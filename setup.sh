#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

OS="$(uname -s)"

# Install pixi if not present
if ! command -v pixi &>/dev/null; then
    echo "pixi not found. Installing..."
    curl -fsSL https://pixi.sh/install.sh | sh
fi
# Ensure pixi (and globally-installed tools) are on PATH for this script
export PATH="$HOME/.pixi/bin:$PATH"

# Install packages (including age) and apply configs.
./sync.sh

# Decrypt the age key (prompts for the passphrase). Skip with SKIP_SECRETS=1
# (e.g. in CI / the docker tests). `age` was installed into ~/.pixi/bin by sync.sh.
if [ "${SKIP_SECRETS:-0}" != 1 ]; then
    AGE="$HOME/.pixi/bin/age"
    mkdir -p ~/.local/share/age
    "$AGE" -d ./setup/age-key.age >~/.local/share/age/key.txt
    chmod 600 ~/.local/share/age/key.txt
    # Copy over to passage
    mkdir -p ~/.passage
    cp ~/.local/share/age/key.txt ~/.passage/identities
fi
