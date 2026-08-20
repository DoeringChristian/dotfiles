#!/usr/bin/env bash
# install.sh — install the whole toolset (pkg/packages) at LATEST via Homebrew,
# per each tool's declared method, plus a local tap for the custom formulae.
#
# SAFE alongside mise: everything lands in the Homebrew prefix + ~/.local. It does
# NOT touch ~/.local/share/mise or any PATH file, so your current setup keeps
# working. Whether the brew tools "win" depends only on PATH order — flip that
# yourself once you've verified (see pkg/README.md). Nothing is removed.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
OS="$(uname -s)"
MANIFEST="$DIR/packages"
TAP="local/dotfiles"
PREFIX="$HOME/.local"; mkdir -p "$PREFIX/bin" "$PREFIX/share"

have() { command -v "$1" >/dev/null 2>&1; }
opt()  { printf '%s\n' "$1" | grep -oE "$2=[^ ]+" | head -1 | cut -d= -f2-; }

# ---------------------------------------------------------- ensure Homebrew
if ! have brew; then
    echo "==> installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
done

# ---------------------------------------------------------- parse the manifest
PKG=(); PKG_HEAD=(); CASK_LINES=(); FORMULA=(); OTHER_LINES=()
while read -r name method rest || [ -n "${name:-}" ]; do
    case "${name:-}" in ''|\#*) continue ;; esac
    rest="${rest%%#*}"
    case "$method" in
        pkg)     if [ "$(opt "$rest" head)" = true ]; then PKG_HEAD+=("$name"); else PKG+=("$name"); fi ;;
        cask)    CASK_LINES+=("$name|$rest") ;;
        formula) FORMULA+=("$name") ;;
        *)       OTHER_LINES+=("$name|$method|$rest") ;;
    esac
done < "$MANIFEST"

# ---------------------------------------------------------- brew formulae
echo "==> brew install (${#PKG[@]} bottled tools)"
brew install ${PKG[@]+"${PKG[@]}"}
for h in ${PKG_HEAD[@]+"${PKG_HEAD[@]}"}; do
    echo "==> brew install --HEAD $h"; brew install --HEAD "$h"
done

# ---------------------------------------------------------- custom formulae (tap)
if [ "${#FORMULA[@]}" -gt 0 ]; then
    echo "==> local tap $TAP (custom formulae)"
    brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
    cp -f "$DIR/Formula/"*.rb "$(brew --repo "$TAP")/Formula/" 2>/dev/null || true
    for f in "${FORMULA[@]}"; do echo "==> brew install --HEAD $TAP/$f"; brew install --HEAD "$TAP/$f"; done
fi

# ---------------------------------------------------------- GUI apps
# macOS: brew casks. Linux: Homebrew has no cask support, so fetch official builds.
install_app_linux() {
    local n="$1" repo="$2"
    case "$n" in
        kitty)
            curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh \
                | sh /dev/stdin launch=n dest="$PREFIX" 2>/dev/null || { echo "!! kitty failed"; return; }
            ln -sfn "$PREFIX/kitty.app/bin/kitty"  "$PREFIX/bin/kitty"
            ln -sfn "$PREFIX/kitty.app/bin/kitten" "$PREFIX/bin/kitten" ;;
        claude)
            # Homebrew has no casks on Linux; use the official installer -> ~/.local/bin.
            curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
                && echo "   claude installed" || echo "!! claude installer failed" ;;
        *)
            local url
            url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
                | grep -oE '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
                | grep -iE 'linux' | grep -iE 'x86_64|amd64|x64' \
                | grep -viE '\.(sha256|asc|sig)"?$' | head -1)"
            [ -n "$url" ] || { echo "!! no Linux asset for $n"; return; }
            curl -fsSL "$url" -o "$PREFIX/bin/$n" && chmod +x "$PREFIX/bin/$n" ;;
    esac
}
for line in ${CASK_LINES[@]+"${CASK_LINES[@]}"}; do
    n="${line%%|*}"; rest="${line#*|}"
    token="$(opt "$rest" cask)"; token="${token:-$n}"   # cask token may differ from tool name
    if [ "$OS" = Darwin ]; then echo "==> $n (cask $token)"; brew install --cask "$token"
    else echo "==> $n (Linux official build)"; install_app_linux "$n" "$(opt "$rest" github)"; fi
done

# ---------------------------------------------------------- npm / self / uv
for line in ${OTHER_LINES[@]+"${OTHER_LINES[@]}"}; do
    n="${line%%|*}"; r="${line#*|}"; method="${r%%|*}"; rest="${r#*|}"
    case "$method" in
        self) url="$(opt "$rest" url)"; echo "==> $n (self-installer, self-updating)"; curl -fsSL "$url" | bash || echo "!! $n installer failed" ;;
        npm)  have npm && { p="$(opt "$rest" pkg)"; echo "==> $n (npm)"; npm install -g "${p:-$n}@latest"; } || echo "!! $n: npm missing" ;;
        uv)   have uv  && { echo "==> $n (uv)"; uv tool install "$n"; } || echo "!! $n: uv missing" ;;
    esac
done

# ---------------------------------------------------------- configs (stow)
if have stow; then
    echo "==> stow configs"; cd "$REPO"
    [ -d stow ] && stow -t ~ stow
    [ -d common ] && stow -t ~ common
    if [ "$OS" = Darwin ] && [ -d darwin ]; then
        stow -t ~ darwin
        mkdir -p ~/Library/Fonts && cp -f common/.local/share/fonts/*.ttf ~/Library/Fonts/ 2>/dev/null || true
    fi
fi

echo
echo "==> done (all at latest via brew + ~/.local). mise was NOT touched."
echo "   To switch to it, put \$(brew --prefix)/bin and ~/.local/bin ahead of the"
echo "   mise shims on PATH, restart your shell, and verify. Remove mise only after."
