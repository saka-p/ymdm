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


CSS = b"""
.sidebar-row { padding: 4px 8px; }
.track-title { font-size: 13px; }
.track-artist { font-size: 11px; opacity: 0.6; }
.track-missing { opacity: 0.4; }
.status-ok { color: #27ae60; }
.status-missing { color: #888; }
.log-view { font-family: monospace; font-size: 12px; }
"""


class YmdmWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="ymdm")
        self.set_default_size(900, 580)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self.config = Config.load()
        self._selected_index = 0

        self._build_ui()
        self._refresh_playlists()

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self):
        # Root toolbar view
        root_tv = Adw.ToolbarView()

        # Header bar
        header = Adw.HeaderBar()
        header.set_title_widget(Adw.WindowTitle(title="ymdm", subtitle="YouTube Music Download Manager"))

        menu_btn = Gtk.MenuButton()
        menu_btn.set_icon_name("open-menu-symbolic")
        menu_btn.set_menu_model(self._build_menu())
        header.pack_end(menu_btn)

        root_tv.add_top_bar(header)

        # Main split: sidebar + content
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
        menu.append("Authentication", "win.auth")
        menu.append("Set download directory", "win.set_dir")
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
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_size_request(200, -1)

        # Playlist list
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        self._playlist_list = Gtk.ListBox()
        self._playlist_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._playlist_list.add_css_class("navigation-sidebar")
        self._playlist_list.connect("row-selected", self._on_playlist_selected)
        sw.set_child(self._playlist_list)
        box.append(sw)

        # Sidebar action buttons
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_box.set_margin_top(6)
        btn_box.set_margin_bottom(6)
        btn_box.set_margin_start(8)
        btn_box.set_margin_end(8)

        add_btn = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Add playlist")
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", lambda _: self._on_add_playlist())
        btn_box.append(add_btn)

        self._rename_btn = Gtk.Button(icon_name="document-edit-symbolic", tooltip_text="Rename playlist")
        self._rename_btn.add_css_class("flat")
        self._rename_btn.set_sensitive(False)
        self._rename_btn.connect("clicked", lambda _: self._on_rename_playlist())
        btn_box.append(self._rename_btn)

        self._delete_btn = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Delete playlist")
        self._delete_btn.add_css_class("flat")
        self._delete_btn.set_sensitive(False)
        self._delete_btn.connect("clicked", lambda _: self._on_delete_playlist())
        btn_box.append(self._delete_btn)

        box.append(btn_box)
        return box

    def _build_main(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Toolbar
        toolbar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        toolbar.set_margin_top(8)
        toolbar.set_margin_bottom(8)
        toolbar.set_margin_start(12)
        toolbar.set_margin_end(12)

        # Search entry (top row)
        self._search_entry = Gtk.SearchEntry(placeholder_text="Search tracks…", hexpand=True)
        self._search_entry.connect("search-changed", self._on_search_changed)
        toolbar.append(self._search_entry)

        # Action buttons (bottom row, spread)
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6, homogeneous=True)

        self._sync_btn = Gtk.Button(hexpand=True)
        sync_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        sync_content.set_halign(Gtk.Align.CENTER)
        sync_content.append(Gtk.Image(icon_name="view-refresh-symbolic"))
        sync_content.append(Gtk.Label(label="Sync"))
        self._sync_btn.set_child(sync_content)
        self._sync_btn.add_css_class("suggested-action")
        self._sync_btn.connect("clicked", lambda _: self._on_sync_selected())
        btn_row.append(self._sync_btn)

        sync_all_btn = Gtk.Button(hexpand=True)
        sa_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        sa_content.set_halign(Gtk.Align.CENTER)
        sa_content.append(Gtk.Image(icon_name="emblem-synchronizing-symbolic"))
        sa_content.append(Gtk.Label(label="Sync all"))
        sync_all_btn.set_child(sa_content)
        sync_all_btn.connect("clicked", lambda _: self._on_sync_all())
        btn_row.append(sync_all_btn)

        open_btn = Gtk.Button(hexpand=True)
        open_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        open_content.set_halign(Gtk.Align.CENTER)
        open_content.append(Gtk.Image(icon_name="folder-open-symbolic"))
        open_content.append(Gtk.Label(label="Open folder"))
        open_btn.set_child(open_content)
        open_btn.connect("clicked", lambda _: self._on_open_folder())
        btn_row.append(open_btn)

        rescan_btn = Gtk.Button(hexpand=True)
        rescan_content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        rescan_content.set_halign(Gtk.Align.CENTER)
        rescan_content.append(Gtk.Image(icon_name="edit-find-symbolic"))
        rescan_content.append(Gtk.Label(label="Rescan"))
        rescan_btn.set_child(rescan_content)
        rescan_btn.connect("clicked", lambda _: self._on_rescan())
        btn_row.append(rescan_btn)

        toolbar.append(btn_row)
        box.append(toolbar)
        box.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Track list header
        header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header_row.set_margin_start(12)
        header_row.set_margin_end(12)
        header_row.set_margin_top(4)
        header_row.set_margin_bottom(4)
        for text, expand, width in [("#", False, 32), ("Title", True, -1), ("Album", False, 160), ("", False, 40)]:
            lbl = Gtk.Label(label=text, xalign=0)
            lbl.add_css_class("dim-label")
            lbl.set_size_request(width, -1)
            if expand:
                lbl.set_hexpand(True)
            header_row.append(lbl)
        box.append(header_row)
        box.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Track list
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._track_list = Gtk.ListBox()
        self._track_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._track_list.add_css_class("boxed-list-separate")
        sw.set_child(self._track_list)
        box.append(sw)

        box.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Status bar
        self._status_label = Gtk.Label(label="Ready", xalign=0)
        self._status_label.set_margin_start(12)
        self._status_label.set_margin_end(12)
        self._status_label.set_margin_top(6)
        self._status_label.set_margin_bottom(6)
        self._status_label.add_css_class("dim-label")
        self._status_label.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        box.append(self._status_label)

        return box

    # ------------------------------------------------------------------
    # Data / refresh
    # ------------------------------------------------------------------

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
            row_box.set_margin_top(6)
            row_box.set_margin_bottom(6)
            row_box.set_margin_start(10)
            row_box.set_margin_end(10)
            icon = Gtk.Image(icon_name="audio-x-generic-symbolic")
            icon.add_css_class("dim-label")
            row_box.append(icon)
            lbl = Gtk.Label(label=pl.name, xalign=0, hexpand=True)
            row_box.append(lbl)
            count_lbl = Gtk.Label(label=str(count))
            count_lbl.add_css_class("dim-label")
            row_box.append(count_lbl)
            row.set_child(row_box)
            self._playlist_list.append(row)

        if self.config.playlists:
            idx = min(self._selected_index, len(self.config.playlists) - 1)
            row = self._playlist_list.get_row_at_index(idx)
            if row:
                self._playlist_list.select_row(row)
            self._rename_btn.set_sensitive(True)
            self._delete_btn.set_sensitive(True)
        else:
            self._rename_btn.set_sensitive(False)
            self._delete_btn.set_sensitive(False)

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
            row.set_child(Gtk.Label(label="No tracks downloaded yet — press Sync", margin_top=12, margin_bottom=12))
            self._track_list.append(row)
            return

        for i, track in enumerate(tracks, start=1):
            title = track["title"] or ""
            if query and query not in title.lower():
                continue
            exists = track["file_path"] and Path(track["file_path"]).exists()

            row = Gtk.ListBoxRow()
            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row_box.set_margin_top(5)
            row_box.set_margin_bottom(5)
            row_box.set_margin_start(12)
            row_box.set_margin_end(12)
            if not exists:
                row_box.add_css_class("track-missing")

            num_lbl = Gtk.Label(label=str(i), xalign=1)
            num_lbl.add_css_class("dim-label")
            num_lbl.set_size_request(28, -1)
            row_box.append(num_lbl)

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
            title_lbl = Gtk.Label(label=title, xalign=0)
            title_lbl.add_css_class("track-title")
            title_lbl.set_ellipsize(3)
            text_box.append(title_lbl)
            if track["artist"]:
                artist_lbl = Gtk.Label(label=track["artist"], xalign=0)
                artist_lbl.add_css_class("track-artist")
                artist_lbl.add_css_class("dim-label")
                artist_lbl.set_ellipsize(3)
                text_box.append(artist_lbl)
            row_box.append(text_box)

            album_lbl = Gtk.Label(label=track["album"] or "", xalign=0)
            album_lbl.add_css_class("dim-label")
            album_lbl.set_size_request(150, -1)
            album_lbl.set_ellipsize(3)
            row_box.append(album_lbl)

            status_icon = Gtk.Image(icon_name="emblem-ok-symbolic" if exists else "dialog-error-symbolic")
            if exists:
                status_icon.add_css_class("status-ok")
            else:
                status_icon.add_css_class("status-missing")
            row_box.append(status_icon)

            row.set_child(row_box)
            self._track_list.append(row)

    def _set_status(self, msg: str):
        GLib.idle_add(self._status_label.set_label, msg)

    # ------------------------------------------------------------------
    # Playlist selection
    # ------------------------------------------------------------------

    def _on_playlist_selected(self, listbox, row):
        if row is None:
            return
        self._selected_index = row.get_index()
        self._refresh_tracks()
        self._update_statusbar()

    def _update_statusbar(self):
        if not self.config.playlists or self._selected_index >= len(self.config.playlists):
            return
        pl = self.config.playlists[self._selected_index]
        conn = get_connection()
        tracks = conn.execute(
            "SELECT file_path FROM tracks WHERE playlist = ?", (pl.name,)
        ).fetchall()
        total = len(tracks)
        found = sum(1 for t in tracks if t["file_path"] and Path(t["file_path"]).exists())
        self._set_status(f"{pl.name} — {found}/{total} tracks downloaded")

    # ------------------------------------------------------------------
    # Search
    # ------------------------------------------------------------------

    def _on_search_changed(self, entry):
        self._refresh_tracks()

    # ------------------------------------------------------------------
    # Sync
    # ------------------------------------------------------------------

    def _on_sync_selected(self):
        if not self.config.playlists:
            return
        idx = self._selected_index
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        self._sync_btn.set_sensitive(False)
        self._set_status(f"Syncing {pl.name}…")

        def run():
            cfg = Config.load()
            errors = sync_playlist(pl, cfg, progress_cb=lambda msg: self._set_status(msg.strip()))
            GLib.idle_add(self._after_sync, pl.name, errors)

        threading.Thread(target=run, daemon=True).start()

    def _on_sync_all(self):
        self._set_status("Syncing all playlists…")

        def run():
            cfg = Config.load()
            all_errors = []
            for pl in cfg.playlists:
                self._set_status(f"Syncing {pl.name}…")
                errors = sync_playlist(pl, cfg, progress_cb=lambda msg: self._set_status(msg.strip()))
                all_errors.extend(errors)
            GLib.idle_add(self._after_sync_all, all_errors)

        threading.Thread(target=run, daemon=True).start()

    def _after_sync(self, name: str, errors: list):
        self._sync_btn.set_sensitive(True)
        self._refresh_playlists()
        if errors:
            self._set_status(f"⚠ {name} — {len(errors)} error(s), see errors.log")
        else:
            self._set_status(f"✓ {name} synced")

    def _after_sync_all(self, errors: list):
        self._refresh_playlists()
        if errors:
            self._set_status(f"⚠ Sync complete — {len(errors)} error(s), see errors.log")
        else:
            self._set_status("✓ All playlists synced")

    # ------------------------------------------------------------------
    # Open folder
    # ------------------------------------------------------------------

    def _on_open_folder(self):
        if not self.config.playlists:
            return
        pl = self.config.playlists[self._selected_index]
        music_dir = self.config.general.music_dir / pl.name
        if music_dir.exists():
            import subprocess
            subprocess.Popen(["xdg-open", str(music_dir)])
        else:
            self._set_status(f"Folder not found: {music_dir} — sync first")

    # ------------------------------------------------------------------
    # Rescan
    # ------------------------------------------------------------------

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
        self._set_status("Rescan complete — " + ", ".join(parts) if parts else "Rescan complete — everything looks good")

    # ------------------------------------------------------------------
    # Add / rename / delete playlist
    # ------------------------------------------------------------------

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

    # ------------------------------------------------------------------
    # Auth
    # ------------------------------------------------------------------

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
        self._set_status(f"⚠ Auth enabled using {browser} cookies — may trigger Google security alerts.")
        return False

    # ------------------------------------------------------------------
    # Set directory
    # ------------------------------------------------------------------

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

    # ------------------------------------------------------------------
    # About
    # ------------------------------------------------------------------

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
