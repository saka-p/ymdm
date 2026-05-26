from __future__ import annotations
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw

from .app import YmdmWindow


class YmdmApplication(Adw.Application):
    def __init__(self):
        super().__init__(application_id="io.github.saka_p.ymdm")
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        win = YmdmWindow(app)
        win.present()
