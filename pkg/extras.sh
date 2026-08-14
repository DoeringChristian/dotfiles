#!/usr/bin/env bash
# extras.sh — the handful of tools the package manager (brew / conda-forge) does
# not carry, installed rootless into ~/.local. Called by install.sh; OS is passed
# in via $OS (falls back to uname). Each installer is guarded and non-fatal so one
# failure doesn't abort the rest.
#
#   both platforms : sshr (cargo build), passage (from source)
#   Linux only     : kitty, tev, claude (the macOS casks' equivalents), gemini-cli
#   macOS only     : claude-agent-acp (conda-forge only -> via pixi)
set -uo pipefail

OS="${OS:-$(uname -s)}"
PREFIX="$HOME/.local"
mkdir -p "$PREFIX/bin" "$PREFIX/share"

have() { command -v "$1" >/dev/null 2>&1; }
say()  { echo "   [extras] $*"; }

# --------------------------------------------------------------- sshr (both)
# Rust SSH wrapper (github.com/DoeringChristian/sshr). Also ships share/sshr data
# (shpool + kitty kittens), which sshr finds by walking up from its binary.
install_sshr() {
    have cargo || { say "cargo missing (install rust) — skipping sshr"; return; }
    local tmp; tmp="$(mktemp -d)"
    if git clone --depth 1 https://github.com/DoeringChristian/sshr "$tmp/sshr" 2>/dev/null; then
        ( cd "$tmp/sshr" && cargo install --path . --root "$PREFIX" ) \
            && say "sshr installed"
        # copy the data dir sshr expects next to its binary (best-effort)
        [ -d "$tmp/sshr/share/sshr" ] && cp -R "$tmp/sshr/share/sshr" "$PREFIX/share/" \
            && say "sshr share/ data installed"
    else
        say "could not clone sshr — skipping"
    fi
    rm -rf "$tmp"
}

# --------------------------------------------------------------- passage (both)
# Age-backed password store (github.com/FiloSottile/passage). Shell script; needs
# `age` (from brew/conda) and `make`.
install_passage() {
    have age  || { say "age missing — skipping passage"; return; }
    have make || { say "make missing — skipping passage"; return; }
    local tmp; tmp="$(mktemp -d)"
    if git clone --depth 1 https://github.com/FiloSottile/passage "$tmp/passage" 2>/dev/null; then
        make -C "$tmp/passage" install PREFIX="$PREFIX" >/dev/null 2>&1 \
            && say "passage installed" || say "passage make install failed"
    else
        say "could not clone passage — skipping"
    fi
    rm -rf "$tmp"
}

# --------------------------------------------------------------- Linux GUI + CLIs
# On macOS these come from casks (see Brewfile); on Linux we fetch official builds.

install_kitty_linux() {
    say "installing kitty (official binary -> ~/.local/kitty.app)"
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh \
        | sh /dev/stdin launch=n dest="$PREFIX" 2>/dev/null || { say "kitty install failed"; return; }
    ln -sfn "$PREFIX/kitty.app/bin/kitty"  "$PREFIX/bin/kitty"
    ln -sfn "$PREFIX/kitty.app/bin/kitten" "$PREFIX/bin/kitten"
    # desktop integration (kitty ships the .desktop + icon)
    mkdir -p "$PREFIX/share/applications" "$PREFIX/share/icons/hicolor/256x256/apps"
    cp -f "$PREFIX/kitty.app/share/applications/kitty.desktop" "$PREFIX/share/applications/" 2>/dev/null || true
    sed -i "s|Icon=kitty|Icon=$PREFIX/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|;s|Exec=kitty|Exec=$PREFIX/bin/kitty|" \
        "$PREFIX/share/applications/kitty.desktop" 2>/dev/null || true
    say "kitty installed"
}

install_tev_linux() {
    say "installing tev (latest Linux release binary)"
    local url
    url="$(curl -fsSL https://api.github.com/repos/Tom94/tev/releases/latest \
        | grep -oE '"browser_download_url": *"[^"]*[Ll]inux[^"]*"' | head -1 | cut -d'"' -f4)"
    [ -n "$url" ] || { say "no Linux tev asset found — skipping"; return; }
    curl -fsSL "$url" -o "$PREFIX/bin/tev" && chmod +x "$PREFIX/bin/tev" && say "tev installed" \
        || say "tev download failed"
}

install_claude_linux() {
    say "installing claude (official installer -> ~/.local/bin/claude)"
    # NOTE: confirm the current official installer URL; this is the documented one.
    curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 \
        && say "claude installed" || say "claude install failed (check installer URL)"
}

install_gemini_linux() {
    have npm || { say "npm missing (from nodejs) — skipping gemini-cli"; return; }
    npm install -g @google/gemini-cli >/dev/null 2>&1 && say "gemini-cli installed" \
        || say "gemini-cli install failed"
}

# --------------------------------------------------------------- macOS-only
install_claude_agent_acp_mac() {
    # Not in brew; conda-forge has it. Use pixi if available.
    if have pixi; then
        pixi global install claude-agent-acp >/dev/null 2>&1 && say "claude-agent-acp installed (pixi)" \
            || say "claude-agent-acp via pixi failed"
    else
        say "claude-agent-acp: install pixi, then 'pixi global install claude-agent-acp'"
    fi
}

# ------------------------------------------------------------------- dispatch
install_sshr
install_passage
if [ "$OS" = Darwin ]; then
    install_claude_agent_acp_mac
else
    install_kitty_linux
    install_tev_linux
    install_claude_linux
    install_gemini_linux
fi

echo "   [extras] done."
