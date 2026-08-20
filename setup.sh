#!/usr/bin/env bash
# setup.sh — first-time setup (Homebrew edition). Installs the whole toolset from
# the Brewfile, applies configs with GNU Stow, and decrypts the age secret.
#
#   ./setup.sh                 # everything
#   SKIP_SECRETS=1 ./setup.sh  # skip the age key (CI / minimal)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
OS="$(uname -s)"
TAP="doeringc/local"
have() { command -v "$1" >/dev/null 2>&1; }

# 1. Homebrew.
#   Default: standard prefix (macOS is rootless; Linux /home/linuxbrew needs one
#   sudo prompt) — this gets prebuilt bottles.
#   Rootless option (no root at all, e.g. a locked-down server):
#       BREW_PREFIX="$HOME/.homebrew" ./setup.sh
#   installs Homebrew into your home dir with no sudo. CAVEAT: a non-standard prefix
#   has NO prebuilt bottles, so most formulae build from SOURCE (needs a compiler +
#   time). Use it only where you can't get the standard prefix.
BREW_PREFIX="${BREW_PREFIX:-}"
if ! have brew; then
    if [ -n "$BREW_PREFIX" ]; then
        echo "==> installing Homebrew (rootless) into $BREW_PREFIX"
        mkdir -p "$BREW_PREFIX"
        curl -fsSL https://github.com/Homebrew/brew/tarball/master \
            | tar xz --strip-components 1 -C "$BREW_PREFIX"
    else
        echo "==> installing Homebrew"
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi
for p in "${BREW_PREFIX:+$BREW_PREFIX/bin/brew}" \
         "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew \
         /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -n "$p" ] && [ -x "$p" ] && { eval "$("$p" shellenv)"; break; }
done
[ -n "$BREW_PREFIX" ] && brew update --force --quiet 2>/dev/null || true

# 2. Register + trust the in-repo tap for the custom formulae (sshr, passage).
#    Homebrew refuses to load formulae from an untrusted third-party tap.
brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
cp -f "$REPO/Formula/"*.rb "$(brew --repo "$TAP")/Formula/"
brew trust "$TAP" >/dev/null 2>&1 || true

# 3. Install everything in the Brewfile.
echo "==> brew bundle"
brew bundle --file "$REPO/Brewfile"

# 4. Linux: kitty/tev/claude installed as casks above (they ship Linux variations).
#    The kitty cask installs the binary but not a GNOME .desktop entry, so make one
#    pointing at the brew binary.
if [ "$OS" != Darwin ] && command -v kitty >/dev/null 2>&1; then
    kbin="$(command -v kitty)"
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/kitty.desktop <<EOF_DESKTOP
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

# 5. Configs via GNU Stow (stow itself came from brew above).
echo "==> stow configs"
[ -d stow ]   && stow -t ~ stow
[ -d common ] && stow -t ~ common
if [ "$OS" = Darwin ] && [ -d darwin ]; then
    stow -t ~ darwin
    mkdir -p ~/Library/Fonts && cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    # macOS LaunchAgents (e.g. the ollama server), if present.
    plist=~/Library/LaunchAgents/com.ollama.server.plist
    [ -e "$plist" ] && launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
fi
[ "$OS" = Linux ] && [ -f dconf.ini ] && dconf load / <dconf.ini 2>/dev/null || true

# 6. Secrets: decrypt the age key (age is a brew tool).
if [ "${SKIP_SECRETS:-0}" != 1 ] && [ -f ./setup/age-key.age ]; then
    echo "==> decrypting age key"
    mkdir -p ~/.local/share/age ~/.passage
    age -d ./setup/age-key.age > ~/.local/share/age/key.txt
    chmod 600 ~/.local/share/age/key.txt
    cp ~/.local/share/age/key.txt ~/.passage/identities
fi

cat <<'EOF'

==> setup complete. Everything is Homebrew (+ the sshr/passage tap formulae).
    Open a fresh terminal. Keep it current with ./update.sh.
EOF
