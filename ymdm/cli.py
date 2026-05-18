import click
from .modules.config import Config
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
        click.echo("No playlists configured.")
        return
    for pl in config.playlists:
        click.echo(f"  {pl.name}  —  {pl.url}")

@main.command()
@click.argument("name")
@click.argument("url")
def add(name, url):
    """Print the TOML snippet to add a playlist."""
    click.echo(f'\n[[playlists.watched]]\nname = "{name}"\nurl  = "{url}"\n')
    click.echo("Add the above to ~/.config/ymdm/config.toml")
