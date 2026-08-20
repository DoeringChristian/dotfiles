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

# 4. Linux GUI apps: Homebrew has no cask support on Linux, so fetch official builds.
if [ "$OS" != Darwin ]; then
    echo "==> Linux GUI apps (kitty / tev / claude)"
    PREFIX="$HOME/.local"; mkdir -p "$PREFIX/bin"
    if curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n dest="$PREFIX" 2>/dev/null; then
        ln -sfn "$PREFIX/kitty.app/bin/kitty"  "$PREFIX/bin/kitty"
        ln -sfn "$PREFIX/kitty.app/bin/kitten" "$PREFIX/bin/kitten"
        # Desktop integration so kitty shows up in the app launcher.
        mkdir -p "$PREFIX/share/applications"
        cp -f "$PREFIX/kitty.app/share/applications/"kitty*.desktop "$PREFIX/share/applications/" 2>/dev/null || true
        # Make Exec/TryExec/Icon absolute — GNOME hides an entry whose TryExec name
        # isn't on its (minimal) session PATH, and needs an absolute icon path.
        sed -i "s|Icon=kitty|Icon=$PREFIX/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g; \
                s|Exec=kitty|Exec=$PREFIX/bin/kitty|g; \
                s|TryExec=kitty|TryExec=$PREFIX/bin/kitty|g" \
            "$PREFIX/share/applications/"kitty*.desktop 2>/dev/null || true
        update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
    else echo "!! kitty failed"; fi
    turl="$(curl -fsSL https://api.github.com/repos/Tom94/tev/releases/latest \
        | grep -oE '"browser_download_url": *"[^"]*[Ll]inux[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -n "$turl" ] && curl -fsSL "$turl" -o "$PREFIX/bin/tev" && chmod +x "$PREFIX/bin/tev" || echo "!! tev skipped"
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || echo "!! claude failed"
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
