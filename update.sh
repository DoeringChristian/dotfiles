#!/usr/bin/env bash
# Update the pixi-managed toolset.
#
#   ./update.sh             Update conda-forge tools to their latest versions and
#                           refresh the moving-ref source builds (neovim nightly,
#                           sshr main). Then re-snapshot the manifest and sync.
#
#   ./update.sh <pkg>...    Rebuild specific ext/<pkg> package(s) -- run this after
#                           bumping a recipe's version (e.g. `./update.sh tev`).
#                           Moving-ref packages additionally get their caches
#                           busted so a fresh commit is actually fetched.
#
# Build times (cache-miss) are roughly: tev ~4 min, kitty/neovim ~45 s, sshr ~20 s,
# npm tools / stow / passage a few seconds.
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

ENV=dotfiles
# npm tools (gemini-cli, claude-code) build via the local custom backend.
export PIXI_BUILD_BACKEND_OVERRIDE="pixi-build-npm=$PROJECT_DIR/ext/pixi-build-npm/pixi-build-npm"

# Source packages that track a moving git ref. Their version string never changes,
# so the build hash stays the same and pixi would serve a stale cached build --
# these need a cache bust to pull fresh commits.
NIGHTLY=(neovim sshr)

# ext/<dir> -> conda package name (only neovim differs: dir "neovim", package "nvim").
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

rebuild() {  # $1 = ext dir name
    local dir="$1" pkg; pkg="$(pkg_name "$dir")"
    if is_nightly "$dir"; then
        echo "==> busting caches for $dir (moving git ref)"
        rm -rf "$CACHE/git-v0" "$CACHE/bld/bld/$pkg" "$CACHE"/pkgs/"$pkg"-* 2>/dev/null || true
    fi
    echo "==> rebuilding ext/$dir"
    pixi global install --force-reinstall --environment "$ENV" --path "ext/$dir"
}

if [ "$#" -gt 0 ]; then
    for p in "$@"; do rebuild "$p"; done
else
    echo "==> updating conda-forge tools to latest allowed versions"
    pixi global update "$ENV"
    echo "==> refreshing moving-ref source builds: ${NIGHTLY[*]}"
    for n in "${NIGHTLY[@]}"; do rebuild "$n"; done
fi

# Note: pixi-global.toml (repo root) is the source of truth and is symlinked into
# ~/.pixi/manifests by sync.sh -- nothing to snapshot back.

# Re-apply stow configs / fonts (picks up any newly added config files too).
echo "==> re-applying configs"
./sync.sh
