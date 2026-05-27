#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/state.py"
content = open(path).read()

old = '''def is_downloaded(conn: sqlite3.Connection, video_id: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM tracks WHERE video_id = ?", (video_id,)
    ).fetchone() is not None'''

new = '''def is_downloaded(conn: sqlite3.Connection, video_id: str, playlist: str | None = None) -> bool:
    if playlist:
        return conn.execute(
            "SELECT 1 FROM tracks WHERE video_id = ? AND playlist = ?", (video_id, playlist)
        ).fetchone() is not None
    return conn.execute(
        "SELECT 1 FROM tracks WHERE video_id = ?", (video_id,)
    ).fetchone() is not None'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("state.py fixed")
else:
    print("ERROR: could not find is_downloaded")
    exit(1)
PYEOF

# Update downloader to pass playlist name to is_downloaded
python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):'''
new = '''            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id, playlist.name):'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("downloader.py fixed")
else:
    print("ERROR: could not find is_downloaded call")
    exit(1)
PYEOF

echo "Fix 23 applied successfully"
