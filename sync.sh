#!/usr/bin/env bash
# sync.sh — reconcile the machine to the repo (mise edition). Drop-in for the
# pixi sync.sh: the tool layer is now mise (the whole toolset lives in mise.toml,
# no brew/apt) instead of `pixi global sync`; the stow / Git-LFS / fonts / dconf
# steps are unchanged and only run when their inputs are present.
set -e

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"
OS="$(uname -s)"
PROFILE="${MISE_ENV:-base}"

# mise + its shims on PATH even when run directly (not via a mise-activated shell).
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export npm_config_cache="${npm_config_cache:-$HOME/.cache/npm}"   # avoid a root-owned ~/.npm

mkdir -p ~/.config ~/.local/bin ~/.ssh

# npm backend health: claude-code / gemini-cli need a user-owned npm cache.
if [ -d "$HOME/.npm" ] && find "$HOME/.npm" -user root -print -quit 2>/dev/null | grep -q .; then
    echo "!! ~/.npm has root-owned files; npm-backed tools may fail."
    echo "   Fix: sudo chown -R \"\$(id -u):\$(id -g)\" \"$HOME/.npm\""
fi

# 1. Tools via mise (the pixi-global replacement). Link the in-repo backend
#    (app:), trust the config, then install everything mise.toml + the active
#    profile declare. mise.lock keeps it reproducible.
echo "==> Installing tools with mise (profile=$PROFILE):"
mise trust "$PROJECT_DIR" >/dev/null 2>&1 || true
bash "$PROJECT_DIR/scripts/link-plugins.sh"
[ "$PROFILE" != base ] && export MISE_ENV="$PROFILE"

# Make this repo's mise config the GLOBAL config so its tools are on PATH
# EVERYWHERE (like the old `pixi global` -> ~/.pixi/bin), not just inside this
# repo. Direct analog of the old pixi sync symlinking the manifest into
# ~/.pixi/manifests/. (One tool list for every machine; Linux-only tools are
# os-gated inside mise.toml.)
MISE_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
mkdir -p "$MISE_CFG"
ln -sfn "$PROJECT_DIR/mise.toml" "$MISE_CFG/config.toml"
mise trust "$MISE_CFG/config.toml" >/dev/null 2>&1 || true

mise install

# (No native package layer — everything, incl. system CLIs / GUI apps / from-
# source tools / Linux GPU extras, is a mise tool in mise.toml.)

# claude-code finalizes its native binary in a postinstall (install.cjs), but
# mise's npm backend installs with --ignore-scripts so that step is skipped ->
# `claude` errors with "native binary not installed". Run it ourselves. Guarded
# by a working `claude`, so it's a no-op unless a fresh install / upgrade broke
# it. (gemini-cli is pure JS and needs nothing.)
if ! claude --version >/dev/null 2>&1; then
    cc="$HOME/.local/share/mise/installs/npm-anthropic-ai-claude-code/latest/lib/node_modules/@anthropic-ai/claude-code"
    if [ -f "$cc/install.cjs" ]; then
        echo "==> finalizing claude-code native binary (postinstall)"
        ( cd "$cc" && node install.cjs ) >/dev/null 2>&1 || true
    fi
fi

# 2. Git LFS payloads (fonts, .local/bin binaries) — git-lfs comes from mise.
git lfs install --local >/dev/null 2>&1 || true
git lfs pull 2>/dev/null || true

# 3. Stow configs — stow itself is a mise tool (src:stow), on PATH after install.
if command -v stow >/dev/null 2>&1 && [ -d stow ]; then
    echo "==> Applying configs with GNU Stow:"
    stow -t ~ stow                       # global ignore rules first
    [ -d common ] && stow -t ~ common
    if [ "$OS" = Darwin ] && [ -d darwin ]; then
        stow -t ~ darwin
        # macOS CoreText ignores symlinked fonts -> copy real files.
        mkdir -p ~/Library/Fonts
        cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    fi
fi

# GUI apps (kitty, tev): their .app/.desktop launchers are created by the `app:`
# mise backend during `mise install` (above), so no install/*.sh loop is needed.

# 4. dconf (Linux/GNOME only).
if [ "$OS" = Linux ] && [ -f dconf.ini ]; then
    echo "==> Loading dconf:"
    dconf load / <dconf.ini 2>/dev/null \
        || echo "   Warning: dconf load failed (likely a server). Skipping."
fi

echo "==> sync complete (profile=$PROFILE)."
