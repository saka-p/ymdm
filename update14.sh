#!/usr/bin/env bash
set -e

cat > ymdm/modules/downloader.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_metadata
from .auth import get_ydl_cookie_opts


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
    for f in output_dir.glob("*"):
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            f.unlink(missing_ok=True)


class _FilenameCollector:
    """Hooks into yt-dlp postprocessing to capture the actual output filename."""

    def __init__(self):
        self.last_filepath: str | None = None

    def __call__(self, info: dict) -> None:
        filepath = info.get("filepath")
        if filepath:
            self.last_filepath = filepath


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
        "format": "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": config.general.format,
            "preferredquality": config.general.audio_quality,
        }],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": True,
        "no_warnings": True,
        "js_runtimes": {"node": {}},
        "remote_components": {"ejs": {"source": "github"}},
    }

    if config.auth.enabled and config.auth.browser:
        ydl_opts.update(get_ydl_cookie_opts(config.auth.browser))

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

            # Use a collector to capture the actual output path from yt-dlp
            collector = _FilenameCollector()
            ydl.add_post_hook(collector)

            try:
                ydl.download([f"https://www.youtube.com/watch?v={video_id}"])
            except Exception as e:
                print(f"  [{i}/{total}] Error: {e}")
                continue

            # Use actual path from yt-dlp, fall back to reconstructed path
            if collector.last_filepath:
                file_path = Path(collector.last_filepath)
            else:
                # Fallback: search output_dir for a file matching the video_id or title
                file_path = _find_downloaded_file(output_dir, title, config.general.format)

            if file_path is None or not file_path.exists():
                print(f"  [{i}/{total}] Warning: could not locate downloaded file for '{title}'")
                continue

            # Find thumbnail using the file's stem (actual filename, not title)
            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
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


def _find_downloaded_file(output_dir: Path, title: str, fmt: str) -> Path | None:
    """Find a downloaded file by trying common filename patterns."""
    # Try exact match first
    exact = output_dir / f"{title}.{fmt}"
    if exact.exists():
        return exact

    # Try sanitized title (yt-dlp strips certain special chars)
    import re
    sanitized = re.sub(r'[\\/*?:"<>|]', "_", title)
    sanitized_path = output_dir / f"{sanitized}.{fmt}"
    if sanitized_path.exists():
        return sanitized_path

    # Last resort: find the most recently modified mp3 in the dir
    mp3_files = sorted(output_dir.glob(f"*.{fmt}"), key=lambda f: f.stat().st_mtime, reverse=True)
    if mp3_files:
        return mp3_files[0]

    return None
EOF

echo "Update 14 applied successfully"
