# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a stow-based dotfiles repository using GNU Stow for symlink management and Nix Home Manager for package management. The setup is designed to be portable across machines.

## Key Commands

### Initial Setup / Full Sync
```bash
./sync.sh
```
This runs the complete setup process:
1. Nix Home Manager (installs packages)
2. GNU Stow (creates symlinks)
3. dconf (loads GNOME settings)

### Stow Operations
```bash
# Apply stow package (creates symlinks to home directory)
stow common

# Remove stow package symlinks
stow -D common

# Re-stow (useful after adding new files)
stow -R common
```

### Nix/Home Manager
```bash
# Rebuild home manager configuration
home-manager switch --flake .

# Update flake inputs
nix flake update
```

## Repository Structure

```
dotfiles/
├── common/           # Main stow package - portable configs
│   ├── .config/      # XDG config files (fish, starship, atuin, etc.)
│   ├── .local/bin/   # User binaries (tracked with Git LFS)
│   └── .local/share/applications/  # Desktop entries
├── stow/             # Stow global ignore rules
├── flake.nix         # Nix flakes configuration
├── home.nix          # Home Manager package definitions
├── dconf.ini         # GNOME desktop settings
└── sync.sh           # Setup/installation script
```

## Architecture

- **`common/`**: The main stow package containing all portable configuration files. Files here are symlinked to `~` maintaining their directory structure.
- **`stow/.stow-global-ignore`**: Applied first via `stow stow` to set up ignore patterns before symlinking common.
- **`home.nix`**: Defines packages installed via Nix Home Manager including development tools, terminal emulators, and fonts.
- **`flake.nix`**: Nix flakes entry point with NixGL support for GPU applications and Catppuccin theming.

## Conventions

- **Git LFS**: Binary files in `.local/bin/` are tracked with Git LFS (see `.gitattributes`)
- **Catppuccin Macchiato**: Consistent dark theme used across starship, fish, and other tools
- **Fish shell**: Default shell with vi-mode keybindings (`jk` for escape)
- **Branches**: `main` is default, `stow` is current working branch, `nvim` contains Neovim configs
