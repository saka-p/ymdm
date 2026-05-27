#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            # Skip if file already exists on disk (e.g. imported via rescan)
            if file_path.exists():
                _status(f"  [{i}/{total}] Skipping (file exists): {title}")
                # Make sure it's in the DB with the real video_id
                if not is_downloaded(conn, video_id, playlist.name):
                    mark_downloaded(
                        conn,
                        video_id=video_id,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        playlist=playlist.name,
                        file_path=str(file_path),
                    )
                skipped += 1
                continue'''

new = '''            # Skip if file already exists on disk (e.g. imported via rescan)
            if file_path.exists():
                _status(f"  [{i}/{total}] Skipping (file exists): {title}")
                if not is_downloaded(conn, video_id, playlist.name):
                    # Remove any fake/local entry for this file first
                    conn.execute(
                        "DELETE FROM tracks WHERE file_path = ? AND video_id LIKE 'local_%'",
                        (str(file_path),)
                    )
                    conn.commit()
                    mark_downloaded(
                        conn,
                        video_id=video_id,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        playlist=playlist.name,
                        file_path=str(file_path),
                    )
                skipped += 1
                continue'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find block")
    exit(1)
PYEOF

echo "Fix 33 applied successfully"
