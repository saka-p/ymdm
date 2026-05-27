#!/usr/bin/env bash
set -e

# Update downloader to support a progress callback
cat > ymdm/modules/downloader.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from typing import Callable
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_tags
from .auth import get_ydl_cookie_opts

ERROR_LOG = Path.home() / ".config" / "ymdm" / "errors.log"


def _log_error(msg: str) -> None:
    import datetime
    ERROR_LOG.parent.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(ERROR_LOG, "a") as f:
        f.write(f"[{timestamp}] {msg}\n")


class _YdlLogger:
    def __init__(self, playlist_name: str):
        self.playlist_name = playlist_name
        self.errors: list[str] = []

    def debug(self, msg): pass
    def info(self, msg): pass
    def warning(self, msg): pass

    def error(self, msg):
        clean = msg.replace("\x1b[0;31mERROR:\x1b[0m", "ERROR:").strip()
        self.errors.append(clean)
        _log_error(f"yt-dlp [{self.playlist_name}]: {clean}")


def _cleanup_leftover_images(output_dir: Path):
    for f in output_dir.glob("*"):
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            f.unlink(missing_ok=True)


def sync_playlist(
    playlist: PlaylistEntry,
    config: Config,
    progress_cb: Callable[[str], None] | None = None,
) -> list[str]:
    """Download new tracks from a YouTube Music playlist.
    progress_cb: optional callback called with status strings during download.
    Returns a list of error messages for any failed tracks.
    """
    import yt_dlp

    def _status(msg: str) -> None:
        if progress_cb:
            progress_cb(msg)
        else:
            print(msg)

    dev = config.dev.enabled
    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

    ydl_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best",
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": config.general.format,
                "preferredquality": config.general.audio_quality,
            },
            {
                "key": "EmbedThumbnail",
                "already_have_thumbnail": False,
            },
        ],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": not dev,
        "no_warnings": not dev,
        "js_runtimes": {"node": {}},
        "remote_components": {"ejs": {"source": "github"}},
    }

    if not dev:
        ydl_opts["logger"] = _YdlLogger(playlist.name)
        ydl_opts["ignoreerrors"] = True

    if config.auth.enabled and config.auth.browser:
        ydl_opts.update(get_ydl_cookie_opts(config.auth.browser))

    logger = ydl_opts.get("logger")

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        if dev:
            info = ydl.extract_info(playlist.url, download=False)
        else:
            try:
                info = ydl.extract_info(playlist.url, download=False)
            except Exception as e:
                msg = f"Failed to fetch playlist '{playlist.name}': {e}"
                _status(f"  Error: {msg}")
                _log_error(msg)
                return [msg]

        entries = info.get("entries", []) if info else []
        total = len(entries)
        downloaded = 0
        skipped = 0
        errors = 0

        _status(f"  Found {total} tracks")

        for i, entry in enumerate(entries, start=1):
            if entry is None:
                _status(f"  [{i}/{total}] Skipping unavailable track — check errors.log")
                _log_error(f"Playlist '{playlist.name}' track {i}/{total}: unavailable")
                errors += 1
                continue

            video_id = entry.get("id")
            title = entry.get("title", video_id)

            if not video_id:
                continue

            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                _status(f"  [{i}/{total}] Skipping: {title}")
                skipped += 1
                continue

            _status(f"  [{i}/{total}] Downloading: {title}")

            predicted_path = Path(ydl.prepare_filename(entry))
            file_path = predicted_path.with_suffix(f".{config.general.format}")

            if dev:
                ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
            else:
                try:
                    ydl.download([f"https://music.youtube.com/watch?v={video_id}"])
                except Exception as e:
                    msg = f"'{title}' ({video_id}): {e}"
                    _status(f"  [{i}/{total}] Error — check errors.log")
                    _log_error(f"Playlist '{playlist.name}' track {msg}")
                    errors += 1
                    continue

            if not file_path.exists():
                _status(f"  [{i}/{total}] Warning — file not found, check errors.log")
                _log_error(f"Playlist '{playlist.name}' track '{title}': file not found after download")
                errors += 1
                continue

            _status(f"  [{i}/{total}] Tagging: {title}")
            try:
                embed_tags(
                    file_path=file_path,
                    title=title,
                    artist=entry.get("artist") or entry.get("uploader"),
                    album=entry.get("album") or playlist.name,
                    track_number=i,
                )
            except Exception as e:
                _log_error(f"Playlist '{playlist.name}' track '{title}': tag embed failed: {e}")

            mark_downloaded(
                conn,
                video_id=video_id,
                title=title,
                artist=entry.get("artist") or entry.get("uploader"),
                album=entry.get("album") or playlist.name,
                playlist=playlist.name,
                file_path=str(file_path),
            )
            downloaded += 1

    _cleanup_leftover_images(output_dir)
    summary = f"  Done — {downloaded} downloaded, {skipped} skipped"
    if errors:
        summary += f", {errors} error(s) — see ~/.config/ymdm/errors.log"
    _status(summary)

    return logger.errors if logger else []
