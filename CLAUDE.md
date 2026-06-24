# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Cross-platform (Linux & macOS) dotfiles using:
- **GNU Stow** for symlink management of config files, and
- **`pixi global`** for package management — every CLI tool is installed into
  `~/.pixi/bin` (on PATH in every shell). Tools not on conda-forge, or needing a
  newer/nightly build, are compiled from source as pixi packages under `ext/`.

## Key Commands

### Initial Setup (new machine)
```bash
./setup.sh
```
Installs pixi (if missing) + `rattler-build`, runs `sync.sh`, then decrypts the
age key and sets up passage.

### Full Sync
```bash
./sync.sh
```
1. **pixi global** — copies `pixi-global.toml` to `~/.pixi/manifests/` and runs
   `pixi global sync` (installs tools into `~/.pixi/bin`, creates GUI shortcuts).
2. **GNU Stow** — symlinks configs (`common` everywhere, `darwin` on macOS).
   On macOS it also copies the fonts into `~/Library/Fonts` (see Fonts below).
3. **dconf** — loads GNOME settings (Linux only).

### Update All
```bash
./update.sh
```
Runs `pixi global update` (or re-`sync`) to refresh deps. For source packages
tracking a moving ref (neovim nightly, sshr `main`), force a clean rebuild:
`pixi global install --force-reinstall --environment dotfiles --path ext/neovim`.

### Stow Operations
```bash
stow -t ~ common        # apply (symlink into ~)
stow -t ~ -D common     # remove
stow -t ~ -R common     # re-stow (after adding files)
```
**Ordering matters**: `stow -t ~ stow` runs before `common` so the global ignore
rules are in place. `sync.sh` handles this.

### Pixi global (the package manager)
The committed **`pixi-global.toml`** is the source of truth; it defines one env
(`dotfiles`) containing all tools. `sync.sh` places it at
`~/.pixi/manifests/pixi-global.toml` and runs `pixi global sync`.
```bash
# Add a tool (auto-exposes its binaries), then re-snapshot the manifest:
pixi global install --environment dotfiles <pkg>              # conda-forge package
pixi global install --environment dotfiles --path ext/<name> # from-source package
cp ~/.pixi/manifests/pixi-global.toml ./pixi-global.toml
```
- **GUI apps** (kitty, tev) ship a menuinst `menu.json`, so `pixi global` creates
  a launcher automatically: a shim `~/Applications/<app>.app` on macOS (Spotlight-
  indexable) and a `.desktop` entry on Linux.
- **npm tools** (`gemini-cli`, `claude-code`) build via the local custom backend
  `ext/pixi-build-npm`, which isn't on a channel — so pixi needs
  `PIXI_BUILD_BACKEND_OVERRIDE` set (sync.sh and `.envrc` do this) and
  `rattler-build` installed (setup.sh does this).

## Repository Structure

```
dotfiles/
├── common/           # Main stow package — portable configs (both platforms)
│   ├── .config/      # XDG config (fish, starship, atuin, kitty, zellij, …)
│   ├── .local/bin/   # User binaries (Git LFS)
│   └── .local/share/fonts/  # Nerd Fonts (Git LFS); stow-linked on Linux
├── darwin/           # macOS-only stow package (config overrides)
├── stow/             # Stow global ignore rules (.stow-global-ignore)
├── setup/            # Encrypted secrets (age-key.age)
├── ext/              # From-source pixi package recipes (neovim nightly, sshr,
│                     #   kitty, tev, stow, passage, npm tools) + the custom
│                     #   pixi-build-npm backend
├── pixi-global.toml  # pixi global manifest — the installed tool set (source of truth)
├── pixi.toml         # legacy workspace manifest (dev/build only; not installed)
├── dconf.ini         # GNOME settings (Linux only)
├── sync.sh           # pixi global sync + stow + fonts + dconf
├── setup.sh          # first-time setup (pixi + rattler-build, sync, age key)
└── update.sh         # update deps and sync
```

## Architecture

- **`common/`** / **`darwin/`**: stow packages symlinked into `~`. `darwin` is
  stowed in addition to `common` on macOS only.
- **`stow/.stow-global-ignore`**: applied first so ignore rules are in place.
- **`pixi-global.toml`**: the installed tool set. One `dotfiles` env; conda-forge
  packages plus path deps to `ext/<name>` (paths are relative to
  `~/.pixi/manifests/`, e.g. `../../dotfiles/ext/kitty`). Binaries are exposed in
  `~/.pixi/bin`, which the shell configs put on PATH (replacing the old nix profile).
- **`ext/`**: from-source pixi packages. Each is a `pixi-build-rattler-build`
  recipe (build via `pixi global install --path`), except the npm tools which use
  the local `ext/pixi-build-npm` backend. `kitty`/`tev` also carry a `menu.json`
  for menuinst GUI shortcuts.
- **`pixi.toml` (legacy)**: the original workspace manifest. No longer the install
  mechanism — kept only as a scratch space for building/testing recipes. Safe to
  remove along with `.pixi/`.
- **Fonts**: source of truth is `common/.local/share/fonts/` (Git LFS). On Linux
  it's stow-linked to `~/.local/share/fonts` (fontconfig follows symlinks). On
  macOS `sync.sh` copies real files into `~/Library/Fonts` because **CoreText
  ignores symlinked fonts**.
- **Secrets**: age + passage. `setup/age-key.age` is decrypted to
  `~/.local/share/age/key.txt` by `setup.sh`, which calls `age` from `~/.pixi/bin`
  (where `pixi global` exposed it during the preceding sync).

## Conventions

- **Git LFS**: binaries in `.local/bin/` and `*.ttf` fonts are tracked via LFS.
- **Catppuccin Macchiato**: theme across starship, fish, bat, btop, kitty, eza.
- **Fish shell**: default shell with vi-mode keybindings.
- **Adding a config**: place under `common/` mirroring the home path, then
  `stow -t ~ -R common`. macOS-only configs go in `darwin/`.
- **Adding a tool**:
  - On conda-forge → `pixi global install --environment dotfiles <pkg>`.
  - Not on conda-forge / needs a newer build → add a recipe under `ext/<name>/`
    (copy an existing one), then `pixi global install --environment dotfiles --path ext/<name>`.
  - Either way, re-snapshot: `cp ~/.pixi/manifests/pixi-global.toml ./pixi-global.toml`.
  - For a GUI app, add a `menu.json` to the recipe so a shortcut is created.
```
