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
One-liner (installs git+curl, clones, runs setup):
```bash
curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
```
Or, in an existing checkout, `./setup.sh` directly. `setup.sh` installs pixi (if
missing), runs `sync.sh`, then decrypts the age key and sets up passage (skip the
secrets step with `SKIP_SECRETS=1`, e.g. in CI / the docker tests).

### Full Sync
```bash
./sync.sh
```
1. **pixi global** — symlinks `pixi-global.toml` into `~/.pixi/manifests/` and runs
   `pixi global sync` (installs tools into `~/.pixi/bin`, creates GUI shortcuts).
   Then `git lfs pull` (pixi installed git-lfs) so LFS payloads (fonts, .local/bin)
   are real files, not pointers — important on a fresh clone.
2. **GNU Stow** — symlinks configs (`common` everywhere, `darwin` on macOS).
   On macOS it also copies the fonts into `~/Library/Fonts` (see Fonts below).
3. **dconf** — loads GNOME settings (Linux only).

`sync.sh` puts `~/.pixi/bin` on its own PATH and honors `$PIXI_GLOBAL_MANIFEST`
(an alternate manifest, used by the docker tests for a fast minimal run).

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
**`pixi-global.toml` at the repo root is the hand-edited source of truth** — like
the old flake's `paths` list. `sync.sh` **symlinks** it to
`~/.pixi/manifests/pixi-global.toml` and runs `pixi global sync`.

To add a tool, edit `pixi-global.toml` directly and run `./sync.sh`:
```toml
[envs.dotfiles.dependencies]
ripgrep = "*"                    # conda-forge package
foo = { path = "ext/foo" }       # from-source recipe (path relative to repo root)
[envs.dotfiles.exposed]
rg = "rg"                        # which binary(s) to surface onto ~/.pixi/bin
```
**Do NOT run `pixi global install`** — it rewrites `pixi-global.toml` in an
unreadable machine format (and would clobber the symlinked source). Only
`pixi global sync` and `pixi global update` are safe (they don't touch the file).

Why root + symlink (not stow): pixi resolves `ext/<name>` path-deps relative to
the manifest's **real** location (it canonicalizes the symlink). At the repo root
that's a clean `ext/<name>`; under a stow path it would be `../../../ext/<name>`.

- **GUI apps** (kitty, tev): listed under `shortcuts`. Their recipe ships a
  menuinst `menu.json`, so `sync` creates a shim `~/Applications/<app>.app` on
  macOS (Spotlight-indexable) and a `.desktop` on Linux.
- **npm tools** (`gemini-cli`, `claude-code`) are thin rattler-build recipes whose
  `build.sh` runs `npm install -g … --prefix $PREFIX`. (They use the standard
  `pixi-build-rattler-build` backend so they build under `pixi global sync` with no
  backend override.)

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
│                     #   kitty, tev, stow, passage, gemini-cli, claude-code)
├── tests/            # docker-based bootstrap tests (tests/run.sh)
├── pixi-global.toml  # THE tool list (source of truth; symlinked to ~/.pixi/manifests)
├── dconf.ini         # GNOME settings (Linux only)
├── bootstrap.sh      # one-liner entry: install git/curl, clone, run setup.sh
├── sync.sh           # pixi global sync + git lfs pull + stow + fonts + dconf
├── setup.sh          # first-time setup (install pixi, sync, decrypt age key)
└── update.sh         # update deps and sync
```

## Architecture

- **`common/`** / **`darwin/`**: stow packages symlinked into `~`. `darwin` is
  stowed in addition to `common` on macOS only.
- **`stow/.stow-global-ignore`**: applied first so ignore rules are in place.
- **`pixi-global.toml`**: the tool list. One `dotfiles` env; conda-forge packages
  plus `ext/<name>` path-deps (relative to the repo root). `sync.sh` symlinks it
  to `~/.pixi/manifests/` and `pixi global sync` reconciles the env. The listed
  `exposed` binaries are surfaced in `~/.pixi/bin`, which the shell configs put on
  PATH (replacing the old nix profile). Edit this file by hand; never
  `pixi global install` (it rewrites it).
- **`ext/`**: from-source pixi packages. Each is a `pixi-build-rattler-build`
  recipe, built on demand by `pixi global sync`. The npm tools (`gemini-cli`,
  `claude-code`) are recipes whose `build.sh` runs `npm install`. `kitty`/`tev`
  also carry a `menu.json` for menuinst GUI shortcuts.
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
- **Adding a tool**: edit `pixi-global.toml` (add the dep under
  `[envs.dotfiles.dependencies]` and its binary under `[envs.dotfiles.exposed]`),
  then `./sync.sh`.
  - On conda-forge → `name = "*"`.
  - Not on conda-forge / needs a newer build → add a recipe under `ext/<name>/`
    (copy an existing one) and reference it as `name = { path = "ext/<name>" }`.
  - For a GUI app, add a `menu.json` to the recipe and list it under `shortcuts`.
