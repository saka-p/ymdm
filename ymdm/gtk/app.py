from __future__ import annotations
import threading
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gio

from ..modules.config import Config
from ..modules.state import get_connection, reconcile
from ..modules.downloader import sync_playlist
from .dialogs import (
    AddPlaylistDialog,
    RenamePlaylistDialog,
    DeletePlaylistDialog,
    AuthDialog,
)


CSS = """
.sidebar-list {
    background: transparent;
}
.sidebar-list > row {
    border-radius: 6px;
    margin: 1px 6px;
    padding: 2px 0;
}
.sidebar-list > row:selected {
    background-color: alpha(@accent_color, 0.18);
}
.sidebar-list > row:selected .playlist-name {
    color: @accent_color;
    font-weight: bold;
}
.sidebar-list > row:hover:not(:selected) {
    background-color: alpha(@window_fg_color, 0.06);
}
.playlist-name {
    font-size: 13px;
}
.playlist-count {
    font-size: 11px;
    color: alpha(@window_fg_color, 0.5);
    background-color: alpha(@window_fg_color, 0.08);
    border-radius: 10px;
    padding: 1px 7px;
}
.sidebar-list > row:selected .playlist-count {
    color: @accent_color;
    background-color: alpha(@accent_color, 0.18);
}
.section-label {
    font-size: 10px;
    font-weight: bold;
    color: alpha(@window_fg_color, 0.4);
}
.track-header-label {
    font-size: 11px;
    font-weight: bold;
    color: alpha(@window_fg_color, 0.45);
}
.track-list {
    background: transparent;
}
.track-list > row {
    border-radius: 0;
    margin: 0;
    padding: 0;
}
.track-list > row:hover {
    background-color: alpha(@window_fg_color, 0.04);
}
.track-list > row:selected {
    background-color: alpha(@accent_color, 0.12);
}
.track-list > row:selected .track-title {
    color: @accent_color;
    font-weight: bold;
}
.track-list > row:selected .track-num {
    color: @accent_color;
}
.track-num {
    font-size: 12px;
    color: alpha(@window_fg_color, 0.3);
}
.track-title {
    font-size: 13px;
}
.track-artist {
    font-size: 11px;
    color: alpha(@window_fg_color, 0.5);
}
.track-album {
    font-size: 12px;
    color: alpha(@window_fg_color, 0.4);
}
.track-missing {
    opacity: 0.4;
}
.status-ok {
    color: @success_color;
}
.status-missing {
    color: alpha(@window_fg_color, 0.3);
}
.statusbar {
    border-top: 1px solid alpha(@window_fg_color, 0.1);
    padding: 5px 12px;
}
.statusbar-label {
    font-size: 11px;
    color: alpha(@window_fg_color, 0.5);
}
"""


class YmdmWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="ymdm")
        self.set_default_size(940, 600)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self.config = Config.load()
        self._selected_index = 0
        self._build_ui()
        self._refresh_playlists()

    def _build_ui(self):
        root_tv = Adw.ToolbarView()

        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="ymdm", subtitle="YouTube Music Download Manager"))
        menu_btn = Gtk.MenuButton()
        menu_btn.set_icon_name("open-menu-symbolic")
        menu_btn.set_menu_model(self._build_menu())
        header.pack_end(menu_btn)
        root_tv.add_top_bar(header)

        self._split = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self._split.set_position(240)
        self._split.set_shrink_start_child(False)
        self._split.set_shrink_end_child(False)
        self._split.set_start_child(self._build_sidebar())
        self._split.set_end_child(self._build_main())

        root_tv.set_content(self._split)
        self.set_content(root_tv)

    def _build_menu(self) -> Gio.Menu:
        menu = Gio.Menu()
        menu.append("Set download directory", "win.set_dir")
        menu.append("Authentication", "win.auth")
        menu.append("About ymdm", "win.about")
        self._add_action("auth", self._on_auth)
        self._add_action("set_dir", self._on_set_dir)
        self._add_action("about", self._on_about)
        return menu

    def _add_action(self, name: str, callback):
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", lambda a, p: callback())
        self.add_action(action)

    def _build_sidebar(self) -> Gtk.Widget:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_size_request(210, -1)

        section_lbl = Gtk.Label(label="PLAYLISTS", xalign=0)
        section_lbl.add_css_class("section-label")
        section_lbl.set_margin_start(14)
        section_lbl.set_margin_end(14)
        section_lbl.set_margin_top(12)
        section_lbl.set_margin_bottom(6)
        outer.append(section_lbl)

        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self._playlist_list = Gtk.ListBox()
        self._playlist_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._playlist_list.add_css_class("sidebar-list")
        self._playlist_list.connect("row-selected", self._on_playlist_selected)
        sw.set_child(self._playlist_list)
        outer.append(sw)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        outer.append(sep)

        action_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        action_bar.set_margin_top(5)
        action_bar.set_margin_bottom(5)
        action_bar.set_margin_start(6)
        action_bar.set_margin_end(6)

        add_btn = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Add playlist")
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", lambda _: self._on_add_playlist())
        action_bar.append(add_btn)

        self._rename_btn = Gtk.Button(icon_name="document-edit-symbolic", tooltip_text="Rename playlist")
        self._rename_btn.add_css_class("flat")
        self._rename_btn.set_sensitive(False)
        self._rename_btn.connect("clicked", lambda _: self._on_rename_playlist())
        action_bar.append(self._rename_btn)

        self._delete_btn = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Delete playlist")
        self._delete_btn.add_css_class("flat")
        self._delete_btn.set_sensitive(False)
        self._delete_btn.connect("clicked", lambda _: self._on_delete_playlist())
        action_bar.append(self._delete_btn)

        outer.append(action_bar)
        return outer

    def _build_main(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        toolbar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=7)
        toolbar.set_margin_top(8)
        toolbar.set_margin_bottom(8)
        toolbar.set_margin_start(12)
        toolbar.set_margin_end(12)

        self._search_entry = Gtk.SearchEntry(placeholder_text="Search tracks...", hexpand=True)
        self._search_entry.connect("search-changed", self._on_search_changed)
        toolbar.append(self._search_entry)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, homogeneous=True)

        self._sync_btn = self._make_toolbar_btn("view-refresh-symbolic", "Sync", primary=True)
        self._sync_btn.connect("clicked", lambda _: self._on_sync_selected())
        btn_row.append(self._sync_btn)

        sync_all_btn = self._make_toolbar_btn("emblem-synchronizing-symbolic", "Sync all")
        sync_all_btn.connect("clicked", lambda _: self._on_sync_all())
        btn_row.append(sync_all_btn)

        open_btn = self._make_toolbar_btn("folder-open-symbolic", "Open folder")
        open_btn.connect("clicked", lambda _: self._on_open_folder())
        btn_row.append(open_btn)

        rescan_btn = self._make_toolbar_btn("edit-find-symbolic", "Rescan")
        rescan_btn.connect("clicked", lambda _: self._on_rescan())
        btn_row.append(rescan_btn)

        toolbar.append(btn_row)
        box.append(toolbar)
        box.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header_row.set_margin_start(12)
        header_row.set_margin_end(12)
        header_row.set_margin_top(5)
        header_row.set_margin_bottom(5)

        for text, expand, width in [
            ("#",     False, 32),
            ("TITLE", True,  -1),
            ("ALBUM", False, 160),
            ("",      False, 32),
        ]:
            lbl = Gtk.Label(label=text, xalign=0)
            lbl.add_css_class("track-header-label")
            lbl.set_size_request(width, -1)
            if expand:
                lbl.set_hexpand(True)
            header_row.append(lbl)

        box.append(header_row)
        box.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self._track_list = Gtk.ListBox()
        self._track_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._track_list.add_css_class("track-list")
        self._track_list.set_show_separators(True)
        sw.set_child(self._track_list)
        box.append(sw)

        statusbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        statusbar.add_css_class("statusbar")

        self._status_label = Gtk.Label(label="Ready", xalign=0, hexpand=True)
        self._status_label.add_css_class("statusbar-label")
        self._status_label.set_ellipsize(3)
        statusbar.append(self._status_label)

        self._status_right = Gtk.Label(label="", xalign=1)
        self._status_right.add_css_class("statusbar-label")
        statusbar.append(self._status_right)

        box.append(statusbar)
        return box

    def _make_toolbar_btn(self, icon: str, label: str, primary: bool = False) -> Gtk.Button:
        btn = Gtk.Button(hexpand=True)
        if primary:
            btn.add_css_class("suggested-action")
        else:
            btn.add_css_class("flat")
        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        content.set_halign(Gtk.Align.CENTER)
        content.append(Gtk.Image(icon_name=icon))
        content.append(Gtk.Label(label=label))
        btn.set_child(content)
        return btn

    def _refresh_playlists(self):
        self.config = Config.load()
        while self._playlist_list.get_row_at_index(0):
            self._playlist_list.remove(self._playlist_list.get_row_at_index(0))

        conn = get_connection()
        for pl in self.config.playlists:
            count = conn.execute(
                "SELECT COUNT(*) FROM tracks WHERE playlist = ?", (pl.name,)
            ).fetchone()[0]

            row = Gtk.ListBoxRow()
            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row_box.set_margin_top(5)
            row_box.set_margin_bottom(5)
            row_box.set_margin_start(10)
            row_box.set_margin_end(10)

            icon = Gtk.Image(icon_name="audio-x-generic-symbolic")
            icon.set_pixel_size(16)
            icon.add_css_class("dim-label")
            row_box.append(icon)

            name_lbl = Gtk.Label(label=pl.name, xalign=0, hexpand=True)
            name_lbl.add_css_class("playlist-name")
            name_lbl.set_ellipsize(3)
            row_box.append(name_lbl)

            count_lbl = Gtk.Label(label=str(count))
            count_lbl.add_css_class("playlist-count")
            row_box.append(count_lbl)

            row.set_child(row_box)
            self._playlist_list.append(row)

        has_playlists = bool(self.config.playlists)
        if has_playlists:
            idx = min(self._selected_index, len(self.config.playlists) - 1)
            row = self._playlist_list.get_row_at_index(idx)
            if row:
                self._playlist_list.select_row(row)
        self._rename_btn.set_sensitive(has_playlists)
        self._delete_btn.set_sensitive(has_playlists)
        self._refresh_tracks()

    def _refresh_tracks(self):
        while self._track_list.get_row_at_index(0):
            self._track_list.remove(self._track_list.get_row_at_index(0))

        if not self.config.playlists:
            return
        idx = self._selected_index
        if idx >= len(self.config.playlists):
            return

        playlist = self.config.playlists[idx]
        query = self._search_entry.get_text().strip().lower() if hasattr(self, "_search_entry") else ""

        conn = get_connection()
        tracks = conn.execute(
            "SELECT title, artist, album, file_path FROM tracks WHERE playlist = ? ORDER BY downloaded_at",
            (playlist.name,)
        ).fetchall()

        if not tracks:
            row = Gtk.ListBoxRow()
            lbl = Gtk.Label(label="No tracks downloaded yet -- press Sync")
            lbl.set_margin_top(16)
            lbl.set_margin_bottom(16)
            lbl.add_css_class("dim-label")
            row.set_child(lbl)
            self._track_list.append(row)
            self._update_statusbar(playlist.name, 0, 0)
            return

        found_count = 0
        for i, track in enumerate(tracks, start=1):
            title = track["title"] or ""
            exists = track["file_path"] and Path(track["file_path"]).exists()
            if exists:
                found_count += 1
            if query and query not in title.lower():
                continue

            row = Gtk.ListBoxRow()
            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row_box.set_margin_top(6)
            row_box.set_margin_bottom(6)
            row_box.set_margin_start(12)
            row_box.set_margin_end(12)
            if not exists:
                row_box.add_css_class("track-missing")

            num_lbl = Gtk.Label(label=str(i), xalign=1)
            num_lbl.add_css_class("track-num")
            num_lbl.set_size_request(28, -1)
            row_box.append(num_lbl)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
            text_box.set_valign(Gtk.Align.CENTER)

            title_lbl = Gtk.Label(label=title, xalign=0)
            title_lbl.add_css_class("track-title")
            title_lbl.set_ellipsize(3)
            text_box.append(title_lbl)


            row_box.append(text_box)

            album_lbl = Gtk.Label(label=track["album"] or "", xalign=0)
            album_lbl.add_css_class("track-album")
            album_lbl.set_size_request(150, -1)
            album_lbl.set_ellipsize(3)
            row_box.append(album_lbl)

            if exists:
                status_icon = Gtk.Image(icon_name="emblem-ok-symbolic")
                status_icon.add_css_class("status-ok")
            else:
                status_icon = Gtk.Image(icon_name="dialog-warning-symbolic")
                status_icon.add_css_class("status-missing")
            status_icon.set_pixel_size(14)
            row_box.append(status_icon)

            row.set_child(row_box)
            self._track_list.append(row)

        self._update_statusbar(playlist.name, found_count, len(tracks))

    def _update_statusbar(self, name: str, found: int, total: int):
        self._status_label.set_label(f"{name}  --  {found} of {total} tracks downloaded")
        if total > 0 and found < total:
            self._status_right.set_label(f"{total - found} missing")
        else:
            self._status_right.set_label("")

    def _set_status(self, msg: str):
        GLib.idle_add(self._status_label.set_label, msg)

    def _on_playlist_selected(self, listbox, row):
        if row is None:
            return
        self._selected_index = row.get_index()
        self._refresh_tracks()

    def _on_search_changed(self, entry):
        self._refresh_tracks()

    def _on_sync_selected(self):
        if not self.config.playlists:
            return
        idx = self._selected_index
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self._sync_btn.set_sensitive(False)
        self._set_status(f"Syncing {pl.name}...")

        def run():
            cfg = Config.load()
            errors = sync_playlist(pl, cfg, progress_cb=lambda msg: self._set_status(msg.strip()))
            GLib.idle_add(self._after_sync, pl.name, errors)

        threading.Thread(target=run, daemon=True).start()

    def _on_sync_all(self):
        self._set_status("Syncing all playlists...")

        def run():
            cfg = Config.load()
            all_errors = []
            for pl in cfg.playlists:
                self._set_status(f"Syncing {pl.name}...")
                errors = sync_playlist(pl, cfg, progress_cb=lambda msg: self._set_status(msg.strip()))
                all_errors.extend(errors)
            GLib.idle_add(self._after_sync_all, all_errors)

        threading.Thread(target=run, daemon=True).start()

    def _after_sync(self, name: str, errors: list):
        self._sync_btn.set_sensitive(True)
        self._refresh_playlists()
        if errors:
            self._set_status(f"{name} -- {len(errors)} error(s), see errors.log")
        else:
            self._set_status(f"Synced: {name}")

    def _after_sync_all(self, errors: list):
        self._refresh_playlists()
        if errors:
            self._set_status(f"Sync complete -- {len(errors)} error(s), see errors.log")
        else:
            self._set_status("All playlists synced")

    def _on_open_folder(self):
        if not self.config.playlists:
            return
        pl = self.config.playlists[self._selected_index]
        music_dir = self.config.general.music_dir / pl.name
        if music_dir.exists():
            import subprocess
            subprocess.Popen(["xdg-open", str(music_dir)])
        else:
            self._set_status(f"Folder not found: {music_dir} -- sync first")

    def _on_rescan(self):
        from ..modules.state import import_existing_files
        conn = get_connection()
        imported = import_existing_files(conn, self.config.general.music_dir)
        cleaned = reconcile(conn)
        self._refresh_playlists()
        parts = []
        if imported:
            parts.append(f"{imported} file(s) imported")
        if cleaned:
            parts.append(f"{cleaned} missing track(s) removed")
        self._set_status(
            "Rescan complete -- " + ", ".join(parts) if parts else "Rescan complete -- everything looks good"
        )

    def _on_add_playlist(self):
        from ..modules.utils import sanitize_youtube_url
        from ..modules.config import CONFIG_PATH
        dialog = AddPlaylistDialog(self)
        dialog.connect("close-request", lambda d: self._handle_add(d, sanitize_youtube_url, CONFIG_PATH))
        dialog.present()

    def _handle_add(self, dialog, sanitize_youtube_url, CONFIG_PATH):
        if not dialog.result:
            return False
        name, url = dialog.result
        url = sanitize_youtube_url(url)
        config_path = CONFIG_PATH
        content = config_path.read_text() if config_path.exists() else ""
        if url in content:
            self._set_status(f"'{name}' is already in your config.")
        elif any(pl.name == name for pl in self.config.playlists):
            self._set_status(f"A playlist named '{name}' already exists.")
        else:
            snippet = f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n'
            with open(config_path, "a") as f:
                f.write(snippet)
            self._set_status(f"Added '{name}'.")
        self._refresh_playlists()
        return False

    def _on_rename_playlist(self):
        if not self.config.playlists:
            return
        pl = self.config.playlists[self._selected_index]
        dialog = RenamePlaylistDialog(self, pl.name)
        dialog.connect("close-request", lambda d: self._handle_rename(d, pl.name))
        dialog.present()

    def _handle_rename(self, dialog, old_name: str):
        if not dialog.result:
            return False
        new_name = dialog.result
        from ..modules.config import CONFIG_PATH
        config_path = CONFIG_PATH
        content = config_path.read_text()
        content = content.replace(f'name = "{old_name}"', f'name = "{new_name}"')
        config_path.write_text(content)
        conn = get_connection()
        conn.execute(
            "UPDATE tracks SET playlist = ?, file_path = REPLACE(file_path, ?, ?) WHERE playlist = ?",
            (new_name, f'/{old_name}/', f'/{new_name}/', old_name)
        )
        conn.commit()
        cfg = Config.load()
        old_dir = cfg.general.music_dir / old_name
        new_dir = cfg.general.music_dir / new_name
        if old_dir.exists() and not new_dir.exists():
            old_dir.rename(new_dir)
        self._set_status(f"Renamed '{old_name}' to '{new_name}'.")
        self._refresh_playlists()
        return False

    def _on_delete_playlist(self):
        if not self.config.playlists:
            return
        pl = self.config.playlists[self._selected_index]
        dialog = DeletePlaylistDialog(self, pl.name)
        dialog.connect("close-request", lambda d: self._handle_delete(d, pl.name))
        dialog.present()

    def _handle_delete(self, dialog, playlist_name: str):
        if dialog.result is None:
            return False
        from ..modules.config import CONFIG_PATH
        from ..modules.state import remove_playlist_tracks
        import shutil

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
                if f'name = "{playlist_name}"' in line:
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
        output = [item[1] if isinstance(item, tuple) else item for item in new_lines]
        config_path.write_text("".join(output))

        if dialog.result == 1:
            cfg = Config.load()
            music_dir = cfg.general.music_dir / playlist_name
            if music_dir.exists():
                shutil.rmtree(music_dir)
            conn = get_connection()
            remove_playlist_tracks(conn, playlist_name)
            self._set_status(f"Deleted '{playlist_name}' and all music files.")
        else:
            self._set_status(f"Removed '{playlist_name}' from config.")

        self._selected_index = max(0, self._selected_index - 1)
        self._refresh_playlists()
        return False

    def _on_auth(self):
        current = self.config.auth.browser if self.config.auth.enabled else None
        dialog = AuthDialog(self, current)
        dialog.connect("close-request", self._handle_auth)
        dialog.present()

    def _handle_auth(self, dialog):
        if not dialog.result:
            return False
        from ..modules.config import CONFIG_PATH
        browser = dialog.result
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
        self._set_status(f"Auth enabled using {browser} cookies -- may trigger Google security alerts.")
        return False

    def _on_set_dir(self):
        dialog = Gtk.FileDialog(title="Select download directory")
        dialog.select_folder(self, None, self._handle_set_dir)

    def _handle_set_dir(self, dialog, result):
        try:
            folder = dialog.select_folder_finish(result)
            if not folder:
                return
            new_path = folder.get_path()
            from ..modules.config import CONFIG_PATH
            from ..modules.state import update_music_dir_paths
            config_path = CONFIG_PATH
            old_dir = str(self.config.general.music_dir)
            lines = config_path.read_text().splitlines(keepends=True)
            new_lines = []
            for line in lines:
                if line.strip().startswith("music_dir"):
                    new_lines.append(f'music_dir = "{new_path}"\n')
                else:
                    new_lines.append(line)
            config_path.write_text("".join(new_lines))
            Path(new_path).mkdir(parents=True, exist_ok=True)
            conn = get_connection()
            updated = update_music_dir_paths(conn, old_dir, new_path)
            self.config = Config.load()
            self._set_status(f"Download directory set to: {new_path} ({updated} paths updated)")
        except Exception:
            pass

    def _on_about(self):
        about = Adw.AboutWindow(
            transient_for=self,
            application_name="ymdm",
            application_icon="audio-x-generic",
            version="0.1.0",
            comments="YouTube Music Download Manager",
            license_type=Gtk.License.MIT_X11,
        )
        about.present()
