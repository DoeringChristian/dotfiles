# pkg/ — one manifest, per-package install method, always latest

Replaces mise with something boring: a single list where **each tool declares how
it's installed and kept current**, and everything tracks the **newest version that
exists**. No shims, backends, or plugins.

- **[`packages`](packages)** — the whole toolset, one line per tool: `<name> <method> [opts]`.
- **[`install.sh`](install.sh)** — reads the manifest, installs each tool by its method at latest.
- **[`update.sh`](update.sh)** — brings everything to the newest version.

## Methods

| method | how it installs / stays latest | example |
|--------|-------------------------------|---------|
| `pkg`   | Homebrew (macOS) / conda-forge via `pixi global` (Linux, **rootless**). `conda=<name>` if the name differs. | `ripgrep`, `neovim` |
| `cask`  | Homebrew cask (macOS GUI) / official build on Linux (`github=<owner/repo>`). | `kitty`, `tev` |
| `conda` | conda-forge via pixi on both platforms (things Homebrew lacks). | `claude-agent-acp` |
| `npm`   | `npm install -g …@latest`. `pkg=<npm-name>`. | `gemini-cli` |
| `uv`    | `uv tool install` (Python CLIs). | `vpn-slice` |
| `self`  | the tool's **own installer**; it self-updates (fine/wanted). `url=<installer>`. | `claude` |
| `source`| build from **git main** = latest. `url=<git>`, `build=<cargo\|make>`. | `sshr`, `passage` |

Why the macOS/Linux split under `pkg`: Homebrew is best on macOS but its bottles
need root for the standard prefix on Linux; conda-forge via pixi is genuinely
rootless with prebuilt binaries — right for user-only servers, which is the point.
Self-managed tools (`claude`) just use their own updater, so there's nothing to
fight over.

## Use

```bash
pkg/install.sh     # install everything at latest, per method, + stow configs
pkg/update.sh      # bring everything to newest
```

Add a tool → add a line to `packages`. Change how it's managed → change its method.

## Migrating off mise — SAFELY

`install.sh` installs into the brew/pixi prefixes + `~/.local` and **never touches
`~/.local/share/mise` or your PATH files** — so it runs alongside your current setup.

1. `pkg/install.sh` — install the new toolset alongside mise.
2. Verify every tool works from the new prefix, on **laptop *and* a real user-only
   server**, before touching anything else.
3. Only then: put the new prefix (`$(brew --prefix)/bin` / `~/.pixi/bin`) and
   `~/.local/bin` ahead of the mise shims on PATH; restart; confirm resolution.
4. Last, optional: remove mise (`rm -rf ~/.local/share/mise ~/.config/mise`, drop
   the shims dir from PATH). Never before step 2 passes everywhere.
