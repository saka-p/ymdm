#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
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
            if config.metadata.embed_thumbnail:
                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=thumbnail_path or fallback_thumb,
                    )
                except Exception as e:
                    _log_error(f"Playlist \'{playlist.name}\' track \'{title}\': metadata embed failed: {e}")
                if thumbnail_path:
                    _handle_thumbnail(thumbnail_path, thumb_keep_dir)'''

new = '''            # Look for a thumbnail whose stem exactly matches the MP3 stem
            # This avoids confusing track thumbnails with playlist thumbnails
            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))

            if config.metadata.embed_thumbnail:
                # Only use playlist thumbnail as fallback if track has none
                # and only after we are certain yt-dlp is done writing
                embed_thumb = thumbnail_path
                if embed_thumb is None:
                    # Find any image whose stem does NOT match any known track stem
                    # i.e. it's a playlist-level image, not a track thumbnail
                    track_stems = {f.stem for f in output_dir.glob("*.mp3")}
                    for f in output_dir.iterdir():
                        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
                            if f.stem not in track_stems:
                                embed_thumb = f
                                break
                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=embed_thumb,
                    )
                except Exception as e:
                    _log_error(f"Playlist \'{playlist.name}\' track \'{title}\': metadata embed failed: {e}")
                if thumbnail_path:
                    _handle_thumbnail(thumbnail_path, thumb_keep_dir)'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find thumbnail block")
    exit(1)
PYEOF

echo "Fix 17 applied successfully"
