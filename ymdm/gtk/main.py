from __future__ import annotations
import sys
import os


def run():
    """Entry point for ymdm-gtk binary."""
    # Set WM class so Wayland uses the correct icon
    os.environ.setdefault("GDK_BACKEND", "wayland")
    from .application import YmdmApplication
    app = YmdmApplication()
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    run()
