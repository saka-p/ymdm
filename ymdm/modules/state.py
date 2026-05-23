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
