#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

OS="$(uname -s)"

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# First, install the required packages
echo "Installing packages with Nix:"
export NIX_CONFIG="experimental-features = nix-command flakes"
nix profile remove dotfiles && nix profile install .#default

# This stow comes before the others to ensure global ignore list is respected before other stow commands
echo "Applying configs with GNU Stow:"
stow -t ~ stow
stow -t ~ common

if [ "$OS" = "Darwin" ]; then
    stow -t ~ darwin
fi

# Run install scripts for GUI applications
echo "Running install scripts:"
for script in "$PROJECT_DIR"/install/*.sh; do
    [ -x "$script" ] && bash "$script"
done

# Load dconf (Linux/GNOME only)
if [ "$OS" = "Linux" ]; then
    echo "Loading dconf:"
    if ! dconf load / <dconf.ini 2>/dev/null; then
        echo "Warning: dconf load failed (likely running on a server). Skipping."
    fi
fi
