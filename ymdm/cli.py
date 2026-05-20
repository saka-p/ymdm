import shutil
import click
from .modules.config import Config, CONFIG_PATH
from .modules.state import get_connection, remove_playlist_tracks, reconcile
from .modules.auth import detect_default_browser, SUPPORTED_BROWSERS
from .modules.utils import sanitize_youtube_url
from .core import sync_all


@click.group()
def main():
    """ymdm — YouTube Music Download Manager"""
    pass


@main.command()
@click.argument("name", required=False, default=None)
def sync(name):
    """Sync playlists. Pass a playlist name to sync only that one."""
    config = Config.load()
    if name:
        matches = [pl for pl in config.playlists if pl.name == name]
        if not matches:
            click.echo(f"No playlist named '{name}' found. Use 'ymdm list' to see configured playlists.")
            return
        from .modules.downloader import sync_playlist
        from .modules.state import get_connection
        from .modules.state import reconcile
        config.ensure_dirs()
        conn = get_connection()
        cleaned = reconcile(conn)
        if cleaned:
            click.echo(f"Reconciled: removed {cleaned} missing track(s) from history")
        click.echo(f"\nSyncing: {matches[0].name}")
        sync_playlist(matches[0], config)
    else:
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
    url = sanitize_youtube_url(url)

    config_path = CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)
    if not config_path.exists():
        config_path.write_text("")

    content = config_path.read_text()
    if url in content:
        click.echo(f"Playlist '{name}' is already in your config.")
        return

    # Check for duplicate name
    config = Config.load()
    if any(pl.name == name for pl in config.playlists):
        click.echo(f"A playlist named '{name}' already exists. Use a different name or rename the existing one first.")
        return

    # Check for duplicate name
    config = Config.load()
    if any(pl.name == name for pl in config.playlists):
        click.echo(f"A playlist named '{name}' already exists. Use a different name or rename the existing one first.")
        return

    # Check for duplicate name
    config = Config.load()
    if any(pl.name == name for pl in config.playlists):
        click.echo(f"A playlist named '{name}' already exists. Use a different name or rename the existing one first.")
        return

    snippet = f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n'
    with open(config_path, "a") as f:
        f.write(snippet)

    click.echo(f"Added '{name}' to {config_path}")
    click.echo(f"URL: {url}")


@main.command()
@click.argument("old_name")
@click.argument("new_name")
def rename(old_name, new_name):
    """Rename a playlist."""
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return

    config = Config.load()
    matches = [pl for pl in config.playlists if pl.name == old_name]
    if not matches:
        click.echo(f"No playlist named '{old_name}' found.")
        return

    # Update config
    content = config_path.read_text()
    content = content.replace(f'name = "{old_name}"', f'name = "{new_name}"')
    config_path.write_text(content)

    # Update state DB
    conn = get_connection()
    conn.execute(
        "UPDATE tracks SET playlist = ?, file_path = REPLACE(file_path, ?, ?) WHERE playlist = ?",
        (new_name, f'/{old_name}/', f'/{new_name}/', old_name)
    )
    conn.commit()

    # Rename music folder
    from pathlib import Path
    old_dir = config.general.music_dir / old_name
    new_dir = config.general.music_dir / new_name
    if old_dir.exists() and not new_dir.exists():
        old_dir.rename(new_dir)

    click.echo(f"Renamed '{old_name}' to '{new_name}'.")


@main.command()
@click.argument("name")
@click.option("--delete-files", is_flag=True, default=False,
              help="Also delete downloaded music files and clear download history for this playlist. "
                   "Use this when you want to completely remove a playlist and re-sync it fresh later.")
def remove(name, delete_files):
    """Remove a playlist from your config by name.

    By default, only removes the playlist from config — downloaded files are kept on disk.

    Use --delete-files to also delete the music folder and clear download history,
    so re-adding the playlist will sync it fresh.
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

    Useful if you have manually deleted files and want to re-sync them.
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
    """Manage authentication for private playlists.

    WARNING: Cookie-based auth may trigger Google security alerts.
    Use at your own risk and only on accounts you control.
    """
    pass


@auth.command(name="setup")
def auth_setup():
    """Set up browser cookie auth for private playlists.

    \b
    WARNING: This method reads cookies from your browser to authenticate
    with YouTube. Google may flag this as a suspicious login attempt and
    send a security alert to your account. This is a known limitation of
    cookie-based authentication.

    Use at your own risk. Run 'ymdm auth remove' to disable at any time.
    """
    click.echo("WARNING: Cookie-based auth may trigger Google security alerts.")
    click.echo("         Your account is not at risk, but you may receive a notification.")
    click.echo("")

    if not click.confirm("Do you want to continue?", default=False):
        click.echo("Auth setup cancelled.")
        return

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
        click.echo("Note: this may trigger Google security alerts during sync.")
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


@main.command()
def tui():
    """Launch the TUI interface."""
    from .tui.app import run
    run()
