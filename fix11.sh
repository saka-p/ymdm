#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old1 = '''    @work(thread=True)
    def _do_sync_all(self) -> None:
        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()'''

new1 = '''    @work(thread=True)
    def _do_sync_all(self) -> None:
        self.config = Config.load()
        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()'''

old2 = '''    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")'''

new2 = '''    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        self.config = Config.load()
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")'''

if old1 in content and old2 in content:
    content = content.replace(old1, new1)
    content = content.replace(old2, new2)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find sync methods")
    exit(1)
PYEOF

echo "Fix 11 applied successfully"
