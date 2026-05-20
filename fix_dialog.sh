#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''class AddPlaylistScreen(ModalScreen):
    """Modal dialog for adding a new playlist."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Add Playlist", id="dialog-title")
            yield Label("Name:")
            yield Static("", id="name-input-display")
            yield Label("URL:")
            yield Static("", id="url-input-display")
            yield Label("Press Enter to confirm, Escape to cancel", id="dialog-hint")

    def on_mount(self) -> None:
        self._name = ""
        self._url = ""
        self._field = "name"
        self._update_display()

    def _update_display(self) -> None:
        cursor = "█"
        if self._field == "name":
            self.query_one("#name-input-display").update(f"{self._name}{cursor}")
            self.query_one("#url-input-display").update(self._url or "")
        else:
            self.query_one("#name-input-display").update(self._name)
            self.query_one("#url-input-display").update(f"{self._url}{cursor}")

    def on_key(self, event) -> None:
        if event.key == "enter":
            if self._field == "name" and self._name:
                self._field = "url"
                self._update_display()
            elif self._field == "url" and self._url:
                self.dismiss((self._name, self._url))
        elif event.key == "backspace":
            if self._field == "name":
                self._name = self._name[:-1]
            else:
                self._url = self._url[:-1]
            self._update_display()
        elif event.character and event.character.isprintable():
            if self._field == "name":
                self._name += event.character
            else:
                self._url += event.character
            self._update_display()'''

new = '''class AddPlaylistScreen(ModalScreen):
    """Modal dialog for adding a new playlist — keyboard and paste support."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Add Playlist", id="dialog-title")
            yield Label("Name:")
            yield Input(placeholder="My Playlist", id="name-input")
            yield Label("URL:")
            yield Input(placeholder="https://music.youtube.com/playlist?list=...", id="url-input")
            yield Label("Tab · switch fields   Enter · confirm   Esc · cancel", id="dialog-hint")

    def on_mount(self) -> None:
        self.query_one("#name-input", Input).focus()

    def on_key(self, event) -> None:
        if event.key == "tab":
            focused = self.focused
            if focused and focused.id == "name-input":
                self.query_one("#url-input", Input).focus()
            else:
                self.query_one("#name-input", Input).focus()
            event.prevent_default()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "name-input":
            self.query_one("#url-input", Input).focus()
        elif event.input.id == "url-input":
            name = self.query_one("#name-input", Input).value.strip()
            url = self.query_one("#url-input", Input).value.strip()
            if name and url:
                self.dismiss((name, url))
            else:
                self.query_one("#dialog-title", Label).update("Please fill in both fields")'''

if old in content:
    # Also need to add Input to imports
    content = content.replace(
        "from textual.widgets import Header, Footer, ListView, ListItem, Label, Static",
        "from textual.widgets import Header, Footer, ListView, ListItem, Label, Static, Input"
    )
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Dialog fixed successfully")
else:
    print("ERROR: could not find dialog to patch")
    exit(1)
PYEOF

echo "Fix applied successfully"
