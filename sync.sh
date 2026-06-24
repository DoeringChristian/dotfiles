#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

OS="$(uname -s)"

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# First, install the required packages (builds the pixi env at .pixi/envs/default,
# which the shell config puts on PATH).
echo "Installing packages with pixi:"
# npm tools (gemini-cli, claude-code) build via our local custom backend.
export PIXI_BUILD_BACKEND_OVERRIDE="pixi-build-npm=$PROJECT_DIR/ext/pixi-build-npm/pixi-build-npm"
pixi install

# This stow comes before the others to ensure global ignore list is respected before other stow commands
echo "Applying configs with GNU Stow:"
stow -t ~ stow
stow -t ~ common

if [ "$OS" = "Darwin" ]; then
    stow -t ~ darwin
fi

# Run install scripts for GUI applications (skip already-installed apps unless UPDATE=1)
echo "Running install scripts:"
for script in "$PROJECT_DIR"/install/*.sh; do
    [ -x "$script" ] || continue
    name="$(basename "$script" .sh)"
    installed=false
    if command -v "$name" >/dev/null 2>&1 \
        || [ -d "$HOME/Applications/$name.app" ] \
        || [ -d "/Applications/$name.app" ]; then
        installed=true
    fi
    if [ "${UPDATE:-0}" != "1" ] && [ "$installed" = true ]; then
        echo "Skipping $name (already installed)"
        continue
    fi
    bash "$script"
done

# Load dconf (Linux/GNOME only)
if [ "$OS" = "Linux" ]; then
    echo "Loading dconf:"
    if ! dconf load / <dconf.ini 2>/dev/null; then
        echo "Warning: dconf load failed (likely running on a server). Skipping."
    fi
fi
