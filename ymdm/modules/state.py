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


def is_downloaded(conn: sqlite3.Connection, video_id: str, playlist: str | None = None) -> bool:
    if playlist:
        return conn.execute(
            "SELECT 1 FROM tracks WHERE video_id = ? AND playlist = ?", (video_id, playlist)
        ).fetchone() is not None
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


def import_existing_files(conn: sqlite3.Connection, music_dir) -> int:
    """Scan music_dir for MP3s not in the DB and register them.
    Uses filename as title and parent folder as playlist name.
    Returns number of files imported.
    """
    from pathlib import Path
    music_path = Path(music_dir)
    if not music_path.exists():
        return 0
    imported = 0
    for playlist_dir in music_path.iterdir():
        if not playlist_dir.is_dir():
            continue
        playlist_name = playlist_dir.name
        for mp3 in playlist_dir.glob("*.mp3"):
            title = mp3.stem
            # Check if this file path is already in DB
            existing = conn.execute(
                "SELECT 1 FROM tracks WHERE file_path = ?", (str(mp3),)
            ).fetchone()
            if existing:
                continue
            # Also check by title+playlist to avoid duplicates
            existing = conn.execute(
                "SELECT 1 FROM tracks WHERE title = ? AND playlist = ?", (title, playlist_name)
            ).fetchone()
            if existing:
                continue
            # Register with a fake video_id based on filename to avoid re-downloads
            fake_id = f"local_{mp3.stem[:40]}"
            conn.execute(
                """INSERT OR IGNORE INTO tracks
                   (video_id, title, playlist, file_path, downloaded_at)
                   VALUES (?, ?, ?, ?, datetime('now'))""",
                (fake_id, title, playlist_name, str(mp3))
            )
            imported += 1
    if imported:
        conn.commit()
    return imported


def update_music_dir_paths(conn: sqlite3.Connection, old_dir: str, new_dir: str) -> int:
    """Update all file paths in the DB when the music directory changes.
    Returns the number of rows updated.
    """
    rows = conn.execute("SELECT video_id, file_path FROM tracks WHERE file_path IS NOT NULL").fetchall()
    updated = 0
    for row in rows:
        if row["file_path"] and row["file_path"].startswith(old_dir):
            new_path = new_dir + row["file_path"][len(old_dir):]
            conn.execute("UPDATE tracks SET file_path = ? WHERE video_id = ?", (new_path, row["video_id"]))
            updated += 1
    if updated:
        conn.commit()
    return updated


def import_existing_files(conn: sqlite3.Connection, music_dir) -> int:
    """Scan music_dir for MP3s not in the DB and register them.
    Uses filename as title and parent folder as playlist name.
    Returns number of files imported.
    """
    from pathlib import Path
    music_path = Path(music_dir)
    if not music_path.exists():
        return 0
    imported = 0
    for playlist_dir in music_path.iterdir():
        if not playlist_dir.is_dir():
            continue
        playlist_name = playlist_dir.name
        for mp3 in playlist_dir.glob("*.mp3"):
            title = mp3.stem
            # Check if this file path is already in DB
            existing = conn.execute(
                "SELECT 1 FROM tracks WHERE file_path = ?", (str(mp3),)
            ).fetchone()
            if existing:
                continue
            # Also check by title+playlist to avoid duplicates
            existing = conn.execute(
                "SELECT 1 FROM tracks WHERE title = ? AND playlist = ?", (title, playlist_name)
            ).fetchone()
            if existing:
                continue
            # Register with a fake video_id based on filename to avoid re-downloads
            fake_id = f"local_{mp3.stem[:40]}"
            conn.execute(
                """INSERT OR IGNORE INTO tracks
                   (video_id, title, playlist, file_path, downloaded_at)
                   VALUES (?, ?, ?, ?, datetime('now'))""",
                (fake_id, title, playlist_name, str(mp3))
            )
            imported += 1
    if imported:
        conn.commit()
    return imported


def update_music_dir_paths(conn: sqlite3.Connection, old_dir: str, new_dir: str) -> int:
    """Update all file paths in the DB when the music directory changes.
    Returns the number of rows updated.
    """
    rows = conn.execute("SELECT video_id, file_path FROM tracks WHERE file_path IS NOT NULL").fetchall()
    updated = 0
    for row in rows:
        if row["file_path"] and row["file_path"].startswith(old_dir):
            new_path = new_dir + row["file_path"][len(old_dir):]
            conn.execute("UPDATE tracks SET file_path = ? WHERE video_id = ?", (new_path, row["video_id"]))
            updated += 1
    if updated:
        conn.commit()
    return updated


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
