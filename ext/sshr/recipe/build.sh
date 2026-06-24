#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# --no-track keeps cargo's bookkeeping files (.crates.toml, ...) out of $PREFIX.
cargo install --locked --no-track --root "$PREFIX" --path .

# Auxiliary data files sshr looks for under share/sshr/, if present in the repo.
mkdir -p "$PREFIX/share/sshr"
# kitty integration scripts
if [ -d kitty ]; then
    mkdir -p "$PREFIX/share/sshr/kitty"
    cp kitty/*.py "$PREFIX/share/sshr/kitty/" 2>/dev/null || true
fi
# shpool: the build script + prebuilt remote binaries (bin/) that sshr uploads
# to remotes. Without these, `sshr <host>` errors with "no shpool binaries found".
if [ -d shpool ]; then
    cp -R shpool "$PREFIX/share/sshr/shpool"
fi
