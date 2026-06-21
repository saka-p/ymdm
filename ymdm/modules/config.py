from __future__ import annotations
import tomllib
from pathlib import Path
from dataclasses import dataclass, field

CONFIG_DIR = Path.home() / ".config" / "ymdm"
CONFIG_PATH = CONFIG_DIR / "config.toml"
DB_PATH = CONFIG_DIR / "state.db"


@dataclass
class MetadataConfig:
    embed_thumbnail: bool = True
    embed_artist: bool = True
    embed_album: bool = True
    embed_track_number: bool = True
    thumbnail_dir: str | None = None
    crop_thumbnail: bool = True  # Crop YouTube's padded thumbnail to a clean square


@dataclass
class GeneralConfig:
    music_dir: Path = Path.home() / "Music" / "ymdm"
    sync_mode: str = "new_only"
    format: str = "mp3"
    audio_quality: str = "320"


@dataclass
class AuthConfig:
    enabled: bool = False
    browser: str | None = None


@dataclass
class DevConfig:
    enabled: bool = False  # When True, disables ignoreerrors so full tracebacks show


@dataclass
class PlaylistEntry:
    name: str
    url: str


@dataclass
class Config:
    general: GeneralConfig = field(default_factory=GeneralConfig)
    metadata: MetadataConfig = field(default_factory=MetadataConfig)
    auth: AuthConfig = field(default_factory=AuthConfig)
    dev: DevConfig = field(default_factory=DevConfig)
    playlists: list[PlaylistEntry] = field(default_factory=list)

    @classmethod
    def load(cls, path: Path = CONFIG_PATH) -> "Config":
        if not path.exists():
            return cls()
        with open(path, "rb") as f:
            raw = tomllib.load(f)
        cfg = cls()
        if g := raw.get("general"):
            cfg.general.music_dir = Path(g.get("music_dir", cfg.general.music_dir)).expanduser()
            cfg.general.sync_mode = g.get("sync_mode", cfg.general.sync_mode)
            cfg.general.format = g.get("format", cfg.general.format)
            cfg.general.audio_quality = g.get("audio_quality", cfg.general.audio_quality)
        if m := raw.get("metadata"):
            cfg.metadata.embed_thumbnail = m.get("embed_thumbnail", True)
            cfg.metadata.embed_artist = m.get("embed_artist", True)
            cfg.metadata.embed_album = m.get("embed_album", True)
            cfg.metadata.embed_track_number = m.get("embed_track_number", True)
            cfg.metadata.thumbnail_dir = m.get("thumbnail_dir", None)
            cfg.metadata.crop_thumbnail = m.get("crop_thumbnail", True)
        if a := raw.get("auth"):
            cfg.auth.enabled = a.get("enabled", False)
            cfg.auth.browser = a.get("browser", None)
        if d := raw.get("dev"):
            cfg.dev.enabled = d.get("enabled", False)
        if pl := raw.get("playlists", {}).get("watched"):
            cfg.playlists = [PlaylistEntry(p["name"], p["url"]) for p in pl]
        return cfg

    def ensure_dirs(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.general.music_dir.mkdir(parents=True, exist_ok=True)
