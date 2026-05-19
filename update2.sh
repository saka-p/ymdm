#!/usr/bin/env bash
set -e

# auth module (new)
cat > ymdm/modules/auth.py << 'EOF'
from __future__ import annotations
import subprocess


SUPPORTED_BROWSERS = ["firefox", "chrome", "chromium", "brave", "edge", "opera", "vivaldi"]

DESKTOP_TO_BROWSER = {
    "firefox": "firefox",
    "google-chrome": "chrome",
    "chromium": "chromium",
    "chromium-browser": "chromium",
    "brave-browser": "brave",
    "microsoft-edge": "edge",
    "opera": "opera",
    "vivaldi": "vivaldi",
}


def detect_default_browser() -> str | None:
    """Try to detect the default browser via xdg-settings."""
    try:
        result = subprocess.run(
            ["xdg-settings", "get", "default-web-browser"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            desktop = result.stdout.strip().lower().replace(".desktop", "")
            for key, browser in DESKTOP_TO_BROWSER.items():
                if key in desktop:
                    return browser
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def get_ydl_cookie_opts(browser: str) -> dict:
    """Return yt-dlp options for cookie extraction from the given browser."""
    return {"cookiesfrombrowser": (browser, None, None, None)}
EOF

# config.py — add AuthConfig
cat > ymdm/modules/config.py << 'EOF'
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
class PlaylistEntry:
    name: str
    url: str


@dataclass
class Config:
    general: GeneralConfig = field(default_factory=GeneralConfig)
    metadata: MetadataConfig = field(default_factory=MetadataConfig)
    auth: AuthConfig = field(default_factory=AuthConfig)
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
        if a := raw.get("auth"):
            cfg.auth.enabled = a.get("enabled", False)
            cfg.auth.browser = a.get("browser", None)
        if pl := raw.get("playlists", {}).get("watched"):
            cfg.playlists = [PlaylistEntry(p["name"], p["url"]) for p in pl]
        return cfg

    def ensure_dirs(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        self.general.music_dir.mkdir(parents=True, exist_ok=True)
EOF

# downloader.py — inject cookies if auth enabled
cat > ymdm/modules/downloader.py << 'EOF'
from __future__ import annotations
from pathlib import Path
from .config import Config, PlaylistEntry
from .state import get_connection, is_downloaded, mark_downloaded
from .metadata import embed_metadata
from .auth import get_ydl_cookie_opts


def _find_thumbnail(base_path: Path) -> Path | None:
    for ext in (".webp", ".jpg", ".jpeg", ".png"):
        candidate = base_path.with_suffix(ext)
        if candidate.exists():
            return candidate
    return None


def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):
    if keep_dir is not None:
        keep_dir.mkdir(parents=True, exist_ok=True)
        thumbnail_path.rename(keep_dir / thumbnail_path.name)
    else:
        thumbnail_path.unlink(missing_ok=True)


def _cleanup_leftover_images(output_dir: Path):
    for f in output_dir.glob("*"):
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            f.unlink(missing_ok=True)


def sync_playlist(playlist: PlaylistEntry, config: Config):
    """Download new tracks from a YouTube Music playlist."""
    import yt_dlp

    conn = get_connection()
    output_dir = config.general.music_dir / playlist.name
    output_dir.mkdir(parents=True, exist_ok=True)

    thumb_keep_dir: Path | None = None
    if hasattr(config.metadata, "thumbnail_dir") and config.metadata.thumbnail_dir:
        thumb_keep_dir = Path(config.metadata.thumbnail_dir).expanduser()

    ydl_opts = {
        "format": "bestaudio/best",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": config.general.format,
            "preferredquality": config.general.audio_quality,
        }],
        "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
        "writethumbnail": config.metadata.embed_thumbnail,
        "quiet": True,
        "no_warnings": True,
    }

    if config.auth.enabled and config.auth.browser:
        ydl_opts.update(get_ydl_cookie_opts(config.auth.browser))

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(playlist.url, download=False)
        entries = info.get("entries", [])
        total = len(entries)
        downloaded = 0
        skipped = 0

        print(f"  Found {total} tracks")

        for i, entry in enumerate(entries, start=1):
            video_id = entry.get("id")
            title = entry.get("title", video_id)

            if not video_id:
                continue

            if config.general.sync_mode == "new_only" and is_downloaded(conn, video_id):
                print(f"  [{i}/{total}] Skipping: {title}")
                skipped += 1
                continue

            print(f"  [{i}/{total}] Downloading: {title}")
            ydl.download([f"https://music.youtube.com/watch?v={video_id}"])

            file_path = output_dir / f"{title}.{config.general.format}"

            thumbnail_path = _find_thumbnail(output_dir / title)
            if config.metadata.embed_thumbnail and file_path.exists():
                embed_metadata(
                    file_path=file_path,
                    title=title,
                    artist=entry.get("artist") or entry.get("uploader"),
                    album=entry.get("album") or playlist.name,
                    track_number=i,
                    thumbnail_path=thumbnail_path,
                )
                if thumbnail_path:
                    _handle_thumbnail(thumbnail_path, thumb_keep_dir)

            mark_downloaded(
                conn,
                video_id=video_id,
                title=title,
                artist=entry.get("artist") or entry.get("uploader"),
                album=entry.get("album") or playlist.name,
                playlist=playlist.name,
                file_path=str(file_path),
            )
            downloaded += 1

    _cleanup_leftover_images(output_dir)
    print(f"  Done — {downloaded} downloaded, {skipped} skipped")
