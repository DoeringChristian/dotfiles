# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Cross-platform (Linux & macOS) dotfiles using:
- **GNU Stow** for symlink management of config files, and
- **mise** (mise-en-place) for **all** package management — every tool (CLI,
  language runtime, GUI app, even from-source builds) is a mise tool in
  `mise.toml`, installed into `~/.local/share/mise` and exposed on PATH via shims.
  There is **no brew/apt "native layer"** — that's the whole point. Two in-repo
  mise **backend plugins** (`plugins/`) cover what the standard backends can't:
  `app:` (GUI apps from prebuilt binaries) and `src:` (from-source builds).

> Migrated from `pixi global` to mise. The package manifest is now `mise.toml`
> (not `pixi-global.toml`); `ext/` recipes are gone. If you see references to
> `~/.pixi` or a `native/` layer anywhere, they are stale.

## Key Commands

### Initial Setup (new machine)
One-liner (installs git+curl, clones, runs setup):
```bash
curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash -s -- workstation
```
`bootstrap.sh` → `setup.sh` (installs mise, runs sync.sh, decrypts the age key;
skip secrets with `SKIP_SECRETS=1`). Pick a profile with the arg or `MISE_ENV`
(`workstation` | `server`; omit for base).

### Full Sync
```bash
./sync.sh
```
1. **mise** — trust the config, link the in-repo backend plugins
   (`scripts/link-plugins.sh`), symlink `mise.toml` to `~/.config/mise/config.toml`
   (so tools are global), then `mise install` (the whole toolset). `mise.lock`
   keeps versions reproducible. Then a guarded fixup runs claude-code's
   `install.cjs` postinstall — mise's npm backend installs with `--ignore-scripts`,
   which skips the step that finalizes claude's native binary, so a fresh install
   or upgrade would otherwise leave `claude` erroring "native binary not installed".
   The fixup is a no-op when `claude --version` already works.
2. **Git LFS** — `git lfs pull` (fonts, `.local/bin` payloads).
3. **GNU Stow** — symlinks configs (`common` everywhere, `darwin` on macOS); on
   macOS also copies fonts into `~/Library/Fonts` (CoreText ignores symlinks).
4. **dconf** — loads GNOME settings (Linux only).

### Update
```bash
./update.sh                    # mise upgrade (all) + re-sync
./update.sh app:kitty claude-code   # upgrade only named tools
```
No build caches to bust (unlike the old pixi recipes) — mise installs prebuilt
artifacts, so `mise upgrade` is the whole story. `latest`-tracking tools
(claude-code, gemini-cli, neovim nightly, `app:kitty`/`app:tev`) re-resolve to
newest; pinned ones stay put.

### Try tools without touching anything global
```bash
bash scripts/test-shell.sh             # isolated throwaway shell, examples/test.mise.toml
bash scripts/test-shell.sh mise.toml   # test the real base config
```
Copies a config to a temp dir outside the repo, points all mise data there, links
the plugins, and drops you into a shell where the test shims outrank your global
PATH. Nothing global changes; `rm -rf` the printed workdir to wipe.

### Stow Operations
```bash
stow -t ~ common        # apply (symlink into ~)
stow -t ~ -D common     # remove
stow -t ~ -R common     # re-stow (after adding files)
```
**Ordering matters**: `stow -t ~ stow` runs before `common` so the global ignore
rules are in place. `sync.sh` handles this.

### mise (the package manager)
**`mise.toml` at the repo root is the hand-edited source of truth** — the tool
list (like the old flake's `paths` / pixi's `pixi-global.toml`). **All** mise
tools, including the GUI apps (`app:kitty`, `app:tev`) and `vpn-slice`, live here
and install on every machine. `sync.sh` symlinks it to mise's global config
(`~/.config/mise/config.toml`) so the tools are on PATH everywhere — the analog
of the old `pixi global` / `~/.pixi/bin`.

There are no profiles and no `MISE_ENV` switching: it's one tool list for every
machine. Platform differences are handled per-tool with `os = ["linux"]` /
`["macos"]` gating inside `mise.toml` (e.g. Linux-only `nvtop`, `xsel`, `ollama`).

