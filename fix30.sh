#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''    click.echo(f"Download directory set to: {path}")
    if updated:
        click.echo(f"Updated {updated} file path(s) in download history.")'''

new = '''    click.echo(f"Download directory set to: {path}")
    if updated:
        click.echo(f"Updated {updated} file path(s) in download history.")
    # Verify files exist at new location
    rows = conn.execute("SELECT file_path FROM tracks WHERE file_path IS NOT NULL").fetchall()
    found = sum(1 for r in rows if r["file_path"] and Path(r["file_path"]).exists())
    missing = len(rows) - found
    click.echo(f"Checking files... ✓ {found} found, ✗ {missing} missing")
    if missing:
        click.echo("Run 'ymdm rescan' to remove missing entries, then 'ymdm sync' to re-download them.")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("CLI set-dir verification added")
else:
    print("ERROR: could not find set-dir output block")
    exit(1)
PYEOF

# Also add verification to TUI action_set_directory
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''            msg = f"Download directory set to: {new_path}"
            if updated:
                msg += f" ({updated} path(s) updated)"
            self._set_status(msg)'''

new = '''            from pathlib import Path as P
            rows = conn.execute("SELECT file_path FROM tracks WHERE file_path IS NOT NULL").fetchall()
            found = sum(1 for r in rows if r["file_path"] and P(r["file_path"]).exists())
            missing = len(rows) - found
            msg = f"Directory set to: {new_path} | ✓ {found} found"
            if missing:
                msg += f", ✗ {missing} missing — press r to rescan"
            self._set_status(msg)'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("TUI set-dir verification added")
else:
    print("ERROR: could not find TUI set-dir output block")
    exit(1)
PYEOF

echo "Fix 30 applied successfully"
