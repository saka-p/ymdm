#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old_discover = '''        yield Hit(
            0.9,
            "Developer Mode",
            self.app.action_open_dev_menu,
            help="Toggle error skipping for debugging",
        )
class YmdmApp(App):'''

new_discover = '''        yield Hit(
            0.9,
            "Developer Mode",
            self.app.action_open_dev_menu,
            help="Toggle error skipping for debugging",
        )
        yield Hit(
            0.8,
            "Set Download Directory",
            self.app.action_set_directory,
            help="Change where music files are saved",
        )
class YmdmApp(App):'''

if old_discover in content:
    content = content.replace(old_discover, new_discover)
    print("discover updated")
else:
    print("ERROR: could not find discover")
    exit(1)

# Add action_set_directory before _do_sync_all
old_action = '''    @work(thread=True)
    def _do_sync_all(self) -> None:'''

new_action = '''    def action_set_directory(self) -> None:
        def handle_result(new_path) -> None:
            if not new_path:
                return
            from ..modules.config import CONFIG_PATH
            from pathlib import Path
            config_path = CONFIG_PATH
            content = config_path.read_text() if config_path.exists() else ""
            lines = content.splitlines(keepends=True)
            new_lines = []
            for line in lines:
                if line.strip().startswith("music_dir"):
                    new_lines.append(f\'music_dir = "{new_path}"\\n\')
                else:
                    new_lines.append(line)
            config_path.write_text("".join(new_lines))
            self.config = Config.load()
            Path(new_path).expanduser().mkdir(parents=True, exist_ok=True)
            self._set_status(f"Download directory set to: {new_path}")
        self.push_screen(SetDirectoryScreen(), handle_result)

    @work(thread=True)
    def _do_sync_all(self) -> None:'''

if old_action in content:
    content = content.replace(old_action, new_action)
    open(path, "w").write(content)
    print("action_set_directory added")
else:
    print("ERROR: could not find _do_sync_all")
    exit(1)
PYEOF

echo "Fix 24 applied successfully"
