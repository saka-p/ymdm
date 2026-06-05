# ymdm — YouTube Music Download Manager

> ⚠️ **Beta** — ymdm is functional but still in early development. Expect rough edges.

ymdm is an easy way to download your favorite music from YouTube and YouTube Music so you can listen to it locally. Whether you want to own your music offline or keep a local copy of your YouTube Music library in sync, ymdm handles it automatically.

## Features

- Download playlists and albums from YouTube Music
- Keep your local library in sync with your YouTube Music playlists
- Works with private playlists via browser cookie auth
- Everything runs locally — no accounts, no cloud, no tracking
- Three interfaces: CLI, TUI, and a GTK4 desktop app

## Requirements

- Linux
- Python 3.10+
- ffmpeg

## Install

Run the installer — it will ask which version you want and handle everything:

```bash
curl -fsSL https://raw.githubusercontent.com/saka-p/ymdm/main/install.sh | bash
```

Or install manually:

```bash
pip install "ymdm[full]"      # CLI + TUI + GTK
pip install "ymdm[tui]"       # CLI + TUI
pip install "ymdm[desktop]"   # CLI + GTK
pip install ymdm               # CLI only
```

## CLI Usage

All commands below are for the terminal. For a visual interface, run `ymdm tui` or launch the desktop app with `ymdm-gtk`.

```bash
ymdm add "My Playlist" "https://music.youtube.com/playlist?list=..."
ymdm sync                  # sync all playlists
ymdm sync "My Playlist"    # sync one playlist
ymdm list                  # list configured playlists
ymdm remove "My Playlist"  # remove a playlist
ymdm tui                   # launch TUI
ymdm-gtk                   # launch desktop app
```

## Private Playlists

ymdm supports private YouTube Music playlists using cookie-based authentication. It reads cookies directly from your browser — no passwords are stored or sent anywhere.

To set it up:

```bash
ymdm auth setup
```

You'll be asked to select your browser. ymdm will use its cookies to authenticate with YouTube on your behalf. You can check the status or remove auth at any time:

```bash
ymdm auth status
ymdm auth remove
```

> **Note:** Cookie-based auth may trigger a Google security alert on your account. Your account is not at risk, but you may receive a notification.

## License

MIT
