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
