#!/usr/bin/env bash
# setup.sh — first-time setup (mise edition). Mirrors the pixi setup.sh:
# install the package manager, run sync.sh, then decrypt the age secret.
#
#   ./setup.sh                 # base profile
#   MISE_ENV=workstation ./setup.sh
#   SKIP_SECRETS=1 ./setup.sh  # CI / docker tests
set -e

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

# Install mise if not present (replaces the old `curl pixi.sh/install.sh`).
if ! command -v mise >/dev/null 2>&1; then
    echo "mise not found. Installing..."
    curl -fsSL https://mise.run | sh
fi
# Ensure mise + its shims are on PATH for the rest of this script.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Install all mise tools + apply stow/fonts/dconf.
./sync.sh

# Decrypt the age key (prompts for the passphrase). Skip with SKIP_SECRETS=1.
# `age` is provided by mise (it's in mise.toml), available after sync.sh.
if [ "${SKIP_SECRETS:-0}" != 1 ] && [ -f ./setup/age-key.age ]; then
    echo "Decrypting age key (passage identity)..."
    mkdir -p ~/.local/share/age
    mise exec -- age -d ./setup/age-key.age >~/.local/share/age/key.txt
    chmod 600 ~/.local/share/age/key.txt
    mkdir -p ~/.passage
    cp ~/.local/share/age/key.txt ~/.passage/identities
fi

cat <<'EOF'

==> setup complete.

If your shell rc still puts ~/.pixi/bin on PATH, replace that with mise:

    # ~/.zshrc / ~/.bashrc
    eval "$(mise activate zsh)"     # or 'mise activate bash'
    # fish: ~/.config/fish/config.fish
    #   mise activate fish | source

Then restart your shell. `mise ls` / `mise doctor` show the active toolset.
EOF
