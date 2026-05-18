from __future__ import annotations
from pathlib import Path
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_metadata


def _find_thumbnail(base_path: Path) -> Path | None:
    for ext in (".webp", ".jpg", ".jpeg", ".png"):
        candidate = base_path.with_suffix(ext)
        if candidate.exists():
            return candidate
    return None


def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):
    if keep_dir is not None:
        keep_dir.mkdir(parents=True, exist_ok=True)
        thumbnail_path.rename(keep_dir / thumbnail_path.name)
    else:
        thumbnail_path.unlink(missing_ok=True)


def _cleanup_leftover_images(output_dir: Path):
    """Remove any playlist-level image files left after sync."""
    for f in output_dir.glob("*"):
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            f.unlink(missing_ok=True)


def sync_playlist(playlist: PlaylistEntry, config: Config):
    """Download new tracks from a YouTube Music playlist."""
    import yt_dlp

    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

    thumb_keep_dir: Path | None = None
    if hasattr(config.metadata, "thumbnail_dir") and config.metadata.thumbnail_dir:
        thumb_keep_dir = Path(config.metadata.thumbnail_dir).expanduser()

    ydl_opts = {
        "format": "bestaudio/best",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": config.general.format,
            "preferredquality": config.general.audio_quality,
        }],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": True,
        "no_warnings": True,
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(playlist.url, download=False)
        entries = info.get("entries", [])
        total = len(entries)
        downloaded = 0
        skipped = 0

        print(f"  Found {total} tracks")

        for i, entry in enumerate(entries, start=1):
            video_id = entry.get("id")
            title = entry.get("title", video_id)

            if not video_id:
                continue

            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                print(f"  [{i}/{total}] Skipping: {title}")
                skipped += 1
                continue

            print(f"  [{i}/{total}] Downloading: {title}")
            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])

            file_path = output_dir / f"{title}.{config.general.format}"

            thumbnail_path = _find_thumbnail(output_dir / title)
            if config.metadata.embed_thumbnail and file_path.exists():
                embed_metadata(
                    file_path=file_path,
                    title=title,
                    artist=entry.get("artist") or entry.get("uploader"),
                    album=entry.get("album") or playlist.name,
                    track_number=i,
                    thumbnail_path=thumbnail_path,
                )
                if thumbnail_path:
                    _handle_thumbnail(thumbnail_path, thumb_keep_dir)

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
    print(f"  Done — {downloaded} downloaded, {skipped} skipped")
