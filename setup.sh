#!/usr/bin/env bash
set -e

# Goto the directory this executable is located in
PROJECT_DIR=$(dirname "$(realpath "$0")")
cd "$PROJECT_DIR"

# Install Homebrew if not already installed
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for the rest of this script
    if [[ "$(uname)" == "Darwin" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
fi

# Sync packages, configs, etc.
./sync.sh

# Decrypt the age key (age is now installed via brew)
mkdir -p ~/.local/share/age
age -d ./setup/age-key.age >~/.local/share/age/key.txt
chmod 600 ~/.local/share/age/key.txt

# Copy over to passage
mkdir -p ~/.passage
cp ~/.local/share/age/key.txt ~/.passage/identities
