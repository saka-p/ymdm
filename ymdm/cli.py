import shutil
import click
from .modules.config import Config, CONFIG_PATH
from .modules.state import get_connection, remove_playlist_tracks, reconcile
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
