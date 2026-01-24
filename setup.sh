#!/usr/bin/env bash
set -e

# Goto the directory this executable is located in
PROJECT_DIR=$(dirname "$(realpath $0)")
cd $PROJECT_DIR

# TODO: figure out if we want to hard-code nix install?

# Decrypt the age key
mkdir -p ~/.local/share/age
age -d ./setup/age-key.age >~/.local/share/age/key.txt
chmod 600 ~/.local/share/age/key.txt

# Copy over to passage
mkdir -p ~/.passage
cp ~/.local/share/age/key.txt ~/.passage/identities

./sync.sh
