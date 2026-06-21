from __future__ import annotations
from pathlib import Path
from typing import Callable
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_tags
from .auth import get_ydl_cookie_opts

ERROR_LOG = Path.home() / ".config" / "ymdm" / "errors.log"


def _log_error(msg: str) -> None:
    import datetime
    ERROR_LOG.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(ERROR_LOG, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")


class _YdlLogger:
    def __init__(self, playlist_name: str):
        self.playlist_name = playlist_name
        self.errors: list[str] = []

    def debug(self, msg): pass
    def info(self, msg): pass
    def warning(self, msg): pass

    def error(self, msg):
        clean = msg.replace("\x1b[0;31mERROR:\x1b[0m", "ERROR:").strip()
        self.errors.append(clean)
        _log_error(f"yt-dlp [{self.playlist_name}]: {clean}")


def _cleanup_leftover_images(output_dir: Path):
    for f in output_dir.glob("*"):
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            f.unlink(missing_ok=True)


def sync_playlist(
    playlist: PlaylistEntry,
    config: Config,
    progress_cb: Callable[[str], None] | None = None,
) -> list[str]:
    """Download new tracks from a YouTube Music playlist.
    progress_cb: optional callback called with status strings during download.
    Returns a list of error messages for any failed tracks.
    """
    import yt_dlp

    def _status(msg: str) -> None:
        if progress_cb:
            progress_cb(msg)
        else:
            print(msg)

    dev = config.dev.enabled
    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

    ydl_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best",
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": config.general.format,
                "preferredquality": config.general.audio_quality,
            },
            {
                "key": "EmbedThumbnail",
                "already_have_thumbnail": False,
            },
        ],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": not dev,
        "no_warnings": not dev,
        "js_runtimes": {"node": {}},
        "remote_components": {"ejs": {"source": "github"}},
    }

    if config.metadata.crop_thumbnail:
        # Crop YouTube's padded rectangular thumbnail to a clean square,
        # removing the solid-color bars on the sides, before embedding.
        ydl_opts["postprocessor_args"] = {
            "thumbnailsconvertor": [
                "-vf", "crop=ih:ih"
            ]
        }
        ydl_opts["postprocessors"].insert(-1, {
            "key": "FFmpegThumbnailsConvertor",
            "format": "jpg",
        })

    if not dev:
        ydl_opts["logger"] = _YdlLogger(playlist.name)
        ydl_opts["ignoreerrors"] = True

    if config.auth.enabled and config.auth.browser:
        ydl_opts.update(get_ydl_cookie_opts(config.auth.browser))

    logger = ydl_opts.get("logger")

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        if dev:
            info = ydl.extract_info(playlist.url, download=False)
        else:
            try:
                info = ydl.extract_info(playlist.url, download=False)
            except Exception as e:
                msg = f"Failed to fetch playlist '{playlist.name}': {e}"
                _status(f"  Error: {msg}")
                _log_error(msg)
                return [msg]

        entries = info.get("entries", []) if info else []
        total = len(entries)
        downloaded = 0
        skipped = 0
        errors = 0

        _status(f"  Found {total} tracks")

        for i, entry in enumerate(entries, start=1):
            if entry is None:
                _status(f"  [{i}/{total}] Skipping unavailable track — check errors.log")
                _log_error(f"Playlist '{playlist.name}' track {i}/{total}: unavailable")
                errors += 1
                continue

            video_id = entry.get("id")
            title = entry.get("title", video_id)

            if not video_id:
                continue

            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id, playlist.name):
                _status(f"  [{i}/{total}] Skipping: {title}")
                skipped += 1
                continue

            predicted_path = Path(ydl.prepare_filename(entry))
            file_path = predicted_path.with_suffix(f".{config.general.format}")

            # Skip if file already exists on disk (e.g. imported via rescan)
            if file_path.exists():
                _status(f"  [{i}/{total}] Skipping (file exists): {title}")
                if not is_downloaded(conn, video_id, playlist.name):
                    # Remove any fake/local entry for this file first
                    conn.execute(
                        "DELETE FROM tracks WHERE file_path = ? AND video_id LIKE 'local_%'",
                        (str(file_path),)
                    )
                    conn.commit()
                    mark_downloaded(
                        conn,
                        video_id=video_id,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        playlist=playlist.name,
                        file_path=str(file_path),
                    )
                skipped += 1
                continue

            _status(f"  [{i}/{total}] Downloading: {title}")

            if dev:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            else:
                try:
                    ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
                except Exception as e:
                    msg = f"'{title}' ({video_id}): {e}"
                    _status(f"  [{i}/{total}] Error — check errors.log")
                    _log_error(f"Playlist '{playlist.name}' track {msg}")
                    errors += 1
                    continue

            if not file_path.exists():
                _status(f"  [{i}/{total}] Warning — file not found, check errors.log")
                _log_error(f"Playlist '{playlist.name}' track '{title}': file not found after download")
                errors += 1
                continue

            _status(f"  [{i}/{total}] Tagging: {title}")
            try:
                embed_tags(
                    file_path=file_path,
                    title=title,
                    artist=entry.get("artist") or entry.get("uploader"),
                    album=entry.get("album") or playlist.name,
                    track_number=i,
                )
            except Exception as e:
                _log_error(f"Playlist '{playlist.name}' track '{title}': tag embed failed: {e}")

            mark_downloaded(
                conn,
                video_id=video_id,
                title=title,
                artist=entry.get("artist") or entry.get("uploader"),
                album=entry.get("album") or playlist.name,
                playlist=playlist.name,
                file_path=str(file_path),
            )
            downloaded += 1

    _cleanup_leftover_images(output_dir)
    summary = f"  Done — {downloaded} downloaded, {skipped} skipped"
    if errors:
        summary += f", {errors} error(s) — see ~/.config/ymdm/errors.log"
    _status(summary)

    return logger.errors if logger else []
