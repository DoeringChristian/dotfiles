#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# --no-track keeps cargo's bookkeeping files (.crates.toml, ...) out of $PREFIX.
cargo install --locked --no-track --root "$PREFIX" --path .

# Optional auxiliary data files for the kitty integration, if present in the
# repo. The core `sshr` CLI works without them.
if [ -d kitty ]; then
    mkdir -p "$PREFIX/share/sshr/kitty"
    cp kitty/*.py "$PREFIX/share/sshr/kitty/" 2>/dev/null || true
fi
