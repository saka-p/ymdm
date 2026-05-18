#!/usr/bin/env bash
set -e

mkdir -p ymdm/modules ymdm/tui tests docs

# pyproject.toml
cat > pyproject.toml << 'EOF'
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.backends.legacy:build"

[project]
name = "ymdm"
version = "0.1.0"
description = "YouTube Music Download Manager"
requires-python = ">=3.10"
dependencies = [
    "yt-dlp",
    "ytmusicapi",
    "mutagen",
    "rich",
    "textual",
    "click",
]

[project.scripts]
ymdm = "ymdm.cli:main"

[tool.setuptools.packages.find]
where = ["."]
include = ["ymdm*"]
EOF

# config.toml
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

# .gitignore
cat > .gitignore << 'EOF'
__pycache__/
*.pyc
*.pyo
.eggs/
*.egg-info/
dist/
build/
.venv/
venv/
*.db
EOF

# ymdm/__init__.py
cat > ymdm/__init__.py << 'EOF'
__version__ = "0.1.0"
__app_name__ = "ymdm"
EOF

touch ymdm/modules/__init__.py
touch ymdm/tui/__init__.py
touch tests/__init__.py

# ymdm/modules/config.py
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
        if pl := raw.get("playlists", {}).get("watched"):
            cfg.playlists = [PlaylistEntry(p["name"], p["url"]) for p in pl]
        return cfg

    def ensure_dirs(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.general.music_dir.mkdir(parents=True, exist_ok=True)
EOF

# ymdm/modules/state.py
cat > ymdm/modules/state.py << 'EOF'
from __future__ import annotations
import sqlite3
from pathlib import Path
from .config import DB_PATH

def get_connection(db_path: Path = DB_PATH) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    _init_db(conn)
    return conn

def _init_db(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS tracks (
            video_id      TEXT PRIMARY KEY,
            title         TEXT NOT NULL,
            artist        TEXT,
            album         TEXT,
            playlist      TEXT,
            file_path     TEXT,
            downloaded_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS playlists (
            url         TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            last_synced DATETIME
        );
    """)
    conn.commit()

def is_downloaded(conn: sqlite3.Connection, video_id: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM tracks WHERE video_id = ?", (video_id,)
    ).fetchone() is not None

def mark_downloaded(conn: sqlite3.Connection, video_id: str, title: str,
                    artist: str | None, album: str | None,
                    playlist: str | None, file_path: str):
    conn.execute("""
        INSERT OR REPLACE INTO tracks
            (video_id, title, artist, album, playlist, file_path)
        VALUES (?, ?, ?, ?, ?, ?)
    """, (video_id, title, artist, album, playlist, file_path))
    conn.commit()
EOF

# ymdm/modules/downloader.py
cat > ymdm/modules/downloader.py << 'EOF'
from __future__ import annotations
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded

def sync_playlist(playlist: PlaylistEntry, config: Config):
    import yt_dlp
    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

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
        for entry in entries:
            video_id = entry.get("id")
            if not video_id:
                continue
            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                continue
            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            file_path = str(output_dir / f"{entry.get('title', video_id)}.{config.general.format}")
            mark_downloaded(
                conn,
                video_id=video_id,
                title=entry.get("title", ""),
                artist=entry.get("artist") or entry.get("uploader"),
                album=entry.get("album") or playlist.name,
                playlist=playlist.name,
                file_path=file_path,
            )
EOF

# ymdm/modules/metadata.py
cat > ymdm/modules/metadata.py << 'EOF'
from __future__ import annotations
from pathlib import Path

def embed_metadata(file_path: Path, title: str, artist: str | None,
                   album: str | None, track_number: int | None,
                   thumbnail_path: Path | None):
    from mutagen.id3 import ID3, TIT2, TPE1, TALB, TRCK, APIC
    from mutagen.id3 import ID3NoHeaderError
    try:
        tags = ID3(file_path)
    except ID3NoHeaderError:
        tags = ID3()
    tags["TIT2"] = TIT2(encoding=3, text=title)
    if artist:
        tags["TPE1"] = TPE1(encoding=3, text=artist)
    if album:
        tags["TALB"] = TALB(encoding=3, text=album)
    if track_number:
        tags["TRCK"] = TRCK(encoding=3, text=str(track_number))
    if thumbnail_path and thumbnail_path.exists():
        with open(thumbnail_path, "rb") as img:
            tags["APIC"] = APIC(encoding=3, mime="image/jpeg", type=3, desc="Cover", data=img.read())
    tags.save(file_path)
EOF

# ymdm/core.py
cat > ymdm/core.py << 'EOF'
from __future__ import annotations
from .modules.config import Config
from .modules.downloader import sync_playlist

def sync_all(config: Config):
    config.ensure_dirs()
    if not config.playlists:
        print("No playlists configured. Add some to ~/.config/ymdm/config.toml")
        return
    for playlist in config.playlists:
        print(f"Syncing: {playlist.name}")
        sync_playlist(playlist, config)
        print(f"Done: {playlist.name}")
EOF

# ymdm/cli.py
cat > ymdm/cli.py << 'EOF'
import click
from .modules.config import Config
from .core import sync_all

@click.group()
def main():
    """ymdm — YouTube Music Download Manager"""
    pass

@main.command()
def sync():
    """Sync all watched playlists."""
    config = Config.load()
    sync_all(config)

@main.command(name="list")
def list_playlists():
    """List configured playlists."""
    config = Config.load()
    if not config.playlists:
        click.echo("No playlists configured.")
        return
    for pl in config.playlists:
        click.echo(f"  {pl.name}  —  {pl.url}")

@main.command()
@click.argument("name")
@click.argument("url")
def add(name, url):
    """Print the TOML snippet to add a playlist."""
    click.echo(f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n')
    click.echo("Add the above to ~/.config/ymdm/config.toml")
EOF

# ymdm/tui/app.py
cat > ymdm/tui/app.py << 'EOF'
# TUI — coming soon, will be built with Textual
EOF

# README.md
cat > README.md << 'EOF'
# ymdm — YouTube Music Download Manager

A lightweight, config-driven YouTube Music playlist syncer for Linux.

## Install

```bash
pip install -e .
```

## Setup

```bash
mkdir -p ~/.config/ymdm
cp config.toml ~/.config/ymdm/config.toml
nvim ~/.config/ymdm/config.toml
```

## Usage

```bash
ymdm list
ymdm sync
ymdm add "My Playlist" "https://music.youtube.com/playlist?list=..."
```
EOF

echo "ymdm project structure created successfully"
