# ymdm — YouTube Music Download Manager

A lightweight, config-driven YouTube Music playlist syncer for Linux.

## Install

```bash
pip install -e .
```

## Setup

```bash
mkdir -p ~/.config/ymdm
cp config.toml ~/.config/ymdm/config.toml
nvim ~/.config/ymdm/config.toml
```

## Usage

```bash
ymdm list
ymdm sync
ymdm add "My Playlist" "https://music.youtube.com/playlist?list=..."
```
