#!/usr/bin/env bash
set -e

# Goto the directory this executable is located in
PROJECT_DIR=$(dirname "$(realpath $0)")
cd $PROJECT_DIR

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# First, use homemanager to install the required commands
echo "Installing packages with Nix:"
export NIX_CONFIG="experimental-features = nix-command flakes"
nix profile install .

# This stow comes before the others to ensure global ignore list is respected before other stow commands
echo "Applying configs with GNU Stow:"
stow -t ~ stow
stow -t ~ common

# Load dconf
echo "Loading dconf:"
dconf load / <dconf.ini
