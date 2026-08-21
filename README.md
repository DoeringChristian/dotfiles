# dotfiles

Cross-platform (macOS & Linux) dotfiles, managed with two tools:

- **[GNU Stow](https://www.gnu.org/software/stow/)** — symlinks config files from
  this repo into `~`.
- **[Homebrew](https://brew.sh)** — installs **every** tool from a single
  [`Brewfile`](Brewfile). Two from-source tools (`sshr`, `passage`) come from an
  in-repo tap ([`Formula/`](Formula)); GUI apps are casks on macOS and official
  builds on Linux.

## Quick start

Fresh machine — one line (installs git+curl, clones, installs Homebrew + everything):

```bash
curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
```

Or by hand:

```bash
git clone https://github.com/doeringchristian/dotfiles ~/dotfiles
cd ~/dotfiles && ./setup.sh
```

Day-to-day:

```bash
./sync.sh     # install any missing packages (brew bundle) + re-apply configs. Run
              # this after adding a tool to the Brewfile or a config to common/.
./update.sh   # bump everything to the newest version
# (or just `brew bundle` for packages only; `./setup.sh` is the first-time full run)
```

After setup, **restart your terminal**.

## Profiles (per-machine package sets)

The base `Brewfile` is installed everywhere. Extra packages for a machine type live
in `Brewfile.<profile>` and are layered on top with `--type`:

```bash
./setup.sh --type workstation   # base + Brewfile.workstation (inkscape, …)
./sync.sh  --type workstation   # same, day-to-day
./setup.sh                      # base only (a plain server)
# one-liner:  … | bash -s -- --type workstation
```

Add a profile = add a `Brewfile.<name>` (same DSL: `brew`/`cask`/`npm`/…). Servers
just use the base (no `--type`). `update.sh` upgrades whatever's installed, so it
needs no profile.

## How it works

| Concern | Mechanism |
|---|---|
| CLI tools + runtimes | Homebrew, one line each in [`Brewfile`](Brewfile) |
| neovim (nightly) | `brew "neovim", args: ["HEAD"]` (master build) |
| From-source tools (`sshr`, `passage`) | in-repo tap `Formula/*.rb`, built with `brew --HEAD` from git main |
| GUI apps (kitty, tev) + the `claude` CLI | brew **casks** on macOS; **official builds** on Linux (`setup.sh`) |
| Config files | GNU Stow (`common/` everywhere, `darwin/` on macOS) |
| Fonts | `common/.local/share/fonts/` (LFS); stow-linked on Linux, copied to `~/Library/Fonts` on macOS |
| macOS services | LaunchAgents in `darwin/Library/LaunchAgents/` (e.g. the ollama server) |
| Secrets | [age](https://github.com/FiloSottile/age) + [passage](https://github.com/FiloSottile/passage) |

`claude` is the `claude-code` cask with its self-updater disabled
(`~/.claude/settings.json` `autoUpdates:false`), so Homebrew is the sole owner —
bump it with `brew upgrade --cask`.

## Layout

```
Brewfile            # THE tool list (source of truth)
Formula/            # in-repo brew tap: sshr.rb, passage.rb
common/             # portable config (stowed on all platforms)
darwin/             # macOS-only config (stowed on macOS), incl. LaunchAgents
stow/               # stow global ignore rules
setup/              # encrypted age key
setup.sh / bootstrap.sh / update.sh
```

## Adding things

- **A tool**: add a line to [`Brewfile`](Brewfile) (`brew "…"` / `cask "…" if OS.mac?`),
  then `./setup.sh` (or `brew bundle`).
- **A from-source tool**: add `Formula/<name>.rb` and a
  `brew "doeringc/local/<name>"` line to the Brewfile.
- **A config file**: drop it under `common/` mirroring its `~` path, then
  `stow -t ~ -R common`. macOS-only configs go in `darwin/`.

See [`CLAUDE.md`](CLAUDE.md) for the detailed architecture.
