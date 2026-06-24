#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

OS="$(uname -s)"

# pixi-installed tools (stow, git-lfs, ...) live here; ensure they're findable even
# when this script is run directly (not via the login shell / setup.sh).
export PATH="$HOME/.pixi/bin:$PATH"

mkdir -p ~/.config
mkdir -p ~/.local/bin
mkdir -p ~/.ssh

# Install the toolset globally with `pixi global` so binaries land in ~/.pixi/bin
# (already on PATH) and GUI apps get menuinst shortcuts (~/Applications on macOS,
# .desktop on Linux). The committed pixi-global.toml (repo root) is the source of
# truth: we symlink it where pixi global looks, then sync. It MUST live at the
# root so its `ext/<name>` path-deps resolve (pixi follows the symlink to the
# real file and resolves relative to it). Override the manifest with
# $PIXI_GLOBAL_MANIFEST (used by the docker tests for a fast, minimal run).
echo "Installing tools with pixi global:"
mkdir -p ~/.pixi/manifests
ln -sfn "${PIXI_GLOBAL_MANIFEST:-$PROJECT_DIR/pixi-global.toml}" ~/.pixi/manifests/pixi-global.toml
pixi global sync

# Fetch Git LFS payloads (fonts, .local/bin binaries) now that pixi installed
# git-lfs. A non-LFS or already-pulled checkout is a no-op. Without this, a fresh
# clone leaves those files as small pointer text files.
git lfs install --local >/dev/null 2>&1 || true
git lfs pull 2>/dev/null || true

# This stow comes before the others to ensure global ignore list is respected before other stow commands
echo "Applying configs with GNU Stow:"
stow -t ~ stow
stow -t ~ common

if [ "$OS" = "Darwin" ]; then
    stow -t ~ darwin
    # Fonts: macOS CoreText ignores symlinked fonts, so install REAL copies into
    # ~/Library/Fonts. (On Linux the stow-linked ~/.local/share/fonts works, since
    # fontconfig follows symlinks.)
    mkdir -p ~/Library/Fonts
    cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
fi
# GUI apps (kitty, tev) are exposed by pixi global via menuinst shortcuts
# (~/Applications/*.app on macOS, ~/.local/share/applications/*.desktop on Linux),
# so no manual app linking is needed here.

# Run install scripts for GUI applications (skip already-installed apps unless UPDATE=1)
echo "Running install scripts:"
for script in "$PROJECT_DIR"/install/*.sh; do
    [ -x "$script" ] || continue
    name="$(basename "$script" .sh)"
    installed=false
    if command -v "$name" >/dev/null 2>&1 \
        || [ -d "$HOME/Applications/$name.app" ] \
        || [ -d "/Applications/$name.app" ]; then
        installed=true
    fi
    if [ "${UPDATE:-0}" != "1" ] && [ "$installed" = true ]; then
        echo "Skipping $name (already installed)"
        continue
    fi
    bash "$script"
done

# Load dconf (Linux/GNOME only)
if [ "$OS" = "Linux" ]; then
    echo "Loading dconf:"
    if ! dconf load / <dconf.ini 2>/dev/null; then
        echo "Warning: dconf load failed (likely running on a server). Skipping."
    fi
fi
