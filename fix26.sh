#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

new_screen = '''class SetDirectoryScreen(ModalScreen):
    """Modal for setting the music download directory."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Set Download Directory", id="dialog-title")
            yield Label("Current directory:", id="delete-question")
            yield Label("", id="current-dir")
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

if 'class SetDirectoryScreen' not in content:
    content = content.replace('class YmdmCommands(Provider):', new_screen + 'class YmdmCommands(Provider):')
    open(path, "w").write(content)
    print("SetDirectoryScreen added")
else:
    print("Already exists")
PYEOF

echo "Fix 26 applied successfully"
