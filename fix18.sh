#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            # Look for a thumbnail whose stem exactly matches the MP3 stem
            # This avoids confusing track thumbnails with playlist thumbnails
            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))'''

new = '''            # Use predicted_path stem for thumbnail lookup since yt-dlp sanitizes filenames
            # This matches what yt-dlp actually saves the thumbnail as
            thumbnail_path = _find_thumbnail(predicted_path.with_suffix(""))'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find thumbnail lookup line")
    exit(1)
PYEOF

echo "Fix 18 applied successfully"
