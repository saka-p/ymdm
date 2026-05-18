#!/usr/bin/env bash
set -e

cat > ymdm/modules/downloader.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_metadata


def _find_thumbnail(base_path: Path) -> Path | None:
    """Find a downloaded thumbnail file for a given base path (no extension)."""
    for ext in (".webp", ".jpg", ".jpeg", ".png"):
        candidate = base_path.with_suffix(ext)
        if candidate.exists():
            return candidate
    return None


def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):
    """Either move thumbnail to keep_dir or delete it."""
    if keep_dir is not None:
        keep_dir.mkdir(parents=True, exist_ok=True)
        thumbnail_path.rename(keep_dir / thumbnail_path.name)
    else:
        thumbnail_path.unlink(missing_ok=True)


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

        for i, entry in enumerate(entries, start=1):
            video_id = entry.get("id")
            if not video_id:
                continue
            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                continue

            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])

            title = entry.get("title", video_id)
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
EOF

cat > ymdm/modules/config.py << 'EOF'
from __future__ import annotations
import tomllib
from pathlib import Path
from dataclasses import dataclass, field

CONFIG_DIR = Path.home() / ".config" / "ymdm"
CONFIG_PATH = CONFIG_DIR / "config.toml"
DB_PATH = CONFIG_DIR / "state.db"

@dataclass
class MetadataConfig:
    embed_thumbnail: bool = True
    embed_artist: bool = True
    embed_album: bool = True
    embed_track_number: bool = True
    thumbnail_dir: str | None = None  # None = delete after embedding

@dataclass
class GeneralConfig:
    music_dir: Path = Path.home() / "Music" / "ymdm"
    sync_mode: str = "new_only"
    format: str = "mp3"
    audio_quality: str = "320"

@dataclass
class PlaylistEntry:
    name: str
    url: str

@dataclass
class Config:
    general: GeneralConfig = field(default_factory=GeneralConfig)
    metadata: MetadataConfig = field(default_factory=MetadataConfig)
    playlists: list[PlaylistEntry] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        if not path.exists():
            return cls()
        with open(path, "rb") as f:
            raw = tomllib.load(f)
        cfg = cls()
        if g := raw.get("general"):
            cfg.general.music_dir = Path(g.get("music_dir", cfg.general.music_dir)).expanduser()
            cfg.general.sync_mode = g.get("sync_mode", cfg.general.sync_mode)
            cfg.general.format = g.get("format", cfg.general.format)
            cfg.general.audio_quality = g.get("audio_quality", cfg.general.audio_quality)
        if m := raw.get("metadata"):
            cfg.metadata.embed_thumbnail = m.get("embed_thumbnail", True)
            cfg.metadata.embed_artist = m.get("embed_artist", True)
            cfg.metadata.embed_album = m.get("embed_album", True)
            cfg.metadata.embed_track_number = m.get("embed_track_number", True)
            cfg.metadata.thumbnail_dir = m.get("thumbnail_dir", None)
        if pl := raw.get("playlists", {}).get("watched"):
            cfg.playlists = [PlaylistEntry(p["name"], p["url"]) for p in pl]
        return cfg

    def ensure_dirs(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.general.music_dir.mkdir(parents=True, exist_ok=True)
EOF

cat > config.toml << 'EOF'
[general]
music_dir = "~/Music/ymdm"
sync_mode = "new_only"
format = "mp3"
audio_quality = "320"

[metadata]
embed_thumbnail = true
embed_artist = true
embed_album = true
embed_track_number = true
# thumbnail_dir = "~/Music/ymdm/.thumbnails"  # uncomment to keep thumbnails

[playlists]
# [[playlists.watched]]
# name = "My Playlist"
# url = "https://music.youtube.com/playlist?list=..."

[scheduler]
enabled = false
interval = "24h"

[tui]
theme = "dark"
accent_color = "#7c3aed"
EOF

echo "Patch applied successfully"
