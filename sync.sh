#!/usr/bin/env bash
set -e

# Goto the directory this executable is located in
PROJECT_DIR=$(dirname "$(realpath "$0")")
cd "$PROJECT_DIR"

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# Detect OS
OS="$(uname)"

# Install packages with Homebrew
echo "Installing packages with Homebrew..."
brew bundle --file=Brewfile.common
if [[ "$OS" == "Darwin" ]]; then
    brew bundle --file=Brewfile.macos
else
    brew bundle --file=Brewfile.linux
fi

# This stow comes before the others to ensure global ignore list is respected before other stow commands
echo "Applying configs with GNU Stow..."
stow -t ~ stow
stow -t ~ common
if [[ "$OS" == "Darwin" ]]; then
    stow -t ~ macos
else
    stow -t ~ linux
fi

# Load dconf (Linux with GNOME only)
if [[ "$OS" != "Darwin" ]]; then
    echo "Loading dconf..."
    if ! dconf load / <dconf.ini 2>/dev/null; then
        echo "Warning: dconf load failed (likely running on a server). Skipping."
    fi
fi
