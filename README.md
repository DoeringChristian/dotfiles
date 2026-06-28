# dotfiles

Cross-platform (Linux & macOS) dotfiles, managed with two tools:

- **[GNU Stow](https://www.gnu.org/software/stow/)** — symlinks config files from
  this repo into `~`.
- **[mise](https://mise.jdx.dev)** — installs **every** tool (CLI, language
  runtime, GUI app, even from-source builds) into `~/.local/share/mise`, on `PATH`
  via shims. No brew/apt. Two in-repo mise **backend plugins** (`plugins/`) cover
  what the standard backends can't: `app:` (GUI apps) and `src:` (from source).

> Migrated from `pixi global` to mise. The tool list is now
> [`mise.toml`](mise.toml) (was `pixi-global.toml`); the `ext/` recipes and the
> brew/apt native layer are gone — everything is a mise tool.

## Quick start

On a fresh machine — one line. It installs the only prerequisites (git + curl),
clones the repo, and lets mise pull in everything else:

```bash
curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash -s -- workstation
```

Or by hand:

```bash
git clone https://github.com/doeringchristian/dotfiles ~/dotfiles
cd ~/dotfiles && MISE_ENV=workstation ./setup.sh   # installs mise, syncs, sets up secrets
```

Day-to-day:

```bash
./sync.sh       # mise install + Git-LFS + stow configs + fonts (+ dconf on Linux)
./update.sh     # mise upgrade, then sync
```

After a sync, **restart your terminal** so new tools, fonts, and GUI apps are
picked up. Pick a machine profile with `MISE_ENV=workstation|server` (omit for base).

## How it works

| Concern | Mechanism |
|---|---|
| CLI tools + runtimes | mise, defined by [`mise.toml`](mise.toml) → `~/.local/share/mise` |
| npm / pipx / cargo tools | mise backends (`npm:`, `pipx:`, `cargo:`) in `mise.toml` |
| System CLIs + base utils (git, fish, curl, …) | mise's built-in `conda:` backend (no conda install needed) |
| GUI apps (kitty, tev) | in-repo `app:` backend (`plugins/mise-app`) — GitHub prebuilt binaries + `.app`/`.desktop` launchers |
| From-source tools (stow, passage) | in-repo `src:` backend (`plugins/mise-src`) — build at install time |
| Linux-only tools (nvtop, xsel, ollama) | `conda:`/`aqua:` with `os = ["linux"]` gating |
| Config files | GNU Stow (`common/` everywhere, `darwin/` on macOS) |
| Fonts | `common/.local/share/fonts/` (LFS); stow-linked on Linux, copied to `~/Library/Fonts` on macOS |
| Secrets | [age](https://github.com/FiloSottile/age) + [passage](https://github.com/FiloSottile/passage) |

## Layout

```
common/   # portable config (stowed on all platforms)
darwin/   # macOS-only config (stowed on macOS)
plugins/  # in-repo mise backends: mise-app (app:), mise-src (src:)
scripts/  # link-plugins.sh, test-shell.sh
stow/     # stow global ignore rules
setup/    # encrypted age key
tests/    # docker-based bootstrap tests (tests/run.sh)
mise.toml + mise.lock   # the tool set (source of truth)
bootstrap.sh / setup.sh / sync.sh / update.sh
```

## Try tools without changing anything global

```bash
bash scripts/test-shell.sh             # isolated throwaway shell (examples/test.mise.toml)
bash scripts/test-shell.sh mise.toml   # test the real base config
```

Spins up a shell with the tools active in a temp dir outside the repo — nothing
global is touched. `rm -rf` the printed workdir to wipe.

## Adding things

The tool list is [`mise.toml`](mise.toml) — edit it, then `./sync.sh`.

- **A config file**: drop it under `common/` mirroring its `~` path, then
  `stow -t ~ -R common`.
- **A CLI tool / runtime**: add a line under `[tools]` (`ripgrep = "latest"`,
  `node = "22"`, `"npm:…" = "latest"`, …), then `./sync.sh`.
- **A GUI app**: add an entry to `plugins/mise-app/registry.lua` (copy `tev`) and
  a `"app:<name>" = "latest"` line to `mise.toml`.
- **A system CLI / base util**: `"conda:<name>" = "latest"` (conda-forge).
- **A from-source tool**: add a recipe to `plugins/mise-src/registry.lua` (copy
  `passage`) and a `"src:<name>" = "latest"` line.

Everything is a mise tool in the single `mise.toml`, installed on every machine.
Linux-only tools are gated with `os = ["linux"]`; there are no profiles.

## Decommissioning the old pixi `global` env

After migrating, retire the `pixi global` "dotfiles" environment that used to own
`~/.pixi/bin`. **Do this only once mise is global and verified** (so you're never
left without tools):

```bash
# 1. Make mise global + install everything (kitty/tev included), then verify:
./sync.sh
which kitty            # -> ~/.local/share/mise/shims/kitty  (NOT ~/.pixi/...)

# 2. Remove the pixi global env + its exposed binaries, and the stale manifest:
pixi global uninstall dotfiles
rm -f ~/.pixi/manifests/pixi-global.toml

# 3. Drop ~/.pixi/bin from PATH and reload (the fish config no longer adds it):
exec fish             # or restart your terminal
```

Keep the `pixi` binary itself — it's still used for project toolchains (mitsuba,
…); only the global `dotfiles` environment is being retired.

See [`CLAUDE.md`](CLAUDE.md) for the detailed architecture.

> Note: `tests/` still targets the old pixi bootstrap and needs updating for mise.
