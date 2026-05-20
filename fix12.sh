#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '''        "ignoreerrors": not config.dev.enabled,'''
new = '''        **({"ignoreerrors": True} if not config.dev.enabled else {}),'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find ignoreerrors line")
    exit(1)
PYEOF

echo "Fix 12 applied successfully"
