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

# --- LLM runtime + AI CLIs ---
brew "ollama"
brew "gemini-cli"               # brew trails npm a little; accepted for uniformity

# --- from source, via the in-repo tap (setup.sh registers Formula/*.rb) ---
# HEAD-only formulae (no stable release) -> args: ["HEAD"] so brew bundle builds
# from git main instead of erroring on a missing stable.
brew "doeringc/local/sshr", args: ["HEAD"]      # Rust SSH wrapper
brew "doeringc/local/passage", args: ["HEAD"]   # age-backed password store

# --- GUI apps + the claude CLI (macOS casks; Linux builds handled by setup.sh) ---
cask "kitty" if OS.mac?
cask "tev" if OS.mac?
cask "claude-code" if OS.mac?   # the `claude` CLI; auto-update disabled in ~/.claude/settings.json
