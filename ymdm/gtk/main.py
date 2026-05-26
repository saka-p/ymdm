from __future__ import annotations
import sys


def run():
    """Entry point for ymdm-gtk binary."""
    from .application import YmdmApplication
    app = YmdmApplication()
    sys.exit(app.run(sys.argv))


if __name__ == "__main__":
    run()
