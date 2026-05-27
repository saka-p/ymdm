#!/usr/bin/env bash
set -e

# Remove all patch/fix/update scripts from git tracking
cd "$(git rev-parse --show-toplevel)" 2>/dev/null || true

# Add to .gitignore
cat >> .gitignore << 'EOF'

# Dev scripts
patch*.sh
fix*.sh
update*.sh
revert*.sh
EOF

# Update CLI add command with duplicate name check
python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''@main.command()
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
        click.echo(f"Playlist \'{name}\' is already in your config.")
        return'''

new = '''@main.command()
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
        click.echo(f"Playlist \'{name}\' is already in your config.")
        return

    # Check for duplicate name
    config = Config.load()
    if any(pl.name == name for pl in config.playlists):
        click.echo(f"A playlist named \'{name}\' already exists. Use a different name or rename the existing one first.")
        return'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("CLI add duplicate check added")
else:
    print("ERROR: could not find add command")
    exit(1)
PYEOF

# Update TUI with duplicate check, thumbnail fallback, and e keybind
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

# 1. Add duplicate name check in action_add_playlist
old_add = '''                if url not in content:
                    snippet = f\'\'\'\\n[[playlists.watched]]\\nname = "{name}"\\nurl  = "{url}"\\n\'\'\'
                    with open(config_path, "a") as f:
                        f.write(snippet)
                    self._set_status(f"Added \'{name}\'.")
                else:
                    self._set_status(f"\'{name}\' is already in your config.")'''

new_add = '''                if url in content:
                    self._set_status(f"'{name}' is already in your config.")
                elif any(pl.name == name for pl in self.config.playlists):
                    self._set_status(f"A playlist named '{name}' already exists. Choose a different name.")
                else:
                    snippet = f\'\'\'\\n[[playlists.watched]]\\nname = "{name}"\\nurl  = "{url}"\\n\'\'\'
                    with open(config_path, "a") as f:
                        f.write(snippet)
                    self._set_status(f"Added '{name}'.")'''

if old_add in content:
    content = content.replace(old_add, new_add)
    print("TUI duplicate name check added")
else:
    print("ERROR: could not find action_add_playlist content block")
    exit(1)

# 2. Add e keybind to BINDINGS
old_bindings = '''        Binding("tab", "switch_panel", "Switch panel", show=False),
        Binding("ctrl+p", "command_palette", "Commands", show=False),'''

new_bindings = '''        Binding("e", "open_location", "Open folder"),
        Binding("tab", "switch_panel", "Switch panel", show=False),
        Binding("ctrl+p", "command_palette", "Commands", show=False),'''

if old_bindings in content:
    content = content.replace(old_bindings, new_bindings)
    print("e keybind added")
else:
    print("ERROR: could not find BINDINGS")
    exit(1)

# 3. Add action_open_location before action_switch_panel
old_switch = '''    def action_switch_panel(self) -> None:'''

new_open_location = '''    def action_open_location(self) -> None:
        """Open the music folder for the selected playlist in the file manager."""
        import subprocess
        if not self.config.playlists:
            return
        idx = self.selected_playlist_index
        if idx >= len(self.config.playlists):
            return
        pl = self.config.playlists[idx]
        music_dir = self.config.general.music_dir / pl.name
        if music_dir.exists():
            subprocess.Popen(["xdg-open", str(music_dir)])
            self._set_status(f"Opening {music_dir}")
        else:
            self._set_status(f"Folder not found: {music_dir} — sync first.")

    def action_switch_panel(self) -> None:'''

if old_switch in content:
    content = content.replace(old_switch, new_open_location)
    print("action_open_location added")
else:
    print("ERROR: could not find action_switch_panel")
    exit(1)

open(path, "w").write(content)
print("tui/app.py patched")
PYEOF

# Update downloader with playlist thumbnail fallback
python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old_thumb = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            if config.metadata.embed_thumbnail:
                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=thumbnail_path,
                    )
                except Exception as e:
                    _log_error(f"Playlist \'{playlist.name}\' track \'{title}\': metadata embed failed: {e}")
                if thumbnail_path:
                    _handle_thumbnail(thumbnail_path, thumb_keep_dir)'''

new_thumb = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            # Fallback: use playlist-level thumbnail if track has none
            if thumbnail_path is None:
                playlist_thumb = _find_playlist_thumbnail(output_dir)
                if playlist_thumb:
                    thumbnail_path = playlist_thumb
            if config.metadata.embed_thumbnail:
                try:
                    embed_metadata(
                        file_path=file_path,
                        title=title,
                        artist=entry.get("artist") or entry.get("uploader"),
                        album=entry.get("album") or playlist.name,
                        track_number=i,
                        thumbnail_path=thumbnail_path,
                    )
                except Exception as e:
                    _log_error(f"Playlist \'{playlist.name}\' track \'{title}\': metadata embed failed: {e}")
                if thumbnail_path and thumbnail_path.parent == output_dir:
                    # Only handle if it's a per-track thumbnail, not the playlist one
                    if _find_thumbnail(file_path.with_suffix("")) is not None:
                        _handle_thumbnail(thumbnail_path, thumb_keep_dir)'''

if old_thumb in content:
    content = content.replace(old_thumb, new_thumb)
    print("thumbnail fallback added")
else:
    print("ERROR: could not find thumbnail block")
    exit(1)

# Add _find_playlist_thumbnail helper after _find_thumbnail
old_helper = '''def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):'''

new_helper = '''def _find_playlist_thumbnail(output_dir: Path) -> Path | None:
    """Find a playlist-level thumbnail in the output directory."""
    for ext in (".jpg", ".jpeg", ".png", ".webp"):
        for f in output_dir.glob(f"*{ext}"):
            if f.is_file():
                return f
    return None


def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):'''

if old_helper in content:
    content = content.replace(old_helper, new_helper)
    print("_find_playlist_thumbnail added")
else:
    print("ERROR: could not find _handle_thumbnail")
    exit(1)

open(path, "w").write(content)
print("downloader.py patched")
PYEOF

echo "Update 17 applied successfully"
