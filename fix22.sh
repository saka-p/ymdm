#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''        all_errors = []
        for pl in self.config.playlists:
            self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
            errors = sync_playlist(pl, self.config)
            all_errors.extend(errors)'''

new = '''        all_errors = []
        for pl in self.config.playlists:
            def make_cb(name):
                def cb(msg):
                    self.call_from_thread(self._set_status, msg.strip())
                return cb
            errors = sync_playlist(pl, self.config, progress_cb=make_cb(pl.name))
            all_errors.extend(errors)'''

if old in content:
    content = content.replace(old, new)
    print("sync_all fixed")
else:
    print("ERROR: sync_all block not found")
    exit(1)

old2 = '''        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
        errors = sync_playlist(pl, self.config)'''

new2 = '''        pl = self.config.playlists[idx]
        def cb(msg):
            self.call_from_thread(self._set_status, msg.strip())
        errors = sync_playlist(pl, self.config, progress_cb=cb)'''

if old2 in content:
    content = content.replace(old2, new2)
    open(path, "w").write(content)
    print("sync_selected fixed")
else:
    print("ERROR: sync_selected block not found")
    exit(1)
PYEOF

echo "Fix 22 applied successfully"
