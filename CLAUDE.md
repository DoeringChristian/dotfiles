# CLAUDE.md

Guidance for Claude Code working in this repository.

## Overview

Cross-platform (macOS & Linux) dotfiles using:
- **GNU Stow** for symlinking config files into `~`, and
- **Homebrew** for **all** tool management. The tool list is a single
  [`Brewfile`](Brewfile); install with `brew bundle`. Some packages come from
  an in-repo tap (`Formula/*.rb`).

There is no version manager (no mise/pixi/nix). Every tool is a brew formula or
cask; `brew upgrade` keeps them latest.

## Key commands

```bash
./bootstrap.sh              # first-time (curl | bash, or in a clone): install git/curl,
                            # clone, install Homebrew, run update.sh, decrypt the age key
./bootstrap.sh --no-root    # rootless install into ~/.homebrew (no sudo needed)
./update.sh                 # reconcile + upgrade: register/trust the tap, `brew bundle`
                            # (install missing), brew upgrade (+ casks --greedy, --HEAD
                            # rebuilds, npm globals), Linux app fixups, stow configs.
                            # No brew-install, no secrets.
```
`bootstrap.sh` = git/curl → clone (skipped when run from a clone) → install
Homebrew → `update.sh` → decrypt the age key. So the package/config logic lives
once, in `update.sh`; `bootstrap.sh` just adds the one-time bits. For packages
only, `brew bundle` alone works (after the tap is registered).

## The Brewfile (source of truth)

Each line is a tool. Notable entries:
- `brew "doeringc/local/neovim", args: ["HEAD"]` — nightly-equivalent; the local formula prevents mixed host/Homebrew glibc headers on Linux.
- `brew "tree-sitter-cli"` — the CLI (the `tree-sitter` formula is only the library).
- `brew "python@3.13"` — provides `python3`; brew doesn't link a bare `python` on macOS.
- `brew "doeringc/local/neovim"`, `…/resh`, `…/passage`, and Linux `…/zathura*` / `…/hyperqueue` (prebuilt `hq`; macOS builds it via `cargo`) — the in-repo tap formulae.
- `cask "claude-code@latest"`, `cask "codex"`, GUI apps — casks work on Linux too;
  `update.sh` adds Linux fixups (kitty `.desktop`, tev AppImage repack).

`claude` is the `claude-code` cask with auto-update disabled via
`~/.claude/settings.json` (`autoUpdates:false`) so brew is the sole owner (no
version drift). Bump with `brew upgrade --cask`.

To add a tool: add a `Brewfile` line, run `./update.sh`. From-source: add
`Formula/<name>.rb` + a `brew "doeringc/local/<name>"` line.

**Profiles**: the base `Brewfile` is installed everywhere; `Brewfile.<profile>`
(e.g. `Brewfile.workstation`) adds machine-type extras, layered via `--type`
(`./bootstrap.sh --type workstation`). `update.sh` parses `--type` and persists it to
`dotfiles.lock` (repo root, gitignored, per-machine) via the `lock_get`/`lock_set`
helpers, so a bare `./update.sh` reuses the saved profile. Precedence: `--type` arg >
`dotfiles.lock` > `base`. `bootstrap.sh` forwards `--type` to `update.sh`.

## Repository structure

```
Brewfile          # the tool list
Formula/          # in-repo brew tap (neovim.rb, resh.rb, passage.rb, zathura*.rb, hyperqueue.rb)
common/           # portable stow package (both platforms)
darwin/           # macOS-only stow package (config overrides + LaunchAgents)
stow/             # .stow-global-ignore
setup/            # encrypted age key (age-key.age)
bootstrap.sh / update.sh
```

## Architecture notes

- **Stow ordering**: `stow -t ~ stow` runs before `common` so the global ignore
  rules are in place; `darwin` is stowed in addition to `common` on macOS.
- **Fonts**: source is `common/.local/share/fonts/` (Git LFS). Linux follows the
  stow symlink; macOS copies real files into `~/Library/Fonts` (CoreText ignores
  symlinked fonts).
- **PATH**: the shell configs put the Homebrew prefix on PATH via `brew shellenv`,
  plus `~/.local/bin`, and append `~/.pixi/bin` (pixi is kept standalone for
  project toolchains). No version-manager shims.
- **Secrets**: age + passage. `setup/age-key.age` is decrypted to
  `~/.local/share/age/key.txt` (and `~/.passage/identities`) by `bootstrap.sh`.
- **claudebox / codexbox** (`common/.local/bin/`): sandboxes Claude Code or Codex
  (Seatbelt on macOS / Bubblewrap on Linux). `codexbox` is shorthand for
  `claudebox --agent codex`. The launcher resolves the selected agent from `PATH`
  and binds the real `$HOME` read-only — install-mechanism-agnostic, no
  special-casing. Everything is readable except denied paths; writes are limited
  to the project and configured mounts. The defaults (agent state, `~/.cache`,
  denied credentials) are the built-in `DEFAULT_CONFIG` in the script;
  `common/.config/claudebox/config` adds this machine's extras (the age key). A
  project `.claudebox` only applies after `claudebox --trust`. All paths are
  symlink-resolved so bwrap can mount them. Keep it bash-3.2 compatible.
- **Shared agent skills**: `common/.agents/skills/` is the canonical skill
  directory for Codex/Pi and Claude. `common/.claude/skills` is a single
  relative symlink to it; add and edit skills only under `.agents/skills`.

## resh (special case)

`resh` (SSH wrapper) is the `doeringc/local/resh` tap formula (`--HEAD`, git main).
The formula also installs its `share/resh/{shpool,kitty}` data next to the binary
(shpool = prebuilt remote binaries it scp's to hosts). Its **kitty kittens** are
also vendored at `common/.config/resh/kitty/` (stow-linked) and referenced from
`kitty.conf`. Local state: Linux `~/.local/share/resh`; macOS
`~/Library/Application Support/resh` (the `dirs` crate) — so `~/.local/share/resh`
legitimately won't exist on a Mac.

## Conventions

- **Git LFS**: `.local/bin/` binaries and `*.ttf` fonts.
- **Catppuccin Macchiato**: theme across starship, fish, bat, btop, kitty, eza.
- **Fish** is the default shell (vi-mode). PATH is set in `config.fish` via
  `brew shellenv`; no `mise activate` or version-manager hooks.
