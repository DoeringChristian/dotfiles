#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

OS="$(uname -s)"

# Install Nix if not present
if ! command -v nix &>/dev/null; then
    echo "Nix not found. Installing via Determinate Systems installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    # Source nix for the current shell session
    if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fi
fi

# Install packages (including age) before trying to use age
./sync.sh

# Decrypt the age key (age is now available from nix)
mkdir -p ~/.local/share/age
age -d ./setup/age-key.age >~/.local/share/age/key.txt
chmod 600 ~/.local/share/age/key.txt

# Copy over to passage
mkdir -p ~/.passage
cp ~/.local/share/age/key.txt ~/.passage/identities
