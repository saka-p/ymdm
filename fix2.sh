#!/usr/bin/env bash
set -e

python3 << 'PYEOF'
path = "ymdm/tui/app.py"
content = open(path).read()

# Fix 1: duplicate dialog-hint ID in DeletePlaylistScreen
old = '''    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label(f"Delete \'{self.playlist_name}\'", id="dialog-title")
            yield Label("What would you like to delete?", id="dialog-hint")
            yield ListView(id="delete-options")
            yield Label("Enter · confirm   Esc · cancel", id="dialog-hint")'''

new = '''    def compose(self) -> ComposeResult:
        with Vertical(id="add-dialog"):
            yield Label(f"Delete \'{self.playlist_name}\'", id="dialog-title")
            yield Label("What would you like to delete?", id="delete-question")
            yield ListView(id="delete-options")
            yield Label("Enter · confirm   Esc · cancel", id="delete-hint")'''

if old in content:
    content = content.replace(old, new)
    print("Fixed duplicate ID")
else:
    print("ERROR: could not find duplicate ID to fix")
    exit(1)

# Fix 2: Replace YmdmCommands with a nested auth provider
old_commands = '''class YmdmCommands(Provider):
    """Custom command palette entries for ymdm."""

    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            ("Auth Setup — configure private playlist access", app.action_auth_setup),
            ("Auth Remove — disable authentication", app.action_auth_remove),
            ("Auth Status — show current auth configuration", app.action_auth_status),
        ]
        matcher = self.matcher(query)
        for label, action in commands:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=label)'''

new_commands = '''class YmdmCommands(Provider):
    """Custom command palette entries for ymdm."""

    async def search(self, query: str) -> Hits:
        app = self.app
        commands = [
            (
                "Authentication",
                "Private playlist manager",
                app.action_auth_setup,
            ),
            (
                "Authentication > Setup",
                "Configure browser cookie auth for private playlists",
                app.action_auth_setup,
            ),
            (
                "Authentication > Status",
                "Show current auth configuration",
                app.action_auth_status,
            ),
            (
                "Authentication > Remove",
                "Disable authentication",
                app.action_auth_remove,
            ),
        ]
        matcher = self.matcher(query)
        for label, help_text, action in commands:
            score = matcher.match(label)
            if score > 0:
                yield Hit(score, matcher.highlight(label), action, help=help_text)'''

if old_commands in content:
    content = content.replace(old_commands, new_commands)
    print("Fixed command palette")
else:
    print("ERROR: could not find YmdmCommands to fix")
    exit(1)

open(path, "w").write(content)
print("All fixes applied")
PYEOF

echo "Fix 2 applied successfully"
