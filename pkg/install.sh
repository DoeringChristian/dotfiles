#!/usr/bin/env bash
# install.sh — install the whole toolset (pkg/packages) at LATEST, rootless, per
# each tool's declared method. Safe alongside mise: installs into the package
# manager's prefix + ~/.local, never touches ~/.local/share/mise or PATH files.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
OS="$(uname -s)"
MANIFEST="$DIR/packages"
PREFIX="$HOME/.local"; mkdir -p "$PREFIX/bin" "$PREFIX/share"

have() { command -v "$1" >/dev/null 2>&1; }
opt()  { printf '%s\n' "$1" | grep -oE "$2=[^ ]+" | head -1 | cut -d= -f2-; }  # opt "$rest" conda

# ---------------------------------------------------------- package managers
if [ "$OS" = Darwin ]; then
    have brew || NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
else
    if ! have pixi && [ ! -x "$HOME/.pixi/bin/pixi" ]; then
        curl -fsSL https://pixi.sh/install.sh | bash
    fi
    export PATH="$HOME/.pixi/bin:$PATH"
fi

# ---------------------------------------------------------- parse the manifest
PKG_NAMES=(); CASK_LINES=(); CONDA_NAMES=(); OTHER_LINES=()
while read -r name method rest || [ -n "${name:-}" ]; do
    case "${name:-}" in ''|\#*) continue ;; esac
    rest="${rest%%#*}"
    case "$method" in
        pkg)
            if [ "$OS" = Darwin ]; then PKG_NAMES+=("$name")
            else c="$(opt "$rest" conda)"; PKG_NAMES+=("${c:-$name}"); fi ;;
        cask)  CASK_LINES+=("$name|$rest") ;;
        conda) CONDA_NAMES+=("$name") ;;
        *)     OTHER_LINES+=("$name|$method|$rest") ;;
    esac
done < "$MANIFEST"

# ---------------------------------------------------------- pkg tools first
# (they provide node/uv/cargo/make/git that the other methods need)
echo "==> package manager: installing ${#PKG_NAMES[@]} tools at latest"
if [ "$OS" = Darwin ]; then
    brew install ${PKG_NAMES[@]+"${PKG_NAMES[@]}"}
else
    pixi global install ${PKG_NAMES[@]+"${PKG_NAMES[@]}"}
fi
if [ "${#CONDA_NAMES[@]}" -gt 0 ]; then
    if have pixi; then
        echo "==> conda-forge (pixi): ${CONDA_NAMES[*]}"
        pixi global install "${CONDA_NAMES[@]}"
    else
        echo "!! pixi not found — skipping conda tools: ${CONDA_NAMES[*]}"
    fi
fi

# ---------------------------------------------------------- source builds
install_source() {
    local n="$1" url="$2" build="$3" tmp; tmp="$(mktemp -d)"
    echo "==> $n (source: $build)"
    if ! git clone --depth 1 "$url" "$tmp/$n" 2>/dev/null; then echo "!! clone $n failed"; rm -rf "$tmp"; return; fi
    case "$build" in
        cargo) have cargo && ( cd "$tmp/$n" && cargo install --path . --root "$PREFIX" ) || echo "!! $n: cargo missing/failed"
               [ -d "$tmp/$n/share" ] && cp -R "$tmp/$n/share/." "$PREFIX/share/" 2>/dev/null || true ;;
        make)  have make && make -C "$tmp/$n" install PREFIX="$PREFIX" >/dev/null 2>&1 || echo "!! $n: make missing/failed" ;;
        *)     echo "!! $n: unknown build '$build'" ;;
    esac
    rm -rf "$tmp"
}

# ---------------------------------------------------------- Linux GUI/app fetch
# On macOS these are casks; on Linux fetch the latest official build. Kept simple;
# verify on a real server. (kitty has its own installer; others: latest release.)
install_app_linux() {
    local n="$1" repo="$2"
    case "$n" in
        kitty)
            echo "==> kitty (official installer)"
            curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh \
                | sh /dev/stdin launch=n dest="$PREFIX" 2>/dev/null || { echo "!! kitty failed"; return; }
            ln -sfn "$PREFIX/kitty.app/bin/kitty"  "$PREFIX/bin/kitty"
            ln -sfn "$PREFIX/kitty.app/bin/kitten" "$PREFIX/bin/kitten" ;;
        *)
            echo "==> $n (latest release from $repo)"
            local url
            url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
                | grep -oE '"browser_download_url": *"[^"]*(inux|x86_64|amd64)[^"]*"' \
                | grep -viE '\.(sha256|asc|sig)"' | head -1 | cut -d'"' -f4)"
            [ -n "$url" ] || { echo "!! no Linux asset for $n"; return; }
            case "$url" in
                *.txz|*.tar.xz|*.tar.gz|*.tgz|*.tar.zst)
                    local d="$PREFIX/opt/$n"; mkdir -p "$d"
                    curl -fsSL "$url" | tar x -C "$d" 2>/dev/null
                    find "$d" -maxdepth 3 -type f -name "$n" -perm -u+x -exec ln -sfn {} "$PREFIX/bin/$n" \; 2>/dev/null ;;
                *)  curl -fsSL "$url" -o "$PREFIX/bin/$n" && chmod +x "$PREFIX/bin/$n" ;;
            esac ;;
    esac
}

# ---------------------------------------------------------- casks / GUI apps
for line in ${CASK_LINES[@]+"${CASK_LINES[@]}"}; do
    n="${line%%|*}"; rest="${line#*|}"
    if [ "$OS" = Darwin ]; then echo "==> $n (cask)"; brew install --cask "$n"
    else install_app_linux "$n" "$(opt "$rest" github)"; fi
done

# ---------------------------------------------------------- self / npm / uv / source
for line in ${OTHER_LINES[@]+"${OTHER_LINES[@]}"}; do
    n="${line%%|*}"; r="${line#*|}"; method="${r%%|*}"; rest="${r#*|}"
    case "$method" in
        self)   url="$(opt "$rest" url)"; echo "==> $n (self-installer, self-updating)"; curl -fsSL "$url" | bash || echo "!! $n installer failed" ;;
        npm)    have npm && { p="$(opt "$rest" pkg)"; echo "==> $n (npm)"; npm install -g "${p:-$n}@latest"; } || echo "!! $n: npm missing" ;;
        uv)     have uv  && { echo "==> $n (uv)"; uv tool install "$n"; } || echo "!! $n: uv missing" ;;
        source) install_source "$n" "$(opt "$rest" url)" "$(opt "$rest" build)" ;;
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
echo "==> done (all at latest). Ensure PATH has:"
[ "$OS" = Darwin ] && echo "     \$(brew --prefix)/bin  and  ~/.local/bin" \
                   || echo "     ~/.pixi/bin  and  ~/.local/bin"
echo "   mise was NOT touched."
