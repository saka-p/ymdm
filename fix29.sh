#!/usr/bin/env bash
set -e

# Remove reconcile from TUI sync methods
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

# Remove from _do_sync_all
old1 = '''        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            self.call_from_thread(self._set_status, f"Reconciled {cleaned} missing tracks...")
        all_errors = []'''

new1 = '''        self.call_from_thread(self._set_status, "Syncing all playlists...")
        all_errors = []'''

if old1 in content:
    content = content.replace(old1, new1)
    print("reconcile removed from _do_sync_all")
else:
    print("ERROR: could not find _do_sync_all reconcile block")
    exit(1)

open(path, "w").write(content)
PYEOF

# Remove reconcile from CLI sync command
python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''        config.ensure_dirs()
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            click.echo(f"Reconciled: removed {cleaned} missing track(s) from history")
        click.echo(f"\nSyncing: {matches[0].name}")'''

new = '''        config.ensure_dirs()
        click.echo(f"\nSyncing: {matches[0].name}")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("reconcile removed from CLI sync")
else:
    print("ERROR: could not find CLI sync reconcile block")
    exit(1)
PYEOF

echo "Fix 29 applied successfully"
