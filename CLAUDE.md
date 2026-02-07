# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a stow-based dotfiles repository using GNU Stow for symlink management and Nix (via flake.nix) for package management. The setup is designed to be portable across machines.

## Key Commands

### Initial Setup (new machine)
```bash
./setup.sh
```
Decrypts age key for secrets management, sets up passage, then runs sync.

### Full Sync
```bash
./sync.sh
```
This runs the complete setup process:
1. Nix (installs packages from flake.nix)
2. GNU Stow (creates symlinks)
3. dconf (loads GNOME settings)

### Update All
```bash
./update.sh
```
Updates flake inputs (`nix flake update`) then runs sync.

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

### Nix/Flake
```bash
# Rebuild/reinstall packages
nix profile remove dotfiles && nix profile install .#default

# Update flake inputs
nix flake update
```

## Repository Structure

```
dotfiles/
├── common/           # Main stow package - portable configs
│   ├── .config/      # XDG config files (fish, starship, atuin, kitty, zellij, etc.)
│   ├── .local/bin/   # User binaries (tracked with Git LFS)
│   └── .local/share/applications/  # Desktop entries
├── stow/             # Stow global ignore rules (.stow-global-ignore)
├── setup/            # Encrypted secrets (age-key.age)
├── flake.nix         # Nix flakes configuration
├── dconf.ini         # GNOME desktop settings
├── sync.sh           # Sync packages, symlinks, and dconf
├── setup.sh          # First-time setup (decrypts age key, then syncs)
└── update.sh         # Update flake inputs and sync
```

## Architecture

- **`common/`**: The main stow package containing all portable configuration files. Files here are symlinked to `~` maintaining their directory structure.
- **`stow/.stow-global-ignore`**: Applied first via `stow stow` to set up ignore patterns before symlinking common.
- **`flake.nix`**: Nix flakes entry point with NixGL support for GPU applications (kitty, darktable, tev). Packages are installed via `nix profile install`. Uses a `nixGLWrap` helper that wraps binaries with `nixGLIntel` for GPU compatibility on non-NixOS systems.
- **Secrets**: Uses age for encryption and passage for password management. The encrypted age key lives in `setup/age-key.age` and is decrypted to `~/.local/share/age/key.txt` by `setup.sh`.

## Conventions

- **Git LFS**: Binary files in `.local/bin/` are tracked with Git LFS (see `.gitattributes`)
- **Catppuccin Macchiato**: Consistent dark theme used across starship, fish, bat, btop, kitty, and eza
- **Fish shell**: Default shell with vi-mode keybindings (`jk` for escape, `l` accepts autosuggestions)
- **NixGL wrapping**: GPU-accelerated apps (kitty, darktable, tev) use `nixGLIntel` wrapper for compatibility. To wrap a new GPU app, use `(nixGLWrap pkg)` in flake.nix
- **Adding a new config**: Place files under `common/` mirroring their home directory path (e.g., `common/.config/foo/config` symlinks to `~/.config/foo/config`), then run `stow -t ~ -R common`
- **Adding a new package**: Add it to the `paths` list in `flake.nix`, then run `nix profile remove dotfiles && nix profile install .#default`
