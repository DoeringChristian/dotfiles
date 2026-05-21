# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a stow-based dotfiles repository using GNU Stow for symlink management and Homebrew for package management. The setup is designed to be portable across Linux and macOS machines.

## Key Commands

### Initial Setup (new machine)
```bash
./setup.sh
```
Installs Homebrew (if needed), syncs packages and configs, then decrypts age key for secrets management and sets up passage.

### Full Sync
```bash
./sync.sh
```
This runs the complete setup process:
1. Homebrew (installs packages from Brewfiles)
2. GNU Stow (creates symlinks — common + OS-specific)
3. dconf (loads GNOME settings, Linux only)

### Update All
```bash
./update.sh
```
Runs `brew update && brew upgrade` then syncs.

### Stow Operations
```bash
# Apply stow package (creates symlinks to home directory)
stow -t ~ common

# Remove stow package symlinks
stow -t ~ -D common

# Re-stow (useful after adding new files)
stow -t ~ -R common
```
**Ordering matters**: `stow -t ~ stow` must run before `stow -t ~ common` so the global ignore rules are in place. `sync.sh` handles this automatically.

### Homebrew
```bash
# Install packages from Brewfiles
brew bundle --file=Brewfile.common
brew bundle --file=Brewfile.linux   # or Brewfile.macos

# Add a new package: add it to the appropriate Brewfile, then run sync.sh
```

## Repository Structure

```
dotfiles/
├── common/           # Main stow package - portable configs (shared across Linux & macOS)
│   ├── .config/      # XDG config files (fish, starship, atuin, kitty, zellij, etc.)
│   └── .local/bin/   # User binaries (tracked with Git LFS)
├── linux/            # Linux-specific stow package
│   ├── .local/bin/   # Linux-only scripts (claudebox, vpn, etc.)
│   └── .local/share/applications/  # Desktop entries
├── macos/            # macOS-specific stow package
├── stow/             # Stow global ignore rules (.stow-global-ignore)
├── setup/            # Encrypted secrets (age-key.age)
├── Brewfile.common   # Shared Homebrew packages
├── Brewfile.linux    # Linux-specific Homebrew packages
├── Brewfile.macos    # macOS-specific Homebrew packages
├── dconf.ini         # GNOME desktop settings (Linux only)
├── sync.sh           # Sync packages, symlinks, and dconf
├── setup.sh          # First-time setup (installs brew, syncs, decrypts age key)
└── update.sh         # Update brew packages and sync
```

## Architecture

- **`common/`**: The main stow package containing all portable configuration files. Files here are symlinked to `~` maintaining their directory structure.
- **`linux/`**: Linux-specific stow package (desktop entries, VPN scripts, claudebox sandbox wrapper).
- **`macos/`**: macOS-specific stow package.
- **`stow/.stow-global-ignore`**: Applied first via `stow stow` to set up ignore patterns before symlinking common.
- **Brewfiles**: `Brewfile.common` for cross-platform packages, `Brewfile.linux` and `Brewfile.macos` for OS-specific packages. Installed via `brew bundle`.
- **Secrets**: Uses age for encryption and passage for password management. The encrypted age key lives in `setup/age-key.age` and is decrypted to `~/.local/share/age/key.txt` by `setup.sh`.

## Conventions

- **Git LFS**: Binary files in `.local/bin/` are tracked with Git LFS (see `.gitattributes`)
- **Catppuccin Macchiato**: Consistent dark theme used across starship, fish, bat, btop, kitty, and eza
- **Fish shell**: Default shell with vi-mode keybindings (`jk` for escape, `l` accepts autosuggestions)
- **Adding a new config**: Place files under `common/` (or `linux/`/`macos/` for OS-specific) mirroring their home directory path (e.g., `common/.config/foo/config` symlinks to `~/.config/foo/config`), then run `stow -t ~ -R common`
- **Adding a new package**: Add it to the appropriate Brewfile (`Brewfile.common`, `Brewfile.linux`, or `Brewfile.macos`), then run `./sync.sh`
