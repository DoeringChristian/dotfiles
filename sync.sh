#!/usr/bin/env bash
# sync.sh — reconcile this machine with the repo: install any MISSING packages
# (`brew bundle`) and re-apply configs (stow). No first-time steps — no Homebrew
# install, no secret decryption. Run this after adding a tool to the Brewfile or a
# config to common/. (setup.sh calls this; on its own it needs brew already present.)
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
OS="$(uname -s)"
TAP="doeringc/local"

# --type <profile> layers Brewfile.<profile> (e.g. workstation) on top of the base
# Brewfile. The choice is saved to dotfiles.lock (per-machine, gitignored) so a bare
# `./sync.sh` / `./update.sh` reuses it. Precedence: --type arg > dotfiles.lock > base.
LOCK="$REPO/dotfiles.lock"
lock_get() {
    [ -f "$LOCK" ] || return 0
    sed -n "s/^$1=//p" "$LOCK" | tail -1
}
lock_set() {
    local t
    t="$(mktemp)"
    { [ -f "$LOCK" ] && grep -vE "^$1=" "$LOCK" >"$t"; } 2>/dev/null || true
    echo "$1=$2" >>"$t"
    mv "$t" "$LOCK"
}

TYPE_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
    --type)
        TYPE_ARG="${2:?--type needs a value}"
        shift 2
        ;;
    --type=*)
        TYPE_ARG="${1#*=}"
        shift
        ;;
    *)
        echo "sync.sh: unknown argument '$1'" >&2
        exit 2
        ;;
    esac
done
if [ -n "$TYPE_ARG" ]; then
    TYPE="$TYPE_ARG"
    lock_set type "$TYPE" # explicit choice -> remember it
else
    TYPE="$(lock_get type)"
    TYPE="${TYPE:-base}"
fi # else the saved one, or base

# brew on PATH (standard prefixes + rootless ~/.homebrew)
for p in "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && {
        eval "$("$p" shellenv)"
        break
    }
done
command -v brew >/dev/null 2>&1 || {
    echo "brew not found — run ./setup.sh first"
    exit 1
}

# npm uses `#!/usr/bin/env node`. Ensure Homebrew's Node is installed and first
# on PATH before brew bundle handles npm entries; otherwise an older distro Node
# (for example Ubuntu's /usr/bin/node) may execute Homebrew's modern npm.
brew list --versions node >/dev/null 2>&1 || brew install node
NODE_PREFIX="$(brew --prefix node)"
export PATH="$NODE_PREFIX/bin:$PATH"
hash -r
node -e "require('node:path')" >/dev/null 2>&1 || {
    echo "Homebrew Node is not active (found $(command -v node), $(node --version 2>/dev/null || echo unknown))" >&2
    exit 1
}

# Homebrew Bundle discovers npm separately, then npm's env-based shebang can pick
# an old distro Node from Bundle's sanitized PATH. Put a temporary npm wrapper at
# the front of the PATH Bundle captures; it still uses the npm declarations in
# the Brewfile, but pins their execution to Homebrew's Node and npm.
NPM_WRAPPER_DIR="$(mktemp -d)"
cleanup_npm_wrapper() { rm -rf "$NPM_WRAPPER_DIR"; }
trap cleanup_npm_wrapper EXIT
cat >"$NPM_WRAPPER_DIR/npm" <<EOF_NPM
#!/bin/sh
exec "$NODE_PREFIX/bin/node" "$NODE_PREFIX/bin/npm" "\$@"
EOF_NPM
chmod +x "$NPM_WRAPPER_DIR/npm"
export PATH="$NPM_WRAPPER_DIR:$PATH"
hash -r

# HEAD builds can otherwise exhaust memory by compiling once per CPU core on
# Linux servers. Callers can still override this (for example, set it to 8).
if [ "$OS" = Linux ]; then
    export HOMEBREW_MAKE_JOBS="${HOMEBREW_MAKE_JOBS:-2}"
fi

# Custom-formula tap (neovim, sshr, passage) must be registered + trusted for brew bundle.
brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
cp -f "$REPO/Formula/"*.rb "$(brew --repo "$TAP")/Formula/" 2>/dev/null || true
brew trust "$TAP" >/dev/null 2>&1 || true

# One-time migration from homebrew/core/neovim to the local HEAD formula. The
# formula names conflict, so remove the core installation before Bundle installs
# the tap-qualified replacement.
if brew list --formula --full-name | grep -Eq '^(homebrew/core/)?neovim$'; then
    echo "==> replacing homebrew/core/neovim with $TAP/neovim"
    brew uninstall --ignore-dependencies neovim
fi

echo "==> brew bundle (base)"
brew bundle --file "$REPO/Brewfile"
if [ "$TYPE" != base ]; then
    [ -f "$REPO/Brewfile.$TYPE" ] || {
        echo "no Brewfile.$TYPE (available: $(ls Brewfile.* 2>/dev/null | sed 's/Brewfile\.//' | tr '\n' ' '))" >&2
        exit 1
    }
    echo "==> brew bundle (profile: $TYPE)"
    brew bundle --file "$REPO/Brewfile.$TYPE"
fi

# Bundle is finished; remove the compatibility wrapper now rather than at exit.
export PATH="${PATH#"$NPM_WRAPPER_DIR:"}"
cleanup_npm_wrapper
trap - EXIT
hash -r

# Linux: kitty's cask installs the binary but not a GNOME .desktop, so make one.
if [ "$OS" != Darwin ] && command -v kitty >/dev/null 2>&1; then
    kbin="$(command -v kitty)"
    mkdir -p ~/.local/share/applications
    cat >~/.local/share/applications/kitty.desktop <<EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=kitty
GenericName=Terminal emulator
Comment=Fast, feature-rich, GPU-based terminal
Exec=$kbin
TryExec=$kbin
Icon=kitty
Categories=System;TerminalEmulator;
EOF_DESKTOP
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
fi

# Configs via GNU Stow.
echo "==> stow configs"
[ -d stow ] && stow -t ~ stow
[ -d common ] && stow -t ~ common
if [ "$OS" = Darwin ] && [ -d darwin ]; then
    stow -t ~ darwin
    mkdir -p ~/Library/Fonts && cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    plist=~/Library/LaunchAgents/com.ollama.server.plist
    [ -e "$plist" ] && launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
fi
[ "$OS" = Linux ] && [ -f dconf.ini ] && dconf load / <dconf.ini 2>/dev/null || true
echo "==> synced."
