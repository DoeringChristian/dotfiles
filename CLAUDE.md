# CLAUDE.md

Guidance for Claude Code working in this repository.

## Overview

Cross-platform (macOS & Linux) dotfiles using:
- **GNU Stow** for symlinking config files into `~`, and
- **Homebrew** for **all** tool management. The tool list is a single
  [`Brewfile`](Brewfile); install with `brew bundle`. Two from-source tools come
  from an in-repo tap (`Formula/*.rb`).

There is no version manager (no mise/pixi/nix). Every tool is a brew formula or
cask; `brew upgrade` keeps them latest.

## Key commands

```bash
./bootstrap.sh   # one-liner entry: install git/curl, clone, run setup.sh
./setup.sh       # first-time: install Homebrew, then sync.sh, then decrypt secrets
./sync.sh        # reconcile: register/trust the tap, `brew bundle` (install missing),
                 # kitty .desktop on Linux, stow configs. No brew-install, no secrets.
./update.sh      # brew update && upgrade (+ rebuild the --HEAD formulae from git)
```
`setup.sh` = install Homebrew → `sync.sh` → decrypt the age key. So the package/
config logic lives once, in `sync.sh`; `setup.sh` just adds the one-time bits. For
packages only, `brew bundle` alone works (after the tap is registered).

`setup.sh` steps: install Homebrew → register the `doeringc/local` tap (copy
`Formula/*.rb` in) → `brew bundle --file Brewfile` → on Linux fetch the GUI apps
that can't be casks (kitty/tev/claude) → `stow` configs (+ macOS fonts/LaunchAgents)
→ decrypt the age key.

## The Brewfile (source of truth)

Each line is a tool. Notable entries:
- `brew "neovim", args: ["HEAD"]` — nightly-equivalent (brew pulls cmake/gettext).
- `brew "tree-sitter-cli"` — the CLI (the `tree-sitter` formula is only the library).
- `brew "python@3.13"` — provides `python3`; brew doesn't link a bare `python` on macOS.
- `brew "doeringc/local/sshr"`, `…/passage` — the in-repo tap formulae (`--HEAD`, git main).
- `cask "kitty"/"tev"/"claude-code" if OS.mac?` — macOS GUI apps + the `claude` CLI.
  On **Linux** casks don't exist, so `setup.sh` installs these from official builds.

`claude` is the `claude-code` cask with auto-update disabled via
`~/.claude/settings.json` (`autoUpdates:false`) so brew is the sole owner (no
version drift). Bump with `brew upgrade --cask`.

To add a tool: add a `Brewfile` line, run `./sync.sh`. From-source: add
`Formula/<name>.rb` + a `brew "doeringc/local/<name>"` line.

**Profiles**: the base `Brewfile` is installed everywhere; `Brewfile.<profile>`
(e.g. `Brewfile.workstation`) adds machine-type extras, layered via `--type`
(`./setup.sh --type workstation`). `sync.sh` parses `--type` and persists it to
`dotfiles.lock` (repo root, gitignored, per-machine) via the `lock_get`/`lock_set`
helpers, so a bare `./sync.sh` reuses the saved profile. Precedence: `--type` arg >
`dotfiles.lock` > `base`. `setup.sh`/`bootstrap.sh` forward `--type` to `sync.sh`.

## Repository structure

```
Brewfile          # the tool list
Formula/          # in-repo brew tap (sshr.rb, passage.rb)
common/           # portable stow package (both platforms)
darwin/           # macOS-only stow package (config overrides + LaunchAgents)
stow/             # .stow-global-ignore
setup/            # encrypted age key (age-key.age)
setup.sh / bootstrap.sh / update.sh
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
  `~/.local/share/age/key.txt` (and `~/.passage/identities`) by `setup.sh`.
- **claudebox** (`common/.local/bin/claudebox`): sandboxes `claude` (Seatbelt on
  macOS / Bubblewrap on Linux). It resolves `command -v claude` and binds the real
  `$HOME` read-only — install-mechanism-agnostic, no special-casing.

## sshr (special case)

`sshr` (SSH wrapper) is the `doeringc/local/sshr` tap formula (`--HEAD`, git main).
The formula also installs its `share/sshr/{shpool,kitty}` data next to the binary
(shpool = prebuilt remote binaries it scp's to hosts). Its **kitty kittens** are
also vendored at `common/.config/sshr/kitty/` (stow-linked) and referenced from
`kitty.conf`. Local state: Linux `~/.local/share/sshr`; macOS
`~/Library/Application Support/sshr` (the `dirs` crate) — so `~/.local/share/sshr`
legitimately won't exist on a Mac.

## Conventions

- **Git LFS**: `.local/bin/` binaries and `*.ttf` fonts.
- **Catppuccin Macchiato**: theme across starship, fish, bat, btop, kitty, eza.
- **Fish** is the default shell (vi-mode). PATH is set in `config.fish` via
  `brew shellenv`; no `mise activate` or version-manager hooks.
