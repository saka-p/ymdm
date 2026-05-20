#!/usr/bin/env bash
set -e

cat > ymdm/tui/app.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, ListView, ListItem, Label, Static, Input
from textual.containers import Horizontal, Vertical
from textual.binding import Binding
from textual.screen import ModalScreen
from textual import work
from textual.command import Provider, Hit, Hits

from ..modules.config import Config
from ..modules.state import get_connection, reconcile
from ..modules.downloader import sync_playlist


class AddPlaylistScreen(ModalScreen):
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
                self.query_one("#dialog-title", Label).update("Please fill in both fields")


class RenamePlaylistScreen(ModalScreen):
    BINDINGS = [("escape", "dismiss", "Cancel")]

    def __init__(self, current_name: str):
        super().__init__()
        self.current_name = current_name

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label(f"Rename '{self.current_name}'", id="dialog-title")
            yield Label("New name:")
            yield Input(value=self.current_name, id="name-input")
            yield Label("Enter · confirm   Esc · cancel", id="dialog-hint")

    def on_mount(self) -> None:
        inp = self.query_one("#name-input", Input)
        inp.focus()
        inp.cursor_position = len(inp.value)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        new_name = event.value.strip()
        if new_name and new_name != self.current_name:
            self.dismiss(new_name)
        else:
            self.dismiss(None)


class DeletePlaylistScreen(ModalScreen):
    BINDINGS = [("escape", "dismiss", "Cancel")]

    def __init__(self, playlist_name: str):
        super().__init__()
        self.playlist_name = playlist_name

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label(f"Delete '{self.playlist_name}'", id="dialog-title")
            yield Label("What would you like to delete?", id="dialog-hint")
            yield ListView(id="delete-options")
            yield Label("Enter · confirm   Esc · cancel", id="dialog-hint")

    def on_mount(self) -> None:
        lv = self.query_one("#delete-options", ListView)
        lv.append(ListItem(Label("Remove from config only (keep music files)")))
        lv.append(ListItem(Label("Remove from config and delete music files")))
        lv.focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = self.query_one("#delete-options", ListView).index
        self.dismiss(idx)


class AuthSetupScreen(ModalScreen):
    BINDINGS = [("escape", "dismiss", "Cancel")]

    BROWSERS = ["firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi"]

    def __init__(self, current_browser: str | None = None):
        super().__init__()
        self.current_browser = current_browser
        self._selected = 0
        if current_browser and current_browser in self.BROWSERS:
            self._selected = self.BROWSERS.index(current_browser)

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Auth Setup — Private Playlists", id="dialog-title")
            yield Label(
                "⚠ WARNING: Cookie auth may trigger Google security alerts.",
                id="auth-warning"
            )
            yield Label("Select your browser:")
            yield ListView(id="browser-list")
            yield Label("Enter · confirm   Esc · cancel", id="dialog-hint")

    def on_mount(self) -> None:
        browser_list = self.query_one("#browser-list", ListView)
        for b in self.BROWSERS:
            marker = " ◀ current" if b == self.current_browser else ""
            browser_list.append(ListItem(Label(f"  {b}{marker}")))
        browser_list.focus()
        browser_list.index = self._selected

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = self.query_one("#browser-list", ListView).index
        if idx is not None:
            self.dismiss(self.BROWSERS[idx])


class YmdmCommands(Provider):
    """Custom command palette entries for ymdm."""

    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("Auth Setup — configure private playlist access", app.action_auth_setup),
            ("Auth Remove — disable authentication", app.action_auth_remove),
            ("Auth Status — show current auth config", app.action_auth_status),
        ]
        matcher = self.matcher(query)
        for label, action in commands:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=label)


