#!/usr/bin/env bash
set -e

# state.py — add reconcile and remove_playlist_tracks
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


def remove_playlist_tracks(conn: sqlite3.Connection, playlist_name: str):
    """Remove all tracks belonging to a playlist from the state DB."""
    conn.execute("DELETE FROM tracks WHERE playlist = ?", (playlist_name,))
    conn.commit()


def reconcile(conn: sqlite3.Connection) -> int:
    """Remove DB entries whose files no longer exist on disk. Returns count removed."""
    rows = conn.execute("SELECT video_id, file_path FROM tracks").fetchall()
    stale = [row["video_id"] for row in rows if row["file_path"] and not Path(row["file_path"]).exists()]
    if stale:
        conn.executemany("DELETE FROM tracks WHERE video_id = ?", [(vid,) for vid in stale])
        conn.commit()
    return len(stale)
EOF

# downloader.py — add per-track progress output
cat > ymdm/modules/downloader.py << 'EOF'
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
EOF

# core.py — auto reconcile on sync
cat > ymdm/core.py << 'EOF'
from __future__ import annotations
from .modules.config import Config
from .modules.downloader import sync_playlist
from .modules.state import get_connection, reconcile


def sync_all(config: Config):
    """Sync all watched playlists."""
    config.ensure_dirs()
    if not config.playlists:
        print("No playlists configured. Add some to ~/.config/ymdm/config.toml")
        return

    # Silently clean up any DB entries whose files are missing
    conn = get_connection()
    cleaned = reconcile(conn)
    if cleaned:
        print(f"Reconciled: removed {cleaned} missing track(s) from history")

    for playlist in config.playlists:
        print(f"\nSyncing: {playlist.name}")
        sync_playlist(playlist, config)
EOF

# cli.py — add rescan command, fix remove help text, keep all existing commands
cat > ymdm/cli.py << 'EOF'
import shutil
import click
from .modules.config import Config, CONFIG_PATH
from .modules.state import get_connection, remove_playlist_tracks, reconcile
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
        click.echo("No playlists configured. Use 'ymdm add' to add one.")
        return
    for pl in config.playlists:
        click.echo(f"  {pl.name}  —  {pl.url}")


@main.command()
@click.argument("name")
@click.argument("url")
def add(name, url):
    """Add a YouTube Music playlist to your config."""
    config_path = CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)
    if not config_path.exists():
        config_path.write_text("")

    content = config_path.read_text()
    if url in content:
        click.echo(f"Playlist '{name}' is already in your config.")
        return

    snippet = f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n'
    with open(config_path, "a") as f:
        f.write(snippet)

    click.echo(f"Added '{name}' to {config_path}")


@main.command()
@click.argument("name")
@click.option("--delete-files", is_flag=True, default=False,
              help="Also delete downloaded music files and clear download history for this playlist.")
def remove(name, delete_files):
    """Remove a playlist from your config by name.

    Use --delete-files to also delete the music folder and clear download history,
    so re-adding the playlist will sync it fresh.
    """
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return

    config = Config.load()

    lines = config_path.read_text().splitlines(keepends=True)
    new_lines = []
    skip = False

    for line in lines:
        if line.strip() == "[[playlists.watched]]":
            skip = False
            new_lines.append(("PLACEHOLDER", line))
            continue
        if new_lines and isinstance(new_lines[-1], tuple) and new_lines[-1][0] == "PLACEHOLDER":
            if f'name = "{name}"' in line:
                skip = True
                new_lines.pop()
                continue
            else:
                actual_line = new_lines.pop()[1]
                new_lines.append(actual_line)
        if skip and line.strip().startswith("[["):
            skip = False
        if not skip:
            new_lines.append(line)

    output = []
    for item in new_lines:
        if isinstance(item, tuple):
            output.append(item[1])
        else:
            output.append(item)

    config_path.write_text("".join(output))
    click.echo(f"Removed '{name}' from config.")

    if delete_files:
        music_dir = config.general.music_dir / name
        if music_dir.exists():
            if click.confirm(f"Delete {music_dir} and all its contents?"):
                shutil.rmtree(music_dir)
                click.echo(f"Deleted {music_dir}")
                conn = get_connection()
                remove_playlist_tracks(conn, name)
                click.echo(f"Cleared '{name}' from download history.")
        else:
            click.echo(f"No music folder found at {music_dir}, nothing to delete.")


@main.command()
def rescan():
    """Check download history against disk and remove missing entries.

    Useful if you have manually deleted files and want to re-sync them.
    Runs automatically on every sync, but can be triggered manually here.
    """
    conn = get_connection()
    cleaned = reconcile(conn)
    if cleaned:
        click.echo(f"Removed {cleaned} missing track(s) from download history.")
        click.echo("Run 'ymdm sync' to re-download them.")
    else:
        click.echo("Everything looks good — no missing files found.")
EOF

echo "Update 1 applied successfully"