To add a tool, edit `mise.toml` and run `./sync.sh`:
```toml
[tools]
ripgrep = "latest"                       # aqua/registry backend
node = "22"                              # pinned runtime
"npm:@anthropic-ai/claude-code" = "latest"   # npm backend
"cargo:https://github.com/me/foo" = "branch:main"  # build a Rust tool from git
"conda:git" = "latest"                   # conda-forge package (system CLIs, base utils, …)
"app:kitty" = "latest"                   # GUI app (in-repo app: backend)
"src:stow" = "latest"                    # from-source build (in-repo src: backend)
"conda:nvtop" = { version = "latest", os = ["linux"] }   # os-gate Linux-only tools
```
Pick the backend by where the tool lives: registry/aqua for tools with a GitHub
release binary; `npm:`/`pipx:`/`cargo:` for language-ecosystem tools; `app:` for
GUI apps; `conda:` for anything conda-forge builds that has no good release binary
(system CLIs like git/fish/curl, btop on macOS, …); `src:` for tools built from
source. mise's `conda:` backend has rattler built in, so it needs **no**
conda/micromamba install. Use `os = ["linux"]`/`["macos"]` to gate per platform.

- **In-repo backend plugins** (`plugins/`, linked locally by
  `scripts/link-plugins.sh` — no need to publish them):
  - `app:` (`plugins/mise-app`) — GUI apps from each project's **official
    prebuilt GitHub binaries**. `registry.lua` declares a repo + per-platform
    download-URL template; versions resolve live from GitHub releases (no hashes).
    Installs `.dmg`/`.txz`/AppImage, puts launchers on PATH, and creates a desktop
    entry (`.app` in `~/Applications` on macOS, `.desktop` on Linux). Add an app
    by copying the `tev` entry in `registry.lua`.
  - `src:` (`plugins/mise-src`) — **from-source builds** (the analog of pixi's
    `ext/` recipes) for tools with no binary backend. `registry.lua` holds a fetch
    spec (tarball or git) + a `build_tools` list + build commands run with
    `$PREFIX` = the install dir. The build is **hermetic**: `build_tools` (make,
    perl) are supplied from conda-forge via `mise x`, so the HOST needs no
    toolchain (matching pixi's recipe build deps). Used for GNU `stow`, `passage`,
    and `sshr` (Rust/cargo; also installs `share/sshr/{shpool,kitty}` — see the
    sshr note below). A tool's runtime interpreter (perl for stow) is a regular
    mise tool (`conda:perl`) so it's guaranteed on PATH — never a host perl.
- **No native layer.** There is deliberately no brew/apt/dnf step. System CLIs
  (git, fish, tree, wget, mosh, ncdu, curl, …) come from `conda:`; GPU/desktop
  Linux tools (nvtop, xsel, openconnect, ollama) are `conda:`/`aqua:` os-gated to
  Linux. CUDA/drivers themselves remain the distro's job, outside this repo.

### sshr (special case)
`sshr` (your SSH wrapper) installs via the in-repo **`src:` backend** (built from
`main`; see `plugins/mise-src/registry.lua`). A plain `cargo install` would drop
its data files, so the recipe also installs `share/sshr/{shpool,kitty}` next to
the binary — `shpool` is the set of prebuilt remote binaries `sshr` scp's to a
host on first connect, found at runtime by walking up from the binary for
`share/sshr/shpool/bin` (or `$SSHR_SHPOOL_DIR`). Its **kitty kittens**
(`smart_launch.py` / `smart_close.py`) are *also* vendored into this repo at
`common/.config/sshr/kitty/` (stow-linked to `~/.config/sshr/kitty/`) and
referenced from `kitty.conf` there.

Note on local state: on Linux sshr writes its session WAL to `$XDG_DATA_HOME`
(`~/.local/share/sshr`); on **macOS** the `dirs` crate maps that to
`~/Library/Application Support/sshr` instead — so `~/.local/share/sshr` legitimately
won't exist on a Mac. The `~/.local/share/sshr/...` paths baked into the binary are
*remote*-host paths (where shpool lands on the server), created on connect.

## Repository Structure

```
dotfiles/
├── common/           # Main stow package — portable configs (both platforms)
│   ├── .config/      # XDG config (fish, starship, atuin, kitty, zellij, sshr/kitty, …)
│   ├── .local/bin/   # User binaries (claudebox, Git LFS payloads)
│   └── .local/share/fonts/  # Nerd Fonts (Git LFS)
├── darwin/           # macOS-only stow package (config overrides)
├── stow/             # Stow global ignore rules (.stow-global-ignore)
├── setup/            # Encrypted secrets (age-key.age)
├── mise.toml         # THE tool list (source of truth — the whole toolset)
├── mise.lock         # pinned versions/checksums for reproducibility
├── plugins/          # in-repo mise backends: mise-app (app:), mise-src (src:)
├── scripts/          # link-plugins.sh, test-shell.sh
├── examples/         # test.mise.toml (one entry per backend, for test-shell)
├── dconf.ini         # GNOME settings (Linux only)
├── bootstrap.sh      # one-liner entry: install git/curl, clone, run setup.sh
├── setup.sh          # first-time: install mise, sync, decrypt age key
├── sync.sh           # mise install + Git-LFS + stow + fonts + dconf
└── update.sh         # mise upgrade + sync
```

## Architecture

- **`common/`** / **`darwin/`**: stow packages symlinked into `~`. `darwin` is
  stowed in addition to `common` on macOS only.
- **`stow/.stow-global-ignore`**: applied first so ignore rules are in place.
- **`mise.toml`**: the tool list. mise installs into `~/.local/share/mise` and
  its **shims** dir (`~/.local/share/mise/shims`) goes on PATH (replacing the old
  `~/.pixi/bin`). There are no profiles — one tool list for every machine, with
  per-tool `os = [...]` gating. The `app:`/`src:` backends are linked from
  `plugins/` by `scripts/link-plugins.sh` before `mise install` (a `mise run` task
  can't link them — it resolves the tool env first).
- **Shell PATH (no `mise activate`)**: the shell configs put
  `~/.local/share/mise/shims` on PATH directly and deliberately do **not** run
  `mise activate`. `mise activate`'s per-prompt `hook-env` re-invokes mise on every
  prompt; if a version resolution there is slow (e.g. an os-gated tool with no
  build for this platform), the hung invocations pile up — once enough accumulate
  you hit the per-user process cap and the shell can't `fork` ("Resource not
  available"). Shims resolve versions lazily only when a tool actually runs, which
  is all a single global toolset needs. **Do not add `mise activate` back.**
- **pixi is standalone, not a mise tool**: pixi is a package manager in its own
  right (used for project toolchains like mitsuba). It lives at `~/.pixi/bin`,
  self-updates via `pixi self-update`, and the shell configs **append** that dir to
  PATH so it only provides `pixi` and never shadows a mise tool. Installing pixi
  via mise's `github:` backend was redundant and broke on GitHub attestation
  verification, so it is intentionally absent from `mise.toml`.
- **Fonts**: source of truth is `common/.local/share/fonts/` (Git LFS). On Linux
  it's stow-linked to `~/.local/share/fonts` (fontconfig follows symlinks). On
  macOS `sync.sh` copies real files into `~/Library/Fonts` because **CoreText
  ignores symlinked fonts**. (Not installed via mise/brew.)
- **Secrets**: age + passage. `setup/age-key.age` is decrypted to
  `~/.local/share/age/key.txt` by `setup.sh`, which calls `age` via
  `mise exec -- age` (age is a mise tool).

## Conventions

- **Git LFS**: binaries in `.local/bin/` and `*.ttf` fonts are tracked via LFS.
- **Catppuccin Macchiato**: theme across starship, fish, bat, btop, kitty, eza.
- **Fish shell**: default shell with vi-mode keybindings. `config.fish` puts the
  mise shims dir on PATH via `fish_add_path` — it does **not** `mise activate`
  (see the PATH note under Architecture).
- **Adding a config**: place under `common/` mirroring the home path, then
  `stow -t ~ -R common`. macOS-only configs go in `darwin/`.
- **Adding a tool**: edit `mise.toml`, then `./sync.sh` (installs on all machines).
  Everything is a mise tool — pick the backend (see "mise (the package manager)"
  above); os-gate Linux-only tools with `os = ["linux"]`.
