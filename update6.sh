#!/usr/bin/env bash
set -e

cat > ymdm/tui/app.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, ListView, ListItem, Label, Static, Input, Button
from textual.containers import Horizontal, Vertical
from textual.binding import Binding
from textual.screen import ModalScreen
from textual import work

from ..modules.config import Config
from ..modules.state import get_connection, reconcile
from ..modules.downloader import sync_playlist


class AddPlaylistScreen(ModalScreen):
    """Modal dialog for adding a new playlist."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Add Playlist", id="dialog-title")
            yield Label("Name:")
            yield Input(placeholder="My Playlist", id="name-input")
            yield Label("URL:")
            yield Input(placeholder="https://music.youtube.com/playlist?list=...", id="url-input")
            with Horizontal(id="dialog-buttons"):
                yield Button("Add", variant="primary", id="btn-add")
                yield Button("Cancel", id="btn-cancel")

    def on_mount(self) -> None:
        self.query_one("#name-input", Input).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-add":
            self._submit()
        else:
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "name-input":
            self.query_one("#url-input", Input).focus()
        elif event.input.id == "url-input":
            self._submit()

    def _submit(self) -> None:
        name = self.query_one("#name-input", Input).value.strip()
        url = self.query_one("#url-input", Input).value.strip()
        if name and url:
            self.dismiss((name, url))
        else:
            self.query_one("#dialog-title", Label).update("Please fill in both fields")


class RenamePlaylistScreen(ModalScreen):
    """Modal dialog for renaming a playlist."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def __init__(self, current_name: str):
        super().__init__()
        self.current_name = current_name

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label(f"Rename '{self.current_name}'", id="dialog-title")
            yield Label("New name:")
            yield Input(value=self.current_name, id="name-input")
            with Horizontal(id="dialog-buttons"):
                yield Button("Rename", variant="primary", id="btn-rename")
                yield Button("Cancel", id="btn-cancel")

    def on_mount(self) -> None:
        inp = self.query_one("#name-input", Input)
        inp.focus()
        inp.cursor_position = len(inp.value)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn-rename":
            new_name = self.query_one("#name-input", Input).value.strip()
            if new_name and new_name != self.current_name:
                self.dismiss(new_name)
            else:
                self.dismiss(None)
        else:
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        new_name = event.value.strip()
        if new_name and new_name != self.current_name:
            self.dismiss(new_name)
        else:
            self.dismiss(None)


