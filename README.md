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

On a fresh machine — one line. It installs the only prerequisites (git + curl),
clones the repo, and lets pixi pull in everything else:

```bash
curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
```

Or by hand:

```bash
git clone https://github.com/doeringchristian/dotfiles ~/dotfiles
cd ~/dotfiles && ./setup.sh      # installs pixi, syncs everything, sets up secrets
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
| npm tools (gemini-cli, claude-code) | thin `ext/` recipes whose `build.sh` runs `npm install` |
| GUI apps (kitty, tev) | menuinst shortcuts → `~/Applications/*.app` (macOS) / `.desktop` (Linux) |
| Config files | GNU Stow (`common/` everywhere, `darwin/` on macOS) |
| Fonts | `common/.local/share/fonts/` (LFS); stow-linked on Linux, copied to `~/Library/Fonts` on macOS |
| Secrets | [age](https://github.com/FiloSottile/age) + [passage](https://github.com/FiloSottile/passage) |

## Layout

```
common/   # portable config (stowed on all platforms)
darwin/   # macOS-only config (stowed on macOS)
ext/      # from-source pixi package recipes
stow/     # stow global ignore rules
setup/    # encrypted age key
tests/    # docker-based bootstrap tests (tests/run.sh)
pixi-global.toml   # the installed tool set (source of truth)
bootstrap.sh / setup.sh / sync.sh / update.sh
```

## Testing

Test the bootstrap on a clean Linux container (needs docker):

```bash
tests/run.sh                 # ubuntu, fast smoke test
tests/run.sh fedora --full   # other distro, build everything
tests/run.sh ubuntu --remote # the real one-liner from origin/main
```

See [`tests/README.md`](tests/README.md).

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
