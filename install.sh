#!/usr/bin/env bash
set -euo pipefail

REPO_URL="git@github.com:saka-p/ymdm.git"
INSTALL_DIR="$HOME/.local/share/ymdm"
DESKTOP_DIR="$HOME/.local/share/applications"

echo "╔══════════════════════════════════════╗"
echo "║      ymdm — installer                ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Version selector ──────────────────────────────────────────────────────────
echo "Which version would you like to install?"
echo ""
echo "  1. CLI only        — terminal commands only"
echo "  2. CLI + TUI       — terminal + text interface"
echo "  3. CLI + GTK       — terminal + desktop app"
echo "  4. CLI + TUI + GTK — everything"
echo ""
read -rp "Enter a number [1-4]: " choice

case "$choice" in
    1) EXTRA=""          ; LABEL="CLI only" ;;
    2) EXTRA="[tui]"     ; LABEL="CLI + TUI" ;;
    3) EXTRA="[desktop]" ; LABEL="CLI + GTK" ;;
    4) EXTRA="[full]"    ; LABEL="CLI + TUI + GTK" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

echo ""
echo "Installing: $LABEL"
echo ""

# ── Detect package manager ────────────────────────────────────────────────────
if command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
else
    echo "✗ No supported package manager found (dnf/apt/pacman)."
    echo "  Please install dependencies manually and re-run."
    exit 1
fi

_install_pkg() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        dnf)    sudo dnf install -y "$pkg" ;;
        apt)    sudo apt install -y "$pkg" ;;
        pacman) sudo pacman -S --needed --noconfirm "$pkg" ;;
    esac
}

# ── Check / install dependencies ──────────────────────────────────────────────
echo "► Checking dependencies..."

# Python
if command -v python3 &>/dev/null && python3 -c "import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)" 2>/dev/null; then
    echo "  ✓ Python $(python3 --version | cut -d' ' -f2)"
else
    echo "  Python 3.10+ not found."
    read -rp "  Install it now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        case "$PKG_MANAGER" in
            dnf)    _install_pkg python3 ;;
            apt)    _install_pkg python3 ;;
            pacman) _install_pkg python ;;
        esac
    else
        echo "  Python is required. Exiting."; exit 1
    fi
fi

# ffmpeg
if command -v ffmpeg &>/dev/null; then
    echo "  ✓ ffmpeg"
else
    echo "  ffmpeg not found."
    read -rp "  Install it now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        _install_pkg ffmpeg
    else
        echo "  ffmpeg is required. Exiting."; exit 1
    fi
fi

# pip — package name differs per distro
if command -v pip &>/dev/null || command -v pip3 &>/dev/null; then
    echo "  ✓ pip"
else
    echo "  pip not found."
    read -rp "  Install it now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        case "$PKG_MANAGER" in
            dnf)    _install_pkg python3-pip ;;
            apt)    _install_pkg python3-pip ;;
            pacman) _install_pkg python-pip ;;
        esac
    else
        echo "  pip is required. Exiting."; exit 1
    fi
fi

# git
if command -v git &>/dev/null; then
    echo "  ✓ git"
else
    echo "  git not found."
    read -rp "  Install it now? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        _install_pkg git
    else
        echo "  git is required. Exiting."; exit 1
    fi
fi

# GTK deps if needed
if [[ "$EXTRA" == "[desktop]" || "$EXTRA" == "[full]" ]]; then
    if python3 -c "import gi" 2>/dev/null; then
        echo "  ✓ pygobject"
    else
        echo "  pygobject (GTK bindings) not found."
        read -rp "  Install it now? [y/N] " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            case "$PKG_MANAGER" in
                dnf)    sudo dnf install -y python3-gobject python3-gobject-devel libadwaita gtk4 ;;
                apt)    sudo apt install -y python3-gi python3-gi-cairo gir1.2-gtk-4.0 gir1.2-adw-1 ;;
                pacman) sudo pacman -S --needed --noconfirm python-gobject libadwaita gtk4 ;;
            esac
        else
            echo "  pygobject is required for the GTK app. Exiting."; exit 1
        fi
    fi
fi

echo ""

# ── Clone or update repo ──────────────────────────────────────────────────────
echo "► Getting ymdm source..."

if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  Existing install found — updating..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    git clone "$REPO_URL" "$INSTALL_DIR"
fi
echo "  ✓ Source ready at $INSTALL_DIR"
echo ""

# ── Install ymdm ──────────────────────────────────────────────────────────────
echo "► Installing ymdm$EXTRA..."
pip install --break-system-packages -e "$INSTALL_DIR$EXTRA"
echo "  ✓ ymdm installed"
echo ""

# ── Install .desktop file if GTK ─────────────────────────────────────────────
if [[ "$EXTRA" == "[desktop]" || "$EXTRA" == "[full]" ]]; then
    echo "► Installing app launcher entry..."
    mkdir -p "$DESKTOP_DIR"
    YMDM_GTK_BIN="$(command -v ymdm-gtk 2>/dev/null || echo "$HOME/.local/bin/ymdm-gtk")"
    sed "s|Exec=ymdm-gtk|Exec=$YMDM_GTK_BIN|" \
        "$INSTALL_DIR/ymdm.desktop" > "$DESKTOP_DIR/ymdm.desktop"
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$DESKTOP_DIR"
    fi
    echo "  ✓ App launcher entry installed"
    echo ""
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo "╔══════════════════════════════════════╗"
echo "║        Installation complete!        ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Get started:"
echo "    ymdm add \"My Playlist\" \"https://music.youtube.com/playlist?list=...\""
echo "    ymdm sync"
if [[ "$EXTRA" == "[tui]" || "$EXTRA" == "[full]" ]]; then
echo "    ymdm tui"
fi
if [[ "$EXTRA" == "[desktop]" || "$EXTRA" == "[full]" ]]; then
echo "    ymdm-gtk"
fi
echo ""
echo "  Docs: https://github.com/saka-p/ymdm"
echo ""
