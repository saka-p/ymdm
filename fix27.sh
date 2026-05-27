#!/usr/bin/env bash
set -e

# 1. Add update_music_dir_paths to state.py
python3 << 'PYEOF'
path = "ymdm/modules/state.py"
content = open(path).read()

old = '''def remove_playlist_tracks(conn: sqlite3.Connection, playlist_name: str):'''

new = '''def update_music_dir_paths(conn: sqlite3.Connection, old_dir: str, new_dir: str) -> int:
    """Update all file paths in the DB when the music directory changes.
    Returns the number of rows updated.
    """
    rows = conn.execute("SELECT video_id, file_path FROM tracks WHERE file_path IS NOT NULL").fetchall()
    updated = 0
    for row in rows:
        if row["file_path"] and row["file_path"].startswith(old_dir):
            new_path = new_dir + row["file_path"][len(old_dir):]
            conn.execute("UPDATE tracks SET file_path = ? WHERE video_id = ?", (new_path, row["video_id"]))
            updated += 1
    if updated:
        conn.commit()
    return updated


def remove_playlist_tracks(conn: sqlite3.Connection, playlist_name: str):'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("state.py updated")
else:
    print("ERROR: could not find remove_playlist_tracks")
    exit(1)
PYEOF

# 2. Update CLI set-dir to also update DB paths
python3 << 'PYEOF'
path = "ymdm/cli.py"
content = open(path).read()

old = '''@main.command(name="set-dir")
@click.argument("path")
def set_directory(path):
    """Set the music download directory."""
    from pathlib import Path
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return
    lines = config_path.read_text().splitlines(keepends=True)
    new_lines = []
    found = False
    for line in lines:
        if line.strip().startswith("music_dir"):
            new_lines.append(f\'music_dir = "{path}"\\n\')
            found = True
        else:
            new_lines.append(line)
    if not found:
        click.echo("Could not find music_dir in config.")
        return
    config_path.write_text("".join(new_lines))
    Path(path).expanduser().mkdir(parents=True, exist_ok=True)
    click.echo(f"Download directory set to: {path}")'''

new = '''@main.command(name="set-dir")
@click.argument("path")
def set_directory(path):
    """Set the music download directory and update file path records."""
    from pathlib import Path
    from .modules.state import get_connection, update_music_dir_paths
    config_path = CONFIG_PATH
    if not config_path.exists():
        click.echo("No config file found.")
        return
    # Get old dir before changing
    old_config = Config.load()
    old_dir = str(old_config.general.music_dir)
    lines = config_path.read_text().splitlines(keepends=True)
    new_lines = []
    found = False
    for line in lines:
        if line.strip().startswith("music_dir"):
            new_lines.append(f\'music_dir = "{path}"\\n\')
            found = True
        else:
            new_lines.append(line)
    if not found:
        click.echo("Could not find music_dir in config.")
        return
    config_path.write_text("".join(new_lines))
    new_path = Path(path).expanduser()
    new_path.mkdir(parents=True, exist_ok=True)
    # Update DB paths
    conn = get_connection()
    updated = update_music_dir_paths(conn, old_dir, str(new_path))
    click.echo(f"Download directory set to: {path}")
    if updated:
        click.echo(f"Updated {updated} file path(s) in download history.")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("CLI set-dir updated")
else:
    print("ERROR: could not find set-dir command")
    exit(1)
PYEOF

# 3. Update TUI action_set_directory to also update DB paths
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''    def action_set_directory(self) -> None:
        def handle_result(new_path) -> None:
            if not new_path:
                return
            from ..modules.config import CONFIG_PATH
            from pathlib import Path
            config_path = CONFIG_PATH
            content = config_path.read_text() if config_path.exists() else ""
            lines = content.splitlines(keepends=True)
            new_lines = []
            for line in lines:
                if line.strip().startswith("music_dir"):
                    new_lines.append(f\'music_dir = "{new_path}"\\n\')
                else:
                    new_lines.append(line)
            config_path.write_text("".join(new_lines))
            self.config = Config.load()
            Path(new_path).expanduser().mkdir(parents=True, exist_ok=True)
            self._set_status(f"Download directory set to: {new_path}")
        self.push_screen(SetDirectoryScreen(), handle_result)'''

new = '''    def action_set_directory(self) -> None:
        def handle_result(new_path) -> None:
            if not new_path:
                return
            from ..modules.config import CONFIG_PATH
            from ..modules.state import update_music_dir_paths
            from pathlib import Path
            config_path = CONFIG_PATH
            old_dir = str(self.config.general.music_dir)
            content = config_path.read_text() if config_path.exists() else ""
            lines = content.splitlines(keepends=True)
            new_lines = []
            for line in lines:
                if line.strip().startswith("music_dir"):
                    new_lines.append(f\'music_dir = "{new_path}"\\n\')
                else:
                    new_lines.append(line)
            config_path.write_text("".join(new_lines))
            expanded = str(Path(new_path).expanduser())
            Path(expanded).mkdir(parents=True, exist_ok=True)
            conn = get_connection()
            updated = update_music_dir_paths(conn, old_dir, expanded)
            self.config = Config.load()
            msg = f"Download directory set to: {new_path}"
            if updated:
                msg += f" ({updated} path(s) updated)"
            self._set_status(msg)
        self.push_screen(SetDirectoryScreen(), handle_result)'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("TUI action_set_directory updated")
else:
    print("ERROR: could not find action_set_directory")
    exit(1)
PYEOF

echo "Fix 27 applied successfully"
