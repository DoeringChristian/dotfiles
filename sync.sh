#!/usr/bin/env bash
set -e

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# First, use homemanager to install the required commands
export NIX_CONFIG="experimental-features = nix-command flakes"
nix run home-manager/master -- switch --impure --flake .#doeringc

# This stow comes before the others to ensure global ignore list is respected before other stow commands
stow -t ~ stow
stow -t ~ common
