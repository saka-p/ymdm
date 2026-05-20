#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''                new_content += f"\n\n[dev]\nenabled = {'true' if new_state else 'false'}\n"'''
new = '''                enabled_str = "true" if new_state else "false"
                new_content += f"\\n\\n[dev]\\nenabled = {enabled_str}\\n"'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: could not find target")
    exit(1)
PYEOF

echo "Fix 10 applied successfully"
