#!/usr/bin/env bash
# sync.sh — reconcile this machine with the repo: install any MISSING packages
# (`brew bundle`) and re-apply configs (stow). No first-time steps — no Homebrew
# install, no secret decryption. Run this after adding a tool to the Brewfile or a
# config to common/. (setup.sh calls this; on its own it needs brew already present.)
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
OS="$(uname -s)"; TAP="doeringc/local"

# brew on PATH (standard prefixes + rootless ~/.homebrew)
for p in "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && { eval "$("$p" shellenv)"; break; }
done
command -v brew >/dev/null 2>&1 || { echo "brew not found — run ./setup.sh first"; exit 1; }

# Custom-formula tap (sshr, passage) must be registered + trusted for brew bundle.
brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
cp -f "$REPO/Formula/"*.rb "$(brew --repo "$TAP")/Formula/" 2>/dev/null || true
brew trust "$TAP" >/dev/null 2>&1 || true

echo "==> brew bundle (install anything missing)"
brew bundle --file "$REPO/Brewfile"

# Linux: kitty's cask installs the binary but not a GNOME .desktop, so make one.
if [ "$OS" != Darwin ] && command -v kitty >/dev/null 2>&1; then
    kbin="$(command -v kitty)"; mkdir -p ~/.local/share/applications
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

# Configs via GNU Stow.
echo "==> stow configs"
[ -d stow ]   && stow -t ~ stow
[ -d common ] && stow -t ~ common
if [ "$OS" = Darwin ] && [ -d darwin ]; then
    stow -t ~ darwin
    mkdir -p ~/Library/Fonts && cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    plist=~/Library/LaunchAgents/com.ollama.server.plist
    [ -e "$plist" ] && launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
fi
[ "$OS" = Linux ] && [ -f dconf.ini ] && dconf load / <dconf.ini 2>/dev/null || true
echo "==> synced."
