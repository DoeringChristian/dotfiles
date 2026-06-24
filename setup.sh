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

# rattler-build powers our custom pixi-build-npm backend (gemini-cli, claude-code)
if ! command -v rattler-build &>/dev/null; then
    echo "Installing rattler-build (build backend dependency)..."
    pixi global install rattler-build
fi

# Install packages (including age) before trying to use age
./sync.sh

# Decrypt the age key. sync.sh installed `age` via pixi global into ~/.pixi/bin,
# which is on this script's PATH (set above).
AGE="$HOME/.pixi/bin/age"
mkdir -p ~/.local/share/age
"$AGE" -d ./setup/age-key.age >~/.local/share/age/key.txt
chmod 600 ~/.local/share/age/key.txt

# Copy over to passage
mkdir -p ~/.passage
cp ~/.local/share/age/key.txt ~/.passage/identities
