# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a stow-based dotfiles repository using GNU Stow for symlink management and pixi (via `pixi.toml`) for package management. The setup is cross-platform (Linux & macOS). Tools that aren't on conda-forge (or need a newer/nightly version) are built from source as pixi packages under `ext/`.

## Key Commands

### Initial Setup (new machine)
```bash
./setup.sh
```
Installs pixi (if missing) and rattler-build, runs sync to build/install packages, then decrypts age key for secrets management and sets up passage.

### Full Sync
```bash
./sync.sh
```
This runs the complete setup process:
1. pixi (`pixi install` builds the env at `.pixi/envs/default`, which the shell config puts on PATH)
2. GNU Stow (creates symlinks — `common` on all platforms, `darwin` additionally on macOS)
3. dconf (loads GNOME settings, Linux only)

### Update All
```bash
./update.sh
```
Updates conda deps (`pixi update`) then runs sync. For source packages tracking a moving ref (neovim nightly, sshr `main`), force a fresh build with `pixi clean && ./sync.sh`.

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

### Pixi (global tools)
Tools are installed **globally** via `pixi global` into `~/.pixi/bin` (already on
PATH in every shell). The committed `pixi-global.toml` is the source of truth;
`sync.sh` copies it to `~/.pixi/manifests/` and runs `pixi global sync`.
```bash
# Apply the committed manifest (what sync.sh does)
cp pixi-global.toml ~/.pixi/manifests/pixi-global.toml && pixi global sync

# Add/remove a tool: edit pixi-global.toml, or use the CLI (which auto-exposes)
pixi global install --environment dotfiles <pkg>        # channel package
pixi global install --environment dotfiles --path ext/<name>   # source package
# then re-snapshot: cp ~/.pixi/manifests/pixi-global.toml ./pixi-global.toml
```
GUI apps (kitty, tev) ship a menuinst `menu.json`, so `pixi global` creates a
launcher automatically: a shim `~/Applications/<app>.app` on macOS (Spotlight-
indexable) and a `.desktop` entry on Linux. `ext/` holds the from-source package
recipes (built on demand by `pixi global install --path`).
**npm tools**: `gemini-cli` and `claude-code` build via a custom local backend
(`ext/pixi-build-npm`) that isn't published to a channel, so pixi needs
`PIXI_BUILD_BACKEND_OVERRIDE` set — `.envrc` and the install scripts do this. It
also requires `rattler-build` (installed via `pixi global` by `setup.sh`).

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
├── pixi.toml         # pixi manifest: conda deps + path deps to ext/ (platform-aware)
├── ext/              # From-source pixi packages (neovim nightly, sshr, kitty, tev,
│                     #   stow, passage, npm tools) + the custom pixi-build-npm backend
├── dconf.ini         # GNOME desktop settings (Linux only)
├── sync.sh           # Sync packages (pixi install), symlinks, and dconf
├── setup.sh          # First-time setup (installs pixi + rattler-build, syncs, decrypts age key)
└── update.sh         # pixi update and sync
```

## Architecture

- **`common/`**: The main stow package containing all portable configuration files. Files here are symlinked to `~` maintaining their directory structure. Used on both Linux and macOS.
- **`darwin/`**: macOS-specific stow package. Stowed in addition to `common/` on macOS only. Place macOS-specific config overrides here.
- **`stow/.stow-global-ignore`**: Applied first via `stow stow` to set up ignore patterns before symlinking common.
- **`pixi.toml`**: pixi manifest. Cross-platform tools are plain conda-forge `[dependencies]`; Linux-only packages (wl-clipboard, distrobox, nvtop, etc.) go in `[target.linux-64.dependencies]`. Tools not on conda-forge — or needing a newer/nightly build — are path deps to `ext/<name>` (rattler-build recipes). The env builds to `.pixi/envs/default`, whose `bin/` the shell config puts on PATH (replacing the old nix profile).
- **`ext/`**: From-source pixi packages. Each is a `pixi-build-rattler-build` recipe except the npm tools, which use the local `ext/pixi-build-npm` custom backend.
- **Secrets**: Uses age for encryption and passage for password management. The encrypted age key lives in `setup/age-key.age` and is decrypted to `~/.local/share/age/key.txt` by `setup.sh`. Note: `setup.sh` runs `sync.sh` first to build the pixi env, then calls `age` by its absolute path in `.pixi/envs/default/bin` (the env isn't on the script's PATH yet).

## Conventions

- **Git LFS**: Binary files in `.local/bin/` are tracked with Git LFS (see `.gitattributes`)
- **Catppuccin Macchiato**: Consistent dark theme used across starship, fish, bat, btop, kitty, and eza
- **Fish shell**: Default shell with vi-mode keybindings (`jk` for escape, `l` accepts autosuggestions)
- **Adding a new config**: Place files under `common/` mirroring their home directory path (e.g., `common/.config/foo/config` symlinks to `~/.config/foo/config`), then run `stow -t ~ -R common`. For macOS-specific configs, use `darwin/` instead.
- **Adding a new package**: If it's on conda-forge, add it to `[dependencies]` in `pixi.toml` (or `[target.linux-64.dependencies]` for Linux-only), then `pixi install`. If it's not on conda-forge (or needs a newer build), add a recipe under `ext/<name>/` and reference it as a path dependency — see the existing `ext/` packages as templates.