class YmdmApp(App):
    """ymdm TUI — YouTube Music Download Manager"""

    COMMANDS = {YmdmCommands}

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

    #dialog-hint {
        color: $text-muted;
        padding: 1 0 0 0;
    }

    #auth-warning {
        color: $warning;
        padding: 0 0 1 0;
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

    Input {
        border: solid $primary;
        background: $surface;
        margin: 0 0 1 0;
    }

    Input:focus {
        border: solid $accent;
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
        Binding("tab", "switch_panel", "Switch panel", show=False),
        Binding("ctrl+p", "command_palette", "Commands", show=True),
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
        yield Static("Ready  |  Tab · switch panel  |  ^p · commands", id="status-bar")
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
        if event.list_view.id != "playlist-list":
            return
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
            # Update config
            content = config_path.read_text()
            content = content.replace(f'name = "{pl.name}"', f'name = "{new_name}"')
            config_path.write_text(content)
            # Update state DB
            conn = get_connection()
            conn.execute(
                "UPDATE tracks SET playlist = ?, file_path = REPLACE(file_path, ?, ?) WHERE playlist = ?",
                (new_name, f'/{pl.name}/', f'/{new_name}/', pl.name)
            )
            conn.commit()
            # Rename music folder
            cfg = Config.load()
            old_dir = cfg.general.music_dir / pl.name
            new_dir = cfg.general.music_dir / new_name
            if old_dir.exists() and not new_dir.exists():
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

        def handle_result(choice) -> None:
            if choice is None:
                return
            from ..modules.config import CONFIG_PATH
            from ..modules.state import remove_playlist_tracks
            import shutil
            config_path = CONFIG_PATH
            # Remove from config
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

            if choice == 1:
                # Also delete files and clear DB
                cfg = Config.load()
                music_dir = cfg.general.music_dir / pl.name
                if music_dir.exists():
                    shutil.rmtree(music_dir)
                conn = get_connection()
                remove_playlist_tracks(conn, pl.name)
                self._set_status(f"Deleted '{pl.name}' and all music files.")
            else:
                self._set_status(f"Removed '{pl.name}' from config.")

            self.selected_playlist_index = max(0, idx - 1)
            self._refresh_playlists()

        self.push_screen(DeletePlaylistScreen(pl.name), handle_result)

    def action_auth_setup(self) -> None:
        current = self.config.auth.browser if self.config.auth.enabled else None

        def handle_result(browser) -> None:
            if not browser:
                return
            from ..modules.config import CONFIG_PATH
            config_path = CONFIG_PATH
            content = config_path.read_text() if config_path.exists() else ""
            lines = content.splitlines(keepends=True)
            new_lines = []
            skip = False
            for line in lines:
                if line.strip() == "[auth]":
                    skip = True
                    continue
                if skip and line.strip().startswith("[") and line.strip() != "[auth]":
                    skip = False
                if not skip:
                    new_lines.append(line)
            new_content = "".join(new_lines).rstrip()
            new_content += f'\n\n[auth]\nenabled = true\nbrowser = "{browser}"\n'
            config_path.write_text(new_content)
            self.config = Config.load()
            self._set_status(f"⚠ Auth enabled using {browser} cookies — may trigger Google security alerts.")

        self.push_screen(AuthSetupScreen(current), handle_result)

    def action_auth_remove(self) -> None:
        from ..modules.config import CONFIG_PATH
        config_path = CONFIG_PATH
        if not config_path.exists():
            self._set_status("No config file found.")
            return
        content = config_path.read_text()
        lines = content.splitlines(keepends=True)
        new_lines = []
        skip = False
        for line in lines:
            if line.strip() == "[auth]":
                skip = True
                continue
            if skip and line.strip().startswith("[") and line.strip() != "[auth]":
                skip = False
            if not skip:
                new_lines.append(line)
        config_path.write_text("".join(new_lines))
        self.config = Config.load()
        self._set_status("Auth removed — only public playlists will sync.")

    def action_auth_status(self) -> None:
        if self.config.auth.enabled and self.config.auth.browser:
            self._set_status(f"Auth enabled — using {self.config.auth.browser} cookies. ⚠ May trigger Google security alerts.")
        else:
            self._set_status("Auth disabled — only public playlists will sync.")


def run():
    app = YmdmApp()
    app.run()
EOF

echo "Update 10 applied successfully"
