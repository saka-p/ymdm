#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

old_commands = '''class AuthMenuCommands(Provider):
    """Nested auth sub-menu shown after selecting Authentication."""

    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("← Back", "Go back to main commands", app.action_command_palette),
            ("Setup", "Configure browser cookie auth for private playlists", app.action_auth_setup),
            ("Status", "Show current auth configuration", app.action_auth_status),
            ("Remove", "Disable authentication", app.action_auth_remove),
        ]
        matcher = self.matcher(query)
        for label, help_text, action in commands:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=help_text)

    async def discover(self) -> Hits:
        app = self.app
        entries = [
            ("← Back", "Go back to main commands", app.action_command_palette),
            ("Setup", "Configure browser cookie auth for private playlists", app.action_auth_setup),
            ("Status", "Show current auth configuration", app.action_auth_status),
            ("Remove", "Disable authentication", app.action_auth_remove),
        ]
        for label, help_text, action in entries:
            yield Hit(1.0, label, action, help=help_text)


class YmdmCommands(Provider):
    """Main command palette entries."""

    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
        ]
        matcher = self.matcher(query)
        for label, help_text, action in commands:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=help_text)

    async def discover(self) -> Hits:
        app = self.app
        yield Hit(
            1.0,
            "Authentication",
            app.action_open_auth_menu,
            help="Manage private playlist auth — setup, status, remove",
        )'''

new_commands = '''class YmdmCommands(Provider):
    """Command palette — root or auth submenu depending on app state."""

    async def search(self, query: str) -> Hits:
        app = self.app
        entries = self._auth_entries(app) if getattr(app, "_auth_menu_open", False) else self._root_entries(app)
        matcher = self.matcher(query)
        for label, help_text, action in entries:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=help_text)

    async def discover(self) -> Hits:
        app = self.app
        entries = self._auth_entries(app) if getattr(app, "_auth_menu_open", False) else self._root_entries(app)
        for label, help_text, action in entries:
            yield Hit(1.0, label, action, help=help_text)

    def _root_entries(self, app):
        return [
            ("Authentication", "Manage private playlist auth — setup, status, remove", app.action_open_auth_menu),
        ]

    def _auth_entries(self, app):
        return [
            ("← Back", "Return to main menu", app.action_close_auth_menu),
            ("Setup", "Configure browser cookie auth for private playlists", app.action_auth_setup),
            ("Status", "Show current auth configuration", app.action_auth_status),
            ("Remove", "Disable authentication", app.action_auth_remove),
        ]'''

if old_commands in content:
    content = content.replace(old_commands, new_commands)
    print("Commands block replaced")
else:
    print("ERROR: could not find commands block")
    exit(1)

old_open = '''    def action_open_auth_menu(self) -> None:
        """Open the auth sub-menu in the command palette."""
        self.app.COMMANDS = App.COMMANDS | {AuthMenuCommands}
        self.action_command_palette()'''

new_open = '''    def action_open_auth_menu(self) -> None:
        """Switch command palette to auth submenu."""
        self._auth_menu_open = True
        self.action_command_palette()

    def action_close_auth_menu(self) -> None:
        """Return to root command palette."""
        self._auth_menu_open = False
        self.action_command_palette()'''

if old_open in content:
    content = content.replace(old_open, new_open)
    print("action_open_auth_menu fixed")
else:
    print("ERROR: could not find action_open_auth_menu")
    exit(1)

# Reset auth menu state in each auth action
for old_reset in [
    "        self.app.COMMANDS = App.COMMANDS | {YmdmCommands}\n        current = self.config.auth.browser",
    "        self.app.COMMANDS = App.COMMANDS | {YmdmCommands}\n        from ..modules.config import CONFIG_PATH\n        config_path = CONFIG_PATH\n        if not config_path.exists():\n            self._set_status(\"No config file found.\")\n            return",
    "        self.app.COMMANDS = App.COMMANDS | {YmdmCommands}\n        if self.config.auth.enabled",
]:
    content = content.replace("        self.app.COMMANDS = App.COMMANDS | {YmdmCommands}\n", "        self._auth_menu_open = False\n", 1)

old_init = '''        self._settings = load_tui_settings()
        self.register_theme(RETRO_THEME)
        self.register_theme(BREEZE_DARK_THEME)'''

new_init = '''        self._settings = load_tui_settings()
        self._auth_menu_open = False
        self.register_theme(RETRO_THEME)
        self.register_theme(BREEZE_DARK_THEME)'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("_auth_menu_open init added")
else:
    print("ERROR: could not find init block")
    exit(1)

open(path, "w").write(content)
print("All fixes applied successfully")
PYEOF

echo "Fix 4 applied successfully"