EOF

# Update TUI with spinner animation and individual song sync
python3 << 'PYEOF'
import re
path = "ymdm/tui/app.py"
content = open(path).read()

# 1. Add SPINNER_FRAMES constant after imports
old_import_end = '''from ..modules.config import Config
from ..modules.state import get_connection, reconcile
from ..modules.downloader import sync_playlist'''

new_import_end = '''from ..modules.config import Config
from ..modules.state import get_connection, reconcile
from ..modules.downloader import sync_playlist

SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]'''

if old_import_end in content:
    content = content.replace(old_import_end, new_import_end)
    print("SPINNER_FRAMES added")
else:
    print("ERROR: imports not found")
    exit(1)

# 2. Add _spinner_frame to __init__
old_init = '''        self._active_panel = "playlist"
        self._settings = load_tui_settings()'''

new_init = '''        self._active_panel = "playlist"
        self._spinner_frame = 0
        self._settings = load_tui_settings()'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("_spinner_frame added to __init__")
else:
    print("ERROR: __init__ not found")
    exit(1)

# 3. Add _spinner_status helper after _set_status
old_set_status = '''    def _set_status(self, msg: str) -> None:
        self.query_one("#status-bar", Static).update(msg)'''

new_set_status = '''    def _set_status(self, msg: str) -> None:
        self._spinner_frame = 0
        self.query_one("#status-bar", Static).update(msg)

    def _spin_status(self, msg: str) -> None:
        frame = SPINNER_FRAMES[self._spinner_frame % len(SPINNER_FRAMES)]
        self._spinner_frame += 1
        self.query_one("#status-bar", Static).update(f"{frame} {msg}")'''

if old_set_status in content:
    content = content.replace(old_set_status, new_set_status)
    print("_spin_status added")
else:
    print("ERROR: _set_status not found")
    exit(1)

# 4. Update _do_sync_all to use spinner via progress_cb
old_sync_all = '''    @work(thread=True)
    def _do_sync_all(self) -> None:
        self.config = Config.load()
        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            self.call_from_thread(self._set_status, f"Reconciled {cleaned} missing tracks...")
        all_errors = []
        for pl in self.config.playlists:
            self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
            errors = sync_playlist(pl, self.config)
            all_errors.extend(errors)
        self.call_from_thread(self._refresh_playlists)
        if all_errors:
            self.call_from_thread(self._set_status, f"⚠ Sync complete with {len(all_errors)} error(s) — see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, "✓ Sync complete.")'''

new_sync_all = '''    @work(thread=True)
    def _do_sync_all(self) -> None:
        self.config = Config.load()
        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            self.call_from_thread(self._set_status, f"Reconciled {cleaned} missing tracks...")
        all_errors = []
        for pl in self.config.playlists:
            def make_cb(name):
                def cb(msg):
                    self.call_from_thread(self._spin_status, f"{name}: {msg.strip()}")
                return cb
            errors = sync_playlist(pl, self.config, progress_cb=make_cb(pl.name))
            all_errors.extend(errors)
        self.call_from_thread(self._refresh_playlists)
        if all_errors:
            self.call_from_thread(self._set_status, f"⚠ Sync complete with {len(all_errors)} error(s) — see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, "✓ Sync complete.")'''

if old_sync_all in content:
    content = content.replace(old_sync_all, new_sync_all)
    print("_do_sync_all updated with spinner")
else:
    print("ERROR: _do_sync_all not found")
    exit(1)

# 5. Update _do_sync_selected to use spinner
old_sync_sel = '''    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        self.config = Config.load()
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
        errors = sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        if errors:
            self.call_from_thread(self._set_status, f"⚠ Done: {pl.name} — {len(errors)} error(s), see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, f"✓ Done: {pl.name}")'''

new_sync_sel = '''    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        self.config = Config.load()
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        def cb(msg):
            self.call_from_thread(self._spin_status, f"{pl.name}: {msg.strip()}")
        errors = sync_playlist(pl, self.config, progress_cb=cb)
        self.call_from_thread(self._refresh_playlists)
        if errors:
            self.call_from_thread(self._set_status, f"⚠ Done: {pl.name} — {len(errors)} error(s), see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, f"✓ Done: {pl.name}")'''

if old_sync_sel in content:
    content = content.replace(old_sync_sel, new_sync_sel)
    print("_do_sync_selected updated with spinner")
else:
    print("ERROR: _do_sync_selected not found")
    exit(1)

open(path, "w").write(content)
print("tui/app.py done")
PYEOF

echo "Update 18 applied successfully"
