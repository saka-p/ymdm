#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            _status(f"  [{i}/{total}] Downloading: {title}")

            predicted_path = Path(ydl.prepare_filename(entry))
            file_path = predicted_path.with_suffix(f".{config.general.format}")

            if dev:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])'''

new = '''            predicted_path = Path(ydl.prepare_filename(entry))
            file_path = predicted_path.with_suffix(f".{config.general.format}")

            # Skip if file already exists on disk (e.g. imported via rescan)
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
                continue

            _status(f"  [{i}/{total}] Downloading: {title}")

            if dev:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("file exists check added")
else:
    print("ERROR: could not find download block")
    exit(1)
PYEOF

echo "Fix 32 applied successfully"
