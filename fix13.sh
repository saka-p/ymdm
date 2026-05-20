#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''        try:
            info = ydl.extract_info(playlist.url, download=False)
        except Exception as e:
            msg = f"Failed to fetch playlist '{playlist.name}': {e}"
            print(f"  Error: {msg}")
            _log_error(msg)
            return []'''

new = '''        if config.dev.enabled:
            info = ydl.extract_info(playlist.url, download=False)
        else:
            try:
                info = ydl.extract_info(playlist.url, download=False)
            except Exception as e:
                msg = f"Failed to fetch playlist '{playlist.name}': {e}"
                print(f"  Error: {msg}")
                _log_error(msg)
                return []'''

if old in content:
    content = content.replace(old, new)
    print("extract_info fixed")
else:
    print("ERROR: could not find extract_info block")
    exit(1)

# Also fix the per-track download try/except
old2 = '''            try:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            except Exception as e:
                msg = f"'{title}' ({video_id}): {e}"
                print(f"  [{i}/{total}] Error — check errors.log")
                _log_error(f"Playlist '{playlist.name}' track {msg}")
                errors += 1
                continue'''

new2 = '''            if config.dev.enabled:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            else:
                try:
                    ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
                except Exception as e:
                    msg = f"'{title}' ({video_id}): {e}"
                    print(f"  [{i}/{total}] Error — check errors.log")
                    _log_error(f"Playlist '{playlist.name}' track {msg}")
                    errors += 1
                    continue'''

if old2 in content:
    content = content.replace(old2, new2)
    print("per-track download fixed")
else:
    print("ERROR: could not find per-track download block")
    exit(1)

open(path, "w").write(content)
print("All fixes applied")
PYEOF

echo "Fix 13 applied successfully"
