# Brewfile — the complete toolset, installed with `brew bundle` (run by setup.sh).
# One list for every machine. macOS uses casks for GUI apps; on Linux (no cask
# support) setup.sh installs those from official builds instead.
#
# Two tools come from the in-repo tap (Formula/*.rb), which setup.sh registers
# before `brew bundle`: sshr and passage (built from git main via --HEAD).
#
# Add a tool = add a line. Keep everything at latest with `./update.sh`.

# --- language runtimes ---
brew "python@3.13"          # `python3`; brew doesn't link a bare `python` on macOS
brew "node"
brew "rust"

# --- editors ---
brew "neovim", args: ["HEAD"]   # master (~= nightly); brew pulls cmake/gettext to build
brew "vim"

# --- search / files / navigation ---
brew "ripgrep"
brew "fd"
brew "eza"
brew "bat"
brew "fzf"
brew "zoxide"
brew "dust"
brew "duf"
brew "tree-sitter-cli"          # the CLI; the `tree-sitter` formula is only the library

# --- git / dev ---
brew "gh"
brew "git-lfs"
brew "lazygit"
brew "direnv"
brew "starship"
brew "atuin"
brew "zellij"

# --- monitoring / tooling / secrets / typesetting / config ---
brew "btop"
brew "uv"
brew "pixi"                     # package manager for project toolchains (mitsuba, …)
brew "age"
brew "typst"
brew "stow"

# --- base + system CLIs ---
brew "git"
brew "fish"
brew "tree"
brew "wget"
brew "mosh"
brew "ncdu"
brew "curl"
brew "unzip"
brew "zip"
brew "gzip"
brew "less"

# --- Linux clipboard (nvim's +register needs a helper; macOS has pbcopy built in) ---
brew "wl-clipboard" if OS.linux?   # Wayland (wl-copy/wl-paste) — GNOME default
brew "xclip" if OS.linux?          # X11 fallback

# --- LLM runtime + AI CLIs ---
brew "ollama"
npm "@google/gemini-cli"        # via brew bundle's npm entry -> latest (brew's formula lags)

# --- from source, via the in-repo tap (setup.sh registers Formula/*.rb) ---
# HEAD-only formulae (no stable release) -> args: ["HEAD"] so brew bundle builds
# from git main instead of erroring on a missing stable.
brew "doeringc/local/sshr", args: ["HEAD"]      # Rust SSH wrapper
brew "doeringc/local/passage", args: ["HEAD"]   # age-backed password store

# --- GUI apps + claude CLI (brew casks — these ship Linux variations, so
#     `brew bundle` installs them on Linux too, not just macOS) ---
cask "kitty"
cask "tev"
# claude-code@latest tracks the newest release (the plain claude-code cask is
# pinned/older). brew owns it; auto-update is off in ~/.claude/settings.json.
cask "claude-code@latest"
cask "codex"
