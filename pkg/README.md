# pkg/ — a dead-simple, rootless package system

Replaces mise with boring, battle-tested package managers. One declarative list per
OS, one install command, no shims/backends/plugins.

| OS | Manager | List | Root needed |
|----|---------|------|-------------|
| macOS | Homebrew | [`Brewfile`](Brewfile) | no |
| Linux / any rootless box | conda-forge via `pixi global` | [`pixi-global.toml`](pixi-global.toml) | **no** |
| both | from-source / official builds | [`extras.sh`](extras.sh) | no |

Why this split: Homebrew is ideal on macOS (GUI casks, fresh dev tools) but its
prebuilt bottles need root for the standard prefix on Linux. conda-forge via pixi
is genuinely rootless everywhere and ships prebuilt binaries (no compiler), so it's
the right fit for user-only servers — which is the whole point.

## Install

```bash
pkg/install.sh          # detects OS -> brew bundle OR pixi global sync, then extras + stow
```

Everything lands in the manager's prefix + `~/.local`. Put these on PATH:
- macOS: `$(brew --prefix)/bin` and `~/.local/bin`
- Linux: `~/.pixi/bin` and `~/.local/bin`

## What's where

- **Package manager** (`Brewfile` / `pixi-global.toml`): ~40 CLI tools + runtimes —
  neovim, ripgrep, fd, gh, lazygit, btop, node, python, rust, fish, git, mosh, …
  and on macOS the GUI casks (kitty, tev) + the `claude` CLI cask.
- **`extras.sh`**: what neither manager carries — `sshr` (cargo build), `passage`
  (from source); on Linux the GUI/CLIs that are macOS casks (kitty, tev, claude,
  gemini-cli); on macOS `claude-agent-acp` (conda-forge, via pixi).

## Migrating off mise — SAFELY

`install.sh` touches **nothing** mise owns (it installs into brew/pixi/`~/.local`).
So you can run it alongside your current setup and verify before removing anything.

1. `pkg/install.sh` — installs the new toolset alongside mise.
2. Verify each tool works from the new prefix (e.g. `$(brew --prefix)/bin/nvim --version`,
   `~/.pixi/bin/rg --version`). Do this on **every** machine you care about — laptop
   *and* a real user-only server — before step 3.
3. Only once verified: put the new prefix ahead of the mise shims on PATH (edit the
   shell configs), restart your shell, confirm `which nvim` etc. resolve to the new one.
4. Optional, last: retire mise (`rm -rf ~/.local/share/mise ~/.config/mise`, drop the
   shims dir from PATH). Keep it until you're sure.

Never do step 4 before step 2 passes everywhere.

## Adding a tool

Add one line to `Brewfile` **and** `pixi-global.toml` (conda-forge names differ a
bit: `fd-find`, `tree-sitter-cli`, `nodejs`). If neither has it, add an installer to
`extras.sh`.
