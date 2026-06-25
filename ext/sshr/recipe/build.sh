#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# --no-track keeps cargo's bookkeeping files (.crates.toml, ...) out of $PREFIX.
# --force overwrites an existing binary: pixi global may re-run the build into a
# prefix that already holds sshr, and cargo otherwise aborts with
# "binary `sshr` already exists in destination".
cargo install --locked --no-track --force --root "$PREFIX" --path .

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
    # rm first so a re-run into a dirty prefix doesn't nest shpool/shpool.
    rm -rf "$PREFIX/share/sshr/shpool"
    cp -R shpool "$PREFIX/share/sshr/shpool"
fi