class YmdmApp(App):
    """ymdm TUI — YouTube Music Download Manager"""

    CSS = """
    Screen {
        background: $background;
    }

    #main-container {
        height: 1fr;
    }

    #playlist-panel {
        width: 35%;
        border: solid $primary;
        padding: 0 1;
    }

    #track-panel {
        width: 65%;
        border: solid $primary;
        padding: 0 1;
    }

    #panel-title {
        text-style: bold;
        color: $accent;
        padding: 0 0 1 0;
    }

    #status-bar {
        height: 3;
        border: solid $primary;
        padding: 0 1;
        color: $text-muted;
    }

    ListView {
        background: transparent;
        border: none;
    }

    ListItem {
        padding: 0 1;
    }

    ListItem.--highlight {
        background: $accent 20%;
    }

    .track-downloaded {
        color: $success;
    }

    .track-missing {
        color: $text-muted;
    }

    #add-dialog {
        width: 60;
        height: 18;
        border: solid $accent;
        background: $surface;
        padding: 1 2;
        margin: 4 8;
    }

    #dialog-title {
        text-style: bold;
        color: $accent;
        padding: 0 0 1 0;
    }

    #dialog-buttons {
        margin: 1 0 0 0;
        height: 3;
    }

    Button {
        margin: 0 1 0 0;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("s", "sync_all", "Sync all"),
        Binding("enter", "sync_selected", "Sync selected"),
        Binding("a", "add_playlist", "Add"),
        Binding("d", "delete_playlist", "Delete"),
        Binding("n", "rename_playlist", "Rename"),
        Binding("r", "rescan", "Rescan"),
    ]

    def __init__(self):
        super().__init__()
        self.config = Config.load()
        self.selected_playlist_index = 0

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="main-container"):
            with Vertical(id="playlist-panel"):
                yield Label("Playlists", id="panel-title")
                yield ListView(id="playlist-list")
            with Vertical(id="track-panel"):
                yield Label("Tracks", id="panel-title")
                yield ListView(id="track-list")
        yield Static("Ready", id="status-bar")
        yield Footer()

    def on_mount(self) -> None:
        self._refresh_playlists()

    def _refresh_playlists(self) -> None:
        self.config = Config.load()
        playlist_list = self.query_one("#playlist-list", ListView)
        playlist_list.clear()
        conn = get_connection()
        for pl in self.config.playlists:
            count = conn.execute(
                "SELECT COUNT(*) FROM tracks WHERE playlist = ?", (pl.name,)
            ).fetchone()[0]
            playlist_list.append(ListItem(Label(f"{pl.name}  [{count}]")))
        self._refresh_tracks()

    def _refresh_tracks(self) -> None:
        track_list = self.query_one("#track-list", ListView)
        track_list.clear()
        if not self.config.playlists:
            return
        idx = self.selected_playlist_index
        if idx >= len(self.config.playlists):
            return
        playlist = self.config.playlists[idx]
        conn = get_connection()
        tracks = conn.execute(
            "SELECT title, file_path FROM tracks WHERE playlist = ? ORDER BY downloaded_at",
            (playlist.name,)
        ).fetchall()
        if not tracks:
            track_list.append(ListItem(Label("No tracks downloaded yet")))
            return
        for track in tracks:
            exists = track["file_path"] and Path(track["file_path"]).exists()
            icon = "✓" if exists else "✗"
            css_class = "track-downloaded" if exists else "track-missing"
            track_list.append(ListItem(Label(f"{icon} {track['title']}", classes=css_class)))

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        if event.list_view.id == "playlist-list" and event.item is not None:
            idx = event.list_view.index
            if idx is not None:
                self.selected_playlist_index = idx
                self._refresh_tracks()

    def _set_status(self, msg: str) -> None:
        self.query_one("#status-bar", Static).update(msg)

    @work(thread=True)
    def _do_sync_all(self) -> None:
        self.call_from_thread(self._set_status, "Syncing all playlists...")
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            self.call_from_thread(self._set_status, f"Reconciled {cleaned} missing tracks...")
        for pl in self.config.playlists:
            self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
            sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        self.call_from_thread(self._set_status, "Sync complete.")

    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
        sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        self.call_from_thread(self._set_status, f"Done: {pl.name}")

    def action_sync_all(self) -> None:
        self._do_sync_all()

    def action_sync_selected(self) -> None:
        self._do_sync_selected(self.selected_playlist_index)

    def action_rescan(self) -> None:
        conn = get_connection()
        cleaned = reconcile(conn)
        self._refresh_playlists()
        msg = f"Rescan complete — {cleaned} missing track(s) removed." if cleaned else "Rescan complete — everything looks good."
        self._set_status(msg)

    def action_add_playlist(self) -> None:
        def handle_result(result) -> None:
            if result:
                name, url = result
                from ..modules.utils import sanitize_youtube_url
                from ..modules.config import CONFIG_PATH
                url = sanitize_youtube_url(url)
                config_path = CONFIG_PATH
                content = config_path.read_text() if config_path.exists() else ""
                if url not in content:
                    snippet = f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n'
                    with open(config_path, "a") as f:
                        f.write(snippet)
                    self._set_status(f"Added '{name}'.")
                else:
                    self._set_status(f"'{name}' is already in your config.")
                self._refresh_playlists()
        self.push_screen(AddPlaylistScreen(), handle_result)

    def action_rename_playlist(self) -> None:
        if not self.config.playlists:
            return
        idx = self.selected_playlist_index
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]

        def handle_result(new_name) -> None:
            if not new_name:
                return
            from ..modules.config import CONFIG_PATH
            config_path = CONFIG_PATH
            content = config_path.read_text()
            content = content.replace(f'name = "{pl.name}"', f'name = "{new_name}"')
            config_path.write_text(content)
            # Also rename in state DB
            conn = get_connection()
            conn.execute(
                "UPDATE tracks SET playlist = ? WHERE playlist = ?",
                (new_name, pl.name)
            )
            conn.commit()
            # Rename music folder if it exists
            from ..modules.config import Config as Cfg
            cfg = Cfg.load()
            old_dir = cfg.general.music_dir / pl.name
            new_dir = cfg.general.music_dir / new_name
            if old_dir.exists():
                old_dir.rename(new_dir)
            self._set_status(f"Renamed '{pl.name}' to '{new_name}'.")
            self._refresh_playlists()

        self.push_screen(RenamePlaylistScreen(pl.name), handle_result)

    def action_delete_playlist(self) -> None:
        if not self.config.playlists:
            return
        idx = self.selected_playlist_index
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        from ..modules.config import CONFIG_PATH
        config_path = CONFIG_PATH
        lines = config_path.read_text().splitlines(keepends=True)
        new_lines = []
        skip = False
        for line in lines:
            if line.strip() == "[[playlists.watched]]":
                skip = False
                new_lines.append(("PLACEHOLDER", line))
                continue
            if new_lines and isinstance(new_lines[-1], tuple) and new_lines[-1][0] == "PLACEHOLDER":
                if f'name = "{pl.name}"' in line:
                    skip = True
                    new_lines.pop()
                    continue
                else:
                    actual_line = new_lines.pop()[1]
                    new_lines.append(actual_line)
            if skip and line.strip().startswith("[["):
                skip = False
            if not skip:
                new_lines.append(line)
        output = []
        for item in new_lines:
            output.append(item[1] if isinstance(item, tuple) else item)
        config_path.write_text("".join(output))
        self._set_status(f"Removed '{pl.name}' from config.")
        self.selected_playlist_index = max(0, idx - 1)
        self._refresh_playlists()


def run():
    app = YmdmApp()
    app.run()
EOF

echo "Update 6 applied successfully"
