#!/usr/bin/env bash
set -e

cat > ymdm/tui/app.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, ListView, ListItem, Label, Static
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
            yield Static("", id="name-input-display")
            yield Label("URL:")
            yield Static("", id="url-input-display")
            yield Label("Enter · next field / confirm   Esc · cancel", id="dialog-hint")

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
            self._update_display()


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

    #playlist-panel:focus-within {
        border: solid $accent;
    }

    #track-panel {
        width: 65%;
        border: solid $primary;
        padding: 0 1;
    }

    #track-panel:focus-within {
        border: solid $accent;
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
        height: 14;
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

    #dialog-hint {
        color: $text-muted;
        padding: 1 0 0 0;
    }

    Footer {
        background: $background;
    }

    Footer > .footer--key {
        background: $background;
        color: $text-muted;
    }

    Footer > .footer--key:hover {
        background: $background;
        color: $text-muted;
    }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("s", "sync_all", "Sync all"),
        Binding("enter", "sync_selected", "Sync selected"),
        Binding("a", "add_playlist", "Add"),
        Binding("d", "delete_playlist", "Delete"),
        Binding("r", "rescan", "Rescan"),
        Binding("tab", "switch_panel", "Switch panel", show=False),
    ]

    def __init__(self):
        super().__init__()
        self.config = Config.load()
        self.selected_playlist_index = 0
        self._active_panel = "playlist"

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="main-container"):
            with Vertical(id="playlist-panel"):
                yield Label("Playlists", id="panel-title")
                yield ListView(id="playlist-list")
            with Vertical(id="track-panel"):
                yield Label("Tracks", id="panel-title")
                yield ListView(id="track-list")
        yield Static("Ready  |  Tab · switch panel", id="status-bar")
        yield Footer()

    def on_mount(self) -> None:
        self._refresh_playlists()
        self.query_one("#playlist-list", ListView).focus()

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

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        # Prevent mouse selection from doing anything
        event.prevent_default()

    def _set_status(self, msg: str) -> None:
        self.query_one("#status-bar", Static).update(msg)

    def action_switch_panel(self) -> None:
        if self._active_panel == "playlist":
            self._active_panel = "track"
            self.query_one("#track-list", ListView).focus()
        else:
            self._active_panel = "playlist"
            self.query_one("#playlist-list", ListView).focus()

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
        self.call_from_thread(self._set_status, "✓ Sync complete.")

    @work(thread=True)
    def _do_sync_selected(self, idx: int) -> None:
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self.call_from_thread(self._set_status, f"Syncing: {pl.name}")
        sync_playlist(pl, self.config)
        self.call_from_thread(self._refresh_playlists)
        self.call_from_thread(self._set_status, f"✓ Done: {pl.name}")

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

echo "Update 8 applied successfully"
