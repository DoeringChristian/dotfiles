#!/usr/bin/env bash
# install.sh — bring this machine up to the full toolset, ROOTLESS, on any OS.
#
#   macOS       -> Homebrew            (pkg/Brewfile)
#   Linux/other -> conda-forge via pixi global (pkg/pixi-global.toml)  [no root]
#   both        -> pkg/extras.sh (tools neither packages) + GNU Stow (configs)
#
# Safe to run ALONGSIDE an existing mise setup: it installs into the brew / pixi
# prefixes and ~/.local, and never touches ~/.local/share/mise or your PATH files.
# Verify everything works, THEN retire mise if you want (see README).
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
OS="$(uname -s)"

# ---------------------------------------------------------------- package layer
if [ "$OS" = Darwin ]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "==> installing Homebrew"
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$p" ] && eval "$("$p" shellenv)"
    done
    echo "==> brew bundle (pkg/Brewfile)"
    brew bundle --file "$DIR/Brewfile"
else
    # Rootless conda-forge via pixi global. pixi self-installs to ~/.pixi (no root).
    if ! command -v pixi >/dev/null 2>&1 && [ ! -x "$HOME/.pixi/bin/pixi" ]; then
        echo "==> installing pixi (rootless)"
        curl -fsSL https://pixi.sh/install.sh | bash
    fi
    export PATH="$HOME/.pixi/bin:$PATH"
    # Point pixi global at our manifest (same trick the old pixi setup used).
    mkdir -p "$HOME/.pixi/manifests"
    ln -sfn "$DIR/pixi-global.toml" "$HOME/.pixi/manifests/pixi-global.toml"
    echo "==> pixi global sync (pkg/pixi-global.toml)"
    pixi global sync
fi

# ---------------------------------------------------------------- extras
# kitty/tev on Linux, sshr, passage, and per-OS AI CLIs — see the script.
echo "==> extras (tools the package manager doesn't carry)"
OS="$OS" REPO="$REPO" bash "$DIR/extras.sh"

# ---------------------------------------------------------------- configs (stow)
# stow itself came from brew/pixi above. Reuse the repo's stow packages.
if command -v stow >/dev/null 2>&1; then
    echo "==> stow configs"
    cd "$REPO"
    [ -d stow ] && stow -t ~ stow            # global ignore rules first
    [ -d common ] && stow -t ~ common
    if [ "$OS" = Darwin ] && [ -d darwin ]; then
        stow -t ~ darwin
        mkdir -p ~/Library/Fonts
        cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    fi
fi

echo
echo "==> done."
echo "   Make sure your shell PATH includes:"
if [ "$OS" = Darwin ]; then
    echo "     \$(brew --prefix)/bin   and   \$HOME/.local/bin"
else
    echo "     \$HOME/.pixi/bin   and   \$HOME/.local/bin"
fi
echo "   (mise was NOT touched — it's still your live setup until you remove it.)"
