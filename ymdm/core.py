from __future__ import annotations
from .modules.config import Config
from .modules.downloader import sync_playlist
from .modules.state import get_connection, reconcile


def sync_all(config: Config):
    """Sync all watched playlists."""
    config.ensure_dirs()
    if not config.playlists:
        print("No playlists configured. Add some to ~/.config/ymdm/config.toml")
        return

    # Silently clean up any DB entries whose files are missing
    conn = get_connection()
    cleaned = reconcile(conn)
    if cleaned:
        print(f"Reconciled: removed {cleaned} missing track(s) from history")

    for playlist in config.playlists:
        print(f"\nSyncing: {playlist.name}")
        sync_playlist(playlist, config)