EOF

# cli.py — add auth command group
cat > ymdm/cli.py << 'EOF'
import shutil
import click
from .modules.config import Config, CONFIG_PATH
from .modules.state import get_connection, remove_playlist_tracks, reconcile
from .modules.auth import detect_default_browser, SUPPORTED_BROWSERS
from .core import sync_all


@click.group()
def main():
    """ymdm — YouTube Music Download Manager"""
    pass


@main.command()
def sync():
    """Sync all watched playlists."""
    config = Config.load()
    sync_all(config)


@main.command(name="list")
def list_playlists():
    """List configured playlists."""
    config = Config.load()
    if not config.playlists:
        click.echo("No playlists configured. Use 'ymdm add' to add one.")
        return
    for pl in config.playlists:
        click.echo(f"  {pl.name}  —  {pl.url}")


@main.command()
@click.argument("name")
@click.argument("url")
def add(name, url):
    """Add a YouTube Music playlist to your config."""
    config_path = CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)
    if not config_path.exists():
        config_path.write_text("")

    content = config_path.read_text()
    if url in content:
        click.echo(f"Playlist '{name}' is already in your config.")
        return

    snippet = f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n'
    with open(config_path, "a") as f:
        f.write(snippet)

    click.echo(f"Added '{name}' to {config_path}")


@main.command()
@click.argument("name")
@click.option("--delete-files", is_flag=True, default=False,
              help="Also delete downloaded music files and clear download history for this playlist.")
def remove(name, delete_files):
    """Remove a playlist from your config by name.

    Use --delete-files to also delete the music folder and clear download
    history, so re-adding the playlist will sync it fresh.
    """
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return

    config = Config.load()

    lines = config_path.read_text().splitlines(keepends=True)
    new_lines = []
    skip = False

    for line in lines:
        if line.strip() == "[[playlists.watched]]":
            skip = False
            new_lines.append(("PLACEHOLDER", line))
            continue
        if new_lines and isinstance(new_lines[-1], tuple) and new_lines[-1][0] == "PLACEHOLDER":
            if f'name = "{name}"' in line:
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
        if isinstance(item, tuple):
            output.append(item[1])
        else:
            output.append(item)

    config_path.write_text("".join(output))
    click.echo(f"Removed '{name}' from config.")

    if delete_files:
        music_dir = config.general.music_dir / name
        if music_dir.exists():
            if click.confirm(f"Delete {music_dir} and all its contents?"):
                shutil.rmtree(music_dir)
                click.echo(f"Deleted {music_dir}")
                conn = get_connection()
                remove_playlist_tracks(conn, name)
                click.echo(f"Cleared '{name}' from download history.")
        else:
            click.echo(f"No music folder found at {music_dir}, nothing to delete.")


@main.command()
def rescan():
    """Check download history against disk and remove missing entries.

    Useful if you manually deleted files and want to re-sync them.
    Runs automatically on every sync, but can be triggered manually here.
    """
    conn = get_connection()
    cleaned = reconcile(conn)
    if cleaned:
        click.echo(f"Removed {cleaned} missing track(s) from download history.")
        click.echo("Run 'ymdm sync' to re-download them.")
    else:
        click.echo("Everything looks good — no missing files found.")


@main.group()
def auth():
    """Manage authentication for private playlists."""
    pass


@auth.command(name="setup")
def auth_setup():
    """Set up browser cookie auth for private playlists."""
    config_path = CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)

    detected = detect_default_browser()
    if detected:
        use_detected = click.confirm(
            f"Detected '{detected}' as your default browser. Use this?",
            default=True
        )
        browser = detected if use_detected else _pick_browser()
    else:
        click.echo("Could not detect your default browser.")
        browser = _pick_browser()

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
    new_content += f"\n\n[auth]\nenabled = true\nbrowser = \"{browser}\"\n"
    config_path.write_text(new_content)

    click.echo(f"\nAuth enabled using {browser} cookies.")
    click.echo("Private playlists will now work on next sync.")


@auth.command(name="status")
def auth_status():
    """Show current auth configuration."""
    config = Config.load()
    if config.auth.enabled and config.auth.browser:
        click.echo(f"Auth enabled — using {config.auth.browser} cookies.")
    else:
        click.echo("Auth disabled — only public playlists will sync.")


@auth.command(name="remove")
def auth_remove():
    """Disable authentication."""
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
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
    click.echo("Auth removed. Only public playlists will sync.")


def _pick_browser() -> str:
    click.echo("\nSupported browsers:")
    for i, b in enumerate(SUPPORTED_BROWSERS, start=1):
        click.echo(f"  {i}. {b}")
    while True:
        choice = click.prompt("Select a browser", type=int)
        if 1 <= choice <= len(SUPPORTED_BROWSERS):
            return SUPPORTED_BROWSERS[choice - 1]
        click.echo("Invalid choice, try again.")
EOF

echo "Update 2 applied successfully"
