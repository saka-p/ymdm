#!/usr/bin/env bash
set -e

# 1. Add SetDirectoryScreen to TUI
# 2. Add "Set Download Directory" to command palette
# 3. Update CLI with a set-dir command

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

# Add SetDirectoryScreen after DevMenuScreen
old_insert = '''class YmdmCommands(Provider):'''

new_screen = '''class SetDirectoryScreen(ModalScreen):
    """Modal for setting the music download directory."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Set Download Directory", id="dialog-title")
            yield Label("Current directory:")
            yield Label("", id="current-dir")
            yield Label("New path:")
            yield Input(placeholder="~/Music/ymdm", id="dir-input")
            yield Label("Enter · confirm   Esc · cancel", id="dialog-hint")

    def on_mount(self) -> None:
        from ..modules.config import Config
        cfg = Config.load()
        self.query_one("#current-dir", Label).update(str(cfg.general.music_dir))
        inp = self.query_one("#dir-input", Input)
        inp.value = str(cfg.general.music_dir)
        inp.focus()
        inp.cursor_position = len(inp.value)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        path = event.value.strip()
        if path:
            self.dismiss(path)
        else:
            self.dismiss(None)


'''

if old_insert in content:
    content = content.replace(old_insert, new_screen + old_insert)
    print("SetDirectoryScreen added")
else:
    print("ERROR: could not find insert point")
    exit(1)

# Add to command palette search
old_search = '''        commands = [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
            ("Developer Mode", "Toggle error skipping for debugging", app.action_open_dev_menu),
        ]'''

new_search = '''        commands = [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
            ("Developer Mode", "Toggle error skipping for debugging", app.action_open_dev_menu),
            ("Set Download Directory", "Change where music files are saved", app.action_set_directory),
        ]'''

if old_search in content:
    content = content.replace(old_search, new_search)
    print("search updated")
else:
    print("ERROR: could not find search")
    exit(1)

# Add to discover
old_discover = '''        yield Hit(0.9, "Developer Mode", self.app.action_open_dev_menu,
                  help="Toggle error skipping for debugging")'''

new_discover = '''        yield Hit(0.9, "Developer Mode", self.app.action_open_dev_menu,
                  help="Toggle error skipping for debugging")
        yield Hit(0.8, "Set Download Directory", self.app.action_set_directory,
                  help="Change where music files are saved")'''

if old_discover in content:
    content = content.replace(old_discover, new_discover)
    print("discover updated")
else:
    print("ERROR: could not find discover")
    exit(1)

# Add action_set_directory before action_sync_all
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
                    new_lines.append(f'music_dir = "{new_path}"\n')
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

# Add set-dir CLI command
python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''@main.command()
def rescan():'''

new = '''@main.command(name="set-dir")
@click.argument("path")
def set_directory(path):
    """Set the music download directory."""
    from pathlib import Path
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return
    lines = config_path.read_text().splitlines(keepends=True)
    new_lines = []
    found = False
    for line in lines:
        if line.strip().startswith("music_dir"):
            new_lines.append(f'music_dir = "{path}"\n')
            found = True
        else:
            new_lines.append(line)
    if not found:
        click.echo("Could not find music_dir in config.")
        return
    config_path.write_text("".join(new_lines))
    Path(path).expanduser().mkdir(parents=True, exist_ok=True)
    click.echo(f"Download directory set to: {path}")


@main.command()
def rescan():'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("CLI set-dir command added")
else:
    print("ERROR: could not find rescan command")
    exit(1)
PYEOF

echo "Update 20 applied successfully"
