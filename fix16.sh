#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            if thumbnail_path is None:
                thumbnail_path = _find_playlist_thumbnail(output_dir)
            if config.metadata.embed_thumbnail:'''

new = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            # Fallback: use playlist thumbnail only if track has no thumbnail at all
            # Exclude the track's own base path to avoid false matches
            fallback_thumb = None
            if thumbnail_path is None:
                for f in output_dir.iterdir():
                    if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
                        # Make sure it's not a thumbnail for a different track (same stem)
                        if f.stem != file_path.stem:
                            fallback_thumb = f
                            break
            if config.metadata.embed_thumbnail:'''

if old in content:
    content = content.replace(old, new)
    print("thumbnail logic fixed")
else:
    print("ERROR: could not find thumbnail block")
    exit(1)

# Fix the embed_metadata call to use fallback_thumb
old_embed = '''                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=thumbnail_path,
                    )'''

new_embed = '''                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=thumbnail_path or fallback_thumb,
                    )'''

if old_embed in content:
    content = content.replace(old_embed, new_embed)
    open(path, "w").write(content)
    print("embed_metadata call updated")
else:
    print("ERROR: could not find embed_metadata call")
    exit(1)
PYEOF

echo "Fix 16 applied successfully"
