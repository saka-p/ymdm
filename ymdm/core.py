from __future__ import annotations
from .modules.config import Config
from .modules.downloader import sync_playlist

def sync_all(config: Config):
    config.ensure_dirs()
    if not config.playlists:
        print("No playlists configured. Add some to ~/.config/ymdm/config.toml")
        return
    for playlist in config.playlists:
        print(f"Syncing: {playlist.name}")
        sync_playlist(playlist, config)
        print(f"Done: {playlist.name}")
