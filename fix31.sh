#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/state.py"
content = open(path).read()

old = '''def update_music_dir_paths(conn: sqlite3.Connection, old_dir: str, new_dir: str) -> int:'''

new = '''def import_existing_files(conn: sqlite3.Connection, music_dir) -> int:
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


def update_music_dir_paths(conn: sqlite3.Connection, old_dir: str, new_dir: str) -> int:'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("import_existing_files added to state.py")
else:
    print("ERROR: could not find update_music_dir_paths")
    exit(1)
PYEOF

# Update CLI rescan to also import existing files
python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''@main.command()
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
        click.echo("Everything looks good — no missing files found.")'''

new = '''@main.command()
def rescan():
    """Scan music directory and sync download history with what\'s on disk.

    Imports any MP3s found in the music folder that aren\'t in the download
    history, and removes entries for files that no longer exist.
    """
    from .modules.state import import_existing_files
    config = Config.load()
    conn = get_connection()
    # First import any existing files not in DB
    imported = import_existing_files(conn, config.general.music_dir)
    if imported:
        click.echo(f"Imported {imported} existing file(s) into download history.")
    # Then remove entries for missing files
    cleaned = reconcile(conn)
    if cleaned:
        click.echo(f"Removed {cleaned} missing track(s) from download history.")
    if not imported and not cleaned:
        click.echo("Everything looks good — no changes needed.")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("CLI rescan updated")
else:
    print("ERROR: could not find rescan command")
    exit(1)
PYEOF

# Update TUI rescan to also import
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''    def action_rescan(self) -> None:
        conn = get_connection()
        cleaned = reconcile(conn)
        self._refresh_playlists()
        msg = f"Rescan complete — {cleaned} missing track(s) removed." if cleaned else "Rescan complete — everything looks good."
        self._set_status(msg)'''

new = '''    def action_rescan(self) -> None:
        from .modules.state import import_existing_files
        conn = get_connection()
        imported = import_existing_files(conn, self.config.general.music_dir)
        cleaned = reconcile(conn)
        self._refresh_playlists()
        parts = []
        if imported:
            parts.append(f"{imported} file(s) imported")
        if cleaned:
            parts.append(f"{cleaned} missing track(s) removed")
        msg = "Rescan complete — " + ", ".join(parts) if parts else "Rescan complete — everything looks good."
        self._set_status(msg)'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("TUI rescan updated")
else:
    print("ERROR: could not find action_rescan")
    exit(1)
PYEOF

echo "Fix 31 applied successfully"
