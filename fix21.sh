#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''    @work(thread=True)
    def _do_sync_all(self) -> None:
        self._set_status("Syncing all playlists...")
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            self._set_status(f"Reconciled {cleaned} missing tracks...")
        for pl in self.config.playlists:
            self._set_status(f"Syncing: {pl.name}")
            sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        self._set_status("Sync complete.")

    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self._set_status(f"Syncing: {pl.name}")
        sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        self._set_status(f"Done: {pl.name}")'''

new = '''    @work(thread=True)
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
                    self.call_from_thread(self._set_status, msg.strip())
                return cb
            errors = sync_playlist(pl, self.config, progress_cb=make_cb(pl.name))
            all_errors.extend(errors)
        self.call_from_thread(self._refresh_playlists)
        if all_errors:
            self.call_from_thread(self._set_status, f"⚠ Sync complete with {len(all_errors)} error(s) — see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, "✓ Sync complete.")

    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        self.config = Config.load()
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        def cb(msg):
            self.call_from_thread(self._set_status, msg.strip())
        errors = sync_playlist(pl, self.config, progress_cb=cb)
        self.call_from_thread(self._refresh_playlists)
        if errors:
            self.call_from_thread(self._set_status, f"⚠ Done: {pl.name} — {len(errors)} error(s), see ~/.config/ymdm/errors.log")
        else:
            self.call_from_thread(self._set_status, f"✓ Done: {pl.name}")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find sync methods")
    exit(1)
PYEOF

echo "Fix 21 applied successfully"
