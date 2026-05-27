#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

# 1. Add syncing state tracking and current status message to __init__
old_init = '''        self._active_panel = "playlist"
        self._spinner_frame = 0
        self._settings = load_tui_settings()'''

new_init = '''        self._active_panel = "playlist"
        self._spinner_frame = 0
        self._syncing = False
        self._sync_msg = ""
        self._settings = load_tui_settings()'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("init updated")
else:
    print("ERROR: init not found")
    exit(1)

# 2. Add on_mount timer
old_mount = '''    def on_mount(self) -> None:
        saved_theme = self._settings.get("theme", "textual-dark")'''

new_mount = '''    def on_mount(self) -> None:
        self.set_interval(0.1, self._tick_spinner)
        saved_theme = self._settings.get("theme", "textual-dark")'''

if old_mount in content:
    content = content.replace(old_mount, new_mount)
    print("timer added")
else:
    print("ERROR: on_mount not found")
    exit(1)

# 3. Update _set_status and _spin_status
old_status = '''    def _set_status(self, msg: str) -> None:
        self._spinner_frame = 0
        self.query_one("#status-bar", Static).update(msg)

    def _spin_status(self, msg: str) -> None:
        frame = SPINNER_FRAMES[self._spinner_frame % len(SPINNER_FRAMES)]
        self._spinner_frame += 1
        self.query_one("#status-bar", Static).update(f"{frame} {msg}")'''

new_status = '''    def _set_status(self, msg: str) -> None:
        self._syncing = False
        self._sync_msg = ""
        self.query_one("#status-bar", Static).update(msg)

    def _spin_status(self, msg: str) -> None:
        self._syncing = True
        self._sync_msg = msg.strip()

    def _tick_spinner(self) -> None:
        if self._syncing and self._sync_msg:
            frame = SPINNER_FRAMES[self._spinner_frame % len(SPINNER_FRAMES)]
            self._spinner_frame += 1
            self.query_one("#status-bar", Static).update(f"{frame} {self._sync_msg}")'''

if old_status in content:
    content = content.replace(old_status, new_status)
    open(path, "w").write(content)
    print("spinner updated")
else:
    print("ERROR: status methods not found")
    exit(1)
PYEOF

echo "Fix 20 applied successfully"
