#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''                if url not in content:
                    snippet = f\'\\n[[playlists.watched]]\\nname = "{name}"\\nurl  = "{url}"\\n\'
                    with open(config_path, "a") as f:
                        f.write(snippet)
                    self._set_status(f"Added \'{name}\'.")
                else:
                    self._set_status(f"\'{name}\' is already in your config.")'''

new = '''                if url in content:
                    self._set_status(f"'{name}' is already in your config.")
                elif any(pl.name == name for pl in self.config.playlists):
                    self._set_status(f"A playlist named '{name}' already exists. Choose a different name.")
                else:
                    snippet = f\'\\n[[playlists.watched]]\\nname = "{name}"\\nurl  = "{url}"\\n\'
                    with open(config_path, "a") as f:
                        f.write(snippet)
                    self._set_status(f"Added '{name}'.")'''

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("Fixed")
else:
    print("ERROR: no match")
    # Debug
    idx = content.find("if url not in content")
    print(repr(content[idx-20:idx+200]))
    exit(1)
PYEOF

# Also add e keybind and open location action
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

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

old_switch = '''    def action_switch_panel(self) -> None:'''

new_open = '''    def action_open_location(self) -> None:
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
    content = content.replace(old_switch, new_open)
    print("action_open_location added")
else:
    print("ERROR: could not find action_switch_panel")
    exit(1)

open(path, "w").write(content)
print("Done")
PYEOF

# Add playlist thumbnail fallback to downloader
python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old_helper = '''def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):'''

new_helper = '''def _find_playlist_thumbnail(output_dir: Path) -> Path | None:
    """Find a playlist-level thumbnail in the output directory."""
    for f in output_dir.iterdir():
        if f.suffix.lower() in (".jpg", ".jpeg", ".png", ".webp") and f.is_file():
            return f
    return None


def _handle_thumbnail(thumbnail_path: Path, keep_dir: Path | None):'''

if old_helper in content:
    content = content.replace(old_helper, new_helper)
    print("_find_playlist_thumbnail added")
else:
    print("ERROR: could not find _handle_thumbnail")
    exit(1)

old_thumb = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            if config.metadata.embed_thumbnail:'''

new_thumb = '''            thumbnail_path = _find_thumbnail(file_path.with_suffix(""))
            if thumbnail_path is None:
                thumbnail_path = _find_playlist_thumbnail(output_dir)
            if config.metadata.embed_thumbnail:'''

if old_thumb in content:
    content = content.replace(old_thumb, new_thumb)
    open(path, "w").write(content)
    print("thumbnail fallback added")
else:
    print("ERROR: could not find thumbnail block")
    exit(1)
PYEOF

# Add to .gitignore
grep -q "patch\*.sh" .gitignore 2>/dev/null || cat >> .gitignore << 'EOF'

# Dev scripts
patch*.sh
fix*.sh
update*.sh
revert*.sh
EOF

echo "Fix 15 applied successfully"
