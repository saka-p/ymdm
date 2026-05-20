#!/usr/bin/env bash
set -e

# Add dev_mode to config
python3 << 'PYEOF'
path = "ymdm/modules/config.py"
content = open(path).read()

old = '''@dataclass
class AuthConfig:
    enabled: bool = False
    browser: str | None = None'''

new = '''@dataclass
class AuthConfig:
    enabled: bool = False
    browser: str | None = None


@dataclass
class DevConfig:
    enabled: bool = False  # When True, disables ignoreerrors so full tracebacks show'''

if old in content:
    content = content.replace(old, new)
    print("DevConfig added")
else:
    print("ERROR: could not find AuthConfig")
    exit(1)

old_class = '''@dataclass
class Config:
    general: GeneralConfig = field(default_factory=GeneralConfig)
    metadata: MetadataConfig = field(default_factory=MetadataConfig)
    auth: AuthConfig = field(default_factory=AuthConfig)
    playlists: list[PlaylistEntry] = field(default_factory=list)'''

new_class = '''@dataclass
class Config:
    general: GeneralConfig = field(default_factory=GeneralConfig)
    metadata: MetadataConfig = field(default_factory=MetadataConfig)
    auth: AuthConfig = field(default_factory=AuthConfig)
    dev: DevConfig = field(default_factory=DevConfig)
    playlists: list[PlaylistEntry] = field(default_factory=list)'''

if old_class in content:
    content = content.replace(old_class, new_class)
    print("Config class updated")
else:
    print("ERROR: could not find Config class")
    exit(1)

old_load = '''        if a := raw.get("auth"):
            cfg.auth.enabled = a.get("enabled", False)
            cfg.auth.browser = a.get("browser", None)'''

new_load = '''        if a := raw.get("auth"):
            cfg.auth.enabled = a.get("enabled", False)
            cfg.auth.browser = a.get("browser", None)
        if d := raw.get("dev"):
            cfg.dev.enabled = d.get("enabled", False)'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("Config load updated")
else:
    print("ERROR: could not find auth load block")
    exit(1)

open(path, "w").write(content)
print("config.py patched")
PYEOF

# Update downloader to respect dev mode
python3 << 'PYEOF'
path = "ymdm/modules/downloader.py"
content = open(path).read()

old = '        "ignoreerrors": True,'
new = '        "ignoreerrors": not config.dev.enabled,'

if old in content:
    content = content.replace(old, new)
    open(path, "w").write(content)
    print("downloader.py patched")
else:
    print("ERROR: could not find ignoreerrors")
    exit(1)
PYEOF

# Add dev mode toggle to TUI command palette
python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old = '''class DevMenuScreen(ModalScreen):''' if 'class DevMenuScreen' in content else None

old_auth_options = '''    OPTIONS = [
        ("Setup", "Configure browser cookie auth for private playlists"),
        ("Status", "Show current auth configuration"),
        ("Remove", "Disable authentication"),
    ]'''

# Add DevMenuScreen after AuthMenuScreen
old_insert = '''class YmdmCommands(Provider):'''

new_dev_screen = '''class DevMenuScreen(ModalScreen):
    """Developer mode toggle modal."""

    BINDINGS = [("escape", "dismiss", "Cancel")]

    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label("Developer Mode", id="dialog-title")
            yield Label("Disables error skipping so full tracebacks show in terminal.", id="delete-question")
            yield ListView(id="dev-options")
            yield Label("Enter · select   Esc · cancel", id="delete-hint")

    def on_mount(self) -> None:
        from ..modules.config import Config
        config = Config.load()
        status = "ON" if config.dev.enabled else "OFF"
        lv = self.query_one("#dev-options", ListView)
        lv.append(ListItem(Label(f"Toggle developer mode (currently {status})")))
        lv.append(ListItem(Label("View errors.log")))
        lv.focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        idx = self.query_one("#dev-options", ListView).index
        self.dismiss(idx)


'''

if 'class DevMenuScreen' not in content:
    content = content.replace(old_insert, new_dev_screen + old_insert)
    print("DevMenuScreen added")
else:
    print("DevMenuScreen already exists")

# Add dev option to YmdmCommands discover
old_discover = '''    async def discover(self) -> Hits:
        yield Hit(
            1.0,
            "Authentication",
            self.app.action_open_auth_menu,
            help="Manage private playlist auth — setup, status, remove",
        )'''

new_discover = '''    async def discover(self) -> Hits:
        yield Hit(
            1.0,
            "Authentication",
            self.app.action_open_auth_menu,
            help="Manage private playlist auth — setup, status, remove",
        )
        yield Hit(
            0.9,
            "Developer Mode",
            self.app.action_open_dev_menu,
            help="Toggle error skipping for debugging",
        )'''

if old_discover in content:
    content = content.replace(old_discover, new_discover)
    print("discover updated")
else:
    print("ERROR: could not find discover")
    exit(1)

# Add dev option to search
old_search = '''    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
        ]'''

new_search = '''    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
            ("Developer Mode", "Toggle error skipping for debugging", app.action_open_dev_menu),
        ]'''

if old_search in content:
    content = content.replace(old_search, new_search)
    print("search updated")
else:
    print("ERROR: could not find search")
    exit(1)

# Add action_open_dev_menu before action_sync_all
old_action = '''    @work(thread=True)
    def _do_sync_all(self) -> None:'''

new_action = '''    def action_open_dev_menu(self) -> None:
        def handle_result(choice) -> None:
            if choice is None:
                return
            from ..modules.config import Config, CONFIG_PATH
            import subprocess
            if choice == 0:
                # Toggle dev mode
                config_path = CONFIG_PATH
                content = config_path.read_text() if config_path.exists() else ""
                cfg = Config.load()
                new_state = not cfg.dev.enabled
                # Remove existing dev block
                lines = content.splitlines(keepends=True)
                new_lines = []
                skip = False
                for line in lines:
                    if line.strip() == "[dev]":
                        skip = True
                        continue
                    if skip and line.strip().startswith("[") and line.strip() != "[dev]":
                        skip = False
                    if not skip:
                        new_lines.append(line)
                new_content = "".join(new_lines).rstrip()
                new_content += f"\n\n[dev]\nenabled = {'true' if new_state else 'false'}\n"
                config_path.write_text(new_content)
                self.config = Config.load()
                state_str = "ON" if new_state else "OFF"
                self._set_status(f"Developer mode {state_str}. {'Full tracebacks will show on next sync.' if new_state else 'Errors will be skipped silently.'}")
            elif choice == 1:
                import os
                from ..modules.downloader import ERROR_LOG
                if ERROR_LOG.exists():
                    os.system(f"xdg-open {ERROR_LOG} &")
                else:
                    self._set_status("No errors.log found yet.")
        self.push_screen(DevMenuScreen(), handle_result)

    @work(thread=True)
    def _do_sync_all(self) -> None:'''

if old_action in content:
    content = content.replace(old_action, new_action)
    print("action_open_dev_menu added")
else:
    print("ERROR: could not find _do_sync_all")
    exit(1)

open(path, "w").write(content)
print("tui/app.py patched")
PYEOF

echo "Fix 9 applied successfully"
