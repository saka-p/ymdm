from __future__ import annotations
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw


def _make_dialog(parent, title: str, width: int = 400) -> Adw.Window:
    dialog = Adw.Window(transient_for=parent, modal=True, title=title)
    dialog.set_default_size(width, -1)
    return dialog


def _toolbar_view(header: Adw.HeaderBar, content: Gtk.Widget) -> Adw.ToolbarView:
    tv = Adw.ToolbarView()
    tv.add_top_bar(header)
    tv.set_content(content)
    return tv


# ---------------------------------------------------------------------------
# Add playlist
# ---------------------------------------------------------------------------

class AddPlaylistDialog(Adw.Window):
    def __init__(self, parent):
        super().__init__(transient_for=parent, modal=True, title="Add Playlist")
        self.set_default_size(420, -1)
        self.result: tuple[str, str] | None = None

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)

        self._add_btn = Gtk.Button(label="Add")
        self._add_btn.add_css_class("suggested-action")
        self._add_btn.set_sensitive(False)
        self._add_btn.connect("clicked", self._on_add)
        header.pack_end(self._add_btn)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(16)
        box.set_margin_end(16)

        group = Adw.PreferencesGroup()

        self._name_row = Adw.EntryRow(title="Name")
        self._name_row.connect("changed", self._validate)
        group.add(self._name_row)

        self._url_row = Adw.EntryRow(title="URL")
        self._url_row.connect("changed", self._validate)
        group.add(self._url_row)

        box.append(group)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(box)
        self.set_content(tv)

    def _validate(self, *_):
        self._add_btn.set_sensitive(
            bool(self._name_row.get_text().strip()) and
            bool(self._url_row.get_text().strip())
        )

    def _on_add(self, *_):
        self.result = (
            self._name_row.get_text().strip(),
            self._url_row.get_text().strip(),
        )
        self.close()


# ---------------------------------------------------------------------------
# Rename playlist
# ---------------------------------------------------------------------------

class RenamePlaylistDialog(Adw.Window):
    def __init__(self, parent, current_name: str):
        super().__init__(transient_for=parent, modal=True, title="Rename Playlist")
        self.set_default_size(380, -1)
        self.result: str | None = None

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)

        self._save_btn = Gtk.Button(label="Rename")
        self._save_btn.add_css_class("suggested-action")
        self._save_btn.connect("clicked", self._on_save)
        header.pack_end(self._save_btn)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(16)
        box.set_margin_end(16)

        group = Adw.PreferencesGroup()
        self._name_row = Adw.EntryRow(title="New name")
        self._name_row.set_text(current_name)
        self._name_row.connect("changed", self._validate)
        group.add(self._name_row)
        box.append(group)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(box)
        self.set_content(tv)

        self._current_name = current_name

    def _validate(self, *_):
        new = self._name_row.get_text().strip()
        self._save_btn.set_sensitive(bool(new) and new != self._current_name)

    def _on_save(self, *_):
        self.result = self._name_row.get_text().strip()
        self.close()


# ---------------------------------------------------------------------------
# Delete playlist
# ---------------------------------------------------------------------------

class DeletePlaylistDialog(Adw.Window):
    """Returns 0 = config only, 1 = config + files, None = cancelled."""

    def __init__(self, parent, playlist_name: str):
        super().__init__(transient_for=parent, modal=True, title=f"Delete '{playlist_name}'")
        self.set_default_size(380, -1)
        self.result: int | None = None

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(16)
        box.set_margin_end(16)

        group = Adw.PreferencesGroup(title="What would you like to delete?")

        config_row = Adw.ActionRow(
            title="Remove from config",
            subtitle="Keep downloaded music files on disk",
        )
        config_btn = Gtk.Button(label="Remove")
        config_btn.set_valign(Gtk.Align.CENTER)
        config_btn.connect("clicked", lambda _: self._pick(0))
        config_row.add_suffix(config_btn)
        group.add(config_row)

        files_row = Adw.ActionRow(
            title="Remove and delete files",
            subtitle="Delete music folder and clear download history",
        )
        files_btn = Gtk.Button(label="Delete")
        files_btn.set_valign(Gtk.Align.CENTER)
        files_btn.add_css_class("destructive-action")
        files_btn.connect("clicked", lambda _: self._pick(1))
        files_row.add_suffix(files_btn)
        group.add(files_row)

        box.append(group)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(box)
        self.set_content(tv)

    def _pick(self, choice: int):
        self.result = choice
        self.close()


# ---------------------------------------------------------------------------
# Auth dialog
# ---------------------------------------------------------------------------

BROWSERS = ["firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi"]


class AuthDialog(Adw.Window):
    """Returns selected browser string, or None if cancelled."""

    def __init__(self, parent, current_browser: str | None = None):
        super().__init__(transient_for=parent, modal=True, title="Authentication")
        self.set_default_size(400, -1)
        self.result: str | None = None

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)

        self._save_btn = Gtk.Button(label="Enable")
        self._save_btn.add_css_class("suggested-action")
        self._save_btn.connect("clicked", self._on_save)
        header.pack_end(self._save_btn)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(16)
        box.set_margin_end(16)

        warning = Adw.Banner(
            title="Cookie auth may trigger Google security alerts.",
            revealed=True,
        )
        box.append(warning)

        group = Adw.PreferencesGroup(title="Select your browser")
        self._checks: list[tuple[str, Gtk.CheckButton]] = []
        first_btn = None
        for browser in BROWSERS:
            row = Adw.ActionRow(title=browser)
            if browser == current_browser:
                row.set_subtitle("current")
            check = Gtk.CheckButton()
            check.set_valign(Gtk.Align.CENTER)
            if first_btn is None:
                first_btn = check
            else:
                check.set_group(first_btn)
            if browser == current_browser or (current_browser is None and browser == BROWSERS[0]):
                check.set_active(True)
            row.add_prefix(check)
            row.set_activatable_widget(check)
            group.add(row)
            self._checks.append((browser, check))

        box.append(group)

        tv = Adw.ToolbarView()
        tv.add_top_bar(header)
        tv.set_content(box)
        self.set_content(tv)

    def _on_save(self, *_):
        for browser, check in self._checks:
            if check.get_active():
                self.result = browser
                break
        self.close()
