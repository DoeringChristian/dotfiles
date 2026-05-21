# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a stow-based dotfiles repository using GNU Stow for symlink management and Nix (via flake.nix) for package management. The setup is cross-platform (Linux & macOS).

## Key Commands

### Initial Setup (new machine)
```bash
./setup.sh
```
Installs Nix (if missing), runs sync to install packages, then decrypts age key for secrets management and sets up passage.

### Full Sync
```bash
./sync.sh
```
This runs the complete setup process:
1. Nix (installs packages from flake.nix)
2. GNU Stow (creates symlinks — `common` on all platforms, `darwin` additionally on macOS)
3. dconf (loads GNOME settings, Linux only)

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
├── common/           # Main stow package - portable configs (both platforms)
│   ├── .config/      # XDG config files (fish, starship, atuin, kitty, zellij, etc.)
│   ├── .local/bin/   # User binaries (tracked with Git LFS)
│   └── .local/share/applications/  # Desktop entries
├── darwin/           # macOS-specific stow package (overrides/additions)
│   └── .config/      # macOS-specific config files
├── stow/             # Stow global ignore rules (.stow-global-ignore)
├── setup/            # Encrypted secrets (age-key.age)
├── flake.nix         # Nix flakes configuration (platform-aware)
├── dconf.ini         # GNOME desktop settings (Linux only)
├── sync.sh           # Sync packages, symlinks, and dconf
├── setup.sh          # First-time setup (installs Nix, syncs, decrypts age key)
└── update.sh         # Update flake inputs and sync
```

## Architecture

- **`common/`**: The main stow package containing all portable configuration files. Files here are symlinked to `~` maintaining their directory structure. Used on both Linux and macOS.
- **`darwin/`**: macOS-specific stow package. Stowed in addition to `common/` on macOS only. Place macOS-specific config overrides here.
- **`stow/.stow-global-ignore`**: Applied first via `stow stow` to set up ignore patterns before symlinking common.
- **`flake.nix`**: Nix flakes entry point. Uses `eachDefaultSystem` for cross-platform support. On Linux, includes NixGL overlay and wraps GPU apps (kitty, darktable, tev) with `nixGLIntel`. On macOS, `nixGLWrap` is a no-op pass-through. Linux-only packages (wl-clipboard, distrobox, nvtop, etc.) are conditionally included.
- **Secrets**: Uses age for encryption and passage for password management. The encrypted age key lives in `setup/age-key.age` and is decrypted to `~/.local/share/age/key.txt` by `setup.sh`. Note: `setup.sh` runs `sync.sh` first to ensure `age` is installed via Nix before attempting decryption.

## Conventions

- **Git LFS**: Binary files in `.local/bin/` are tracked with Git LFS (see `.gitattributes`)
- **Catppuccin Macchiato**: Consistent dark theme used across starship, fish, bat, btop, kitty, and eza
- **Fish shell**: Default shell with vi-mode keybindings (`jk` for escape, `l` accepts autosuggestions)
- **NixGL wrapping** (Linux only): GPU-accelerated apps (kitty, darktable, tev) use `nixGLIntel` wrapper for compatibility. To wrap a new GPU app, use `(nixGLWrap pkg)` in flake.nix. On macOS, `nixGLWrap` is identity — no wrapping needed.
- **Adding a new config**: Place files under `common/` mirroring their home directory path (e.g., `common/.config/foo/config` symlinks to `~/.config/foo/config`), then run `stow -t ~ -R common`. For macOS-specific configs, use `darwin/` instead.
- **Adding a new package**: Add it to the common `paths` list in `flake.nix` (or the linux-only conditional block), then run `nix profile remove dotfiles && nix profile install .#default`
