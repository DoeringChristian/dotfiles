#!/usr/bin/env bash
# Update the pixi-managed toolset.
#
#   ./update.sh             Update conda-forge tools to their latest versions and
#                           refresh the moving-ref source builds (neovim nightly,
#                           sshr main), then sync.
#
#   ./update.sh <pkg>...    Rebuild specific ext/<pkg> package(s) -- run this after
#                           bumping a recipe's version (e.g. `./update.sh tev`).
#                           Moving-ref packages also get their git checkout cleared
#                           so a fresh commit is fetched.
#
# How it works: we only bust the relevant rattler caches here, then let `sync.sh`
# (which runs `pixi global sync`) do the actual rebuild. We never run
# `pixi global install` -- that rewrites the symlinked pixi-global.toml.
#
# Build times (cache-miss): tev ~4 min, kitty/neovim ~45 s, sshr ~20 s,
# npm tools / stow / passage a few seconds.
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

ENV=dotfiles

# Source packages tracking a moving git ref: their version string never changes,
# so the build hash is stable and pixi serves a stale cached build -- bust caches.
NIGHTLY=(neovim sshr)

# ext/<dir> -> conda package name (only neovim differs: dir "neovim", pkg "nvim").
pkg_name() { case "$1" in neovim) echo nvim ;; *) echo "$1" ;; esac; }

# rattler cache root (override with $RATTLER_CACHE_DIR).
rattler_cache() {
    if [ -n "${RATTLER_CACHE_DIR:-}" ]; then printf '%s\n' "$RATTLER_CACHE_DIR"; return; fi
    case "$(uname -s)" in
        Darwin) printf '%s\n' "$HOME/Library/Caches/rattler" ;;
        *)      printf '%s\n' "$HOME/.cache/rattler" ;;
    esac
}
CACHE="$(rattler_cache)/cache"

is_nightly() { local x; for x in "${NIGHTLY[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

bust_cache() {  # $1 = ext dir name -- clear caches so the next `sync` rebuilds it
    local dir="$1" pkg; pkg="$(pkg_name "$dir")"
    echo "==> busting build cache for $dir"
    rm -rf "$CACHE/bld/bld/$pkg" "$CACHE"/pkgs/"$pkg"-* 2>/dev/null || true
    is_nightly "$dir" && rm -rf "$CACHE/git-v0" 2>/dev/null || true
}

if [ "$#" -gt 0 ]; then
    for p in "$@"; do bust_cache "$p"; done
else
    echo "==> updating conda-forge tools to latest allowed versions"
    pixi global update "$ENV"
    echo "==> refreshing moving-ref source builds: ${NIGHTLY[*]}"
    for n in "${NIGHTLY[@]}"; do bust_cache "$n"; done
fi

# sync.sh runs `pixi global sync`, which rebuilds the cache-busted packages and
# re-applies stow configs / fonts.
echo "==> rebuilding (sync) + re-applying configs"
./sync.sh
