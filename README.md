# dotfiles

Cross-platform (Linux & macOS) dotfiles, managed with two tools:

- **[GNU Stow](https://www.gnu.org/software/stow/)** — symlinks config files from
  this repo into `~`.
- **[pixi](https://pixi.sh) (`pixi global`)** — installs every command-line tool
  into `~/.pixi/bin` (on `PATH` in every shell). Tools that aren't on conda-forge,
  or that need a newer/nightly build, are compiled from source as pixi packages
  under [`ext/`](ext/).

This replaces a previous Nix-flake setup; `pixi global` now owns the toolchain.

## Quick start

```bash
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
./setup.sh      # installs pixi + rattler-build, syncs everything, sets up secrets
```

Day-to-day:

```bash
./sync.sh       # apply: pixi global sync + stow configs + fonts (+ dconf on Linux)
./update.sh     # refresh tool versions, then sync
```

After a sync, **restart your terminal** so new tools, fonts, and GUI apps are
picked up.

## How it works

| Concern | Mechanism |
|---|---|
| CLI tools | `pixi global`, defined by [`pixi-global.toml`](pixi-global.toml) → `~/.pixi/bin` |
| From-source / nightly tools | recipes in [`ext/`](ext/) (neovim nightly, kitty, tev, sshr, stow, passage, …) |
| npm tools (gemini-cli, claude-code) | custom [`ext/pixi-build-npm`](ext/pixi-build-npm) build backend |
| GUI apps (kitty, tev) | menuinst shortcuts → `~/Applications/*.app` (macOS) / `.desktop` (Linux) |
| Config files | GNU Stow (`common/` everywhere, `darwin/` on macOS) |
| Fonts | `common/.local/share/fonts/` (LFS); stow-linked on Linux, copied to `~/Library/Fonts` on macOS |
| Secrets | [age](https://github.com/FiloSottile/age) + [passage](https://github.com/FiloSottile/passage) |

## Layout

```
common/   # portable config (stowed on all platforms)
darwin/   # macOS-only config (stowed on macOS)
ext/      # from-source pixi package recipes + the npm build backend
stow/     # stow global ignore rules
setup/    # encrypted age key
pixi-global.toml   # the installed tool set (source of truth)
setup.sh / sync.sh / update.sh
```

## Adding things

The tool list is [`pixi-global.toml`](pixi-global.toml) — edit it like the old
flake's package list, then run `./sync.sh`.

- **A config file**: drop it under `common/` mirroring its `~` path, then
  `stow -t ~ -R common`.
- **A conda-forge tool**: add it under `[envs.dotfiles.dependencies]` and its
  binary under `[envs.dotfiles.exposed]`:
  ```toml
  ripgrep = "*"      # in [envs.dotfiles.dependencies]
  rg = "rg"          # in [envs.dotfiles.exposed]
  ```
  then `./sync.sh`.
- **A from-source / GUI tool**: add a recipe under `ext/<name>/` (copy an existing
  one; add a `menu.json` + a `shortcuts` entry for GUI apps), reference it as
  `name = { path = "ext/<name>" }`, expose its binary, then `./sync.sh`.

> **Don't run `pixi global install`** — it rewrites `pixi-global.toml` in an
> unreadable machine format. Only `pixi global sync` / `update` are used.

See [`CLAUDE.md`](CLAUDE.md) for the detailed architecture.
