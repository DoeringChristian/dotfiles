#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# kitty's setup.py probes deps with pkg-config (harfbuzz, etc.) on both OSes.
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CFLAGS="${CFLAGS:-} -I ${PREFIX}/include/freetype2 -I ${PREFIX}/include/harfbuzz"

# Pre-seed the bundled NERD symbols font so setup.py's add_builtin_fonts()
# finds fonts/SymbolsNerdFontMono-Regular.ttf and skips its system-font search.
mkdir -p fonts
cp nerd-symbols/SymbolsNerdFontMono-Regular.ttf fonts/SymbolsNerdFontMono-Regular.ttf

# kitty's packaging step copies man/html docs and aborts if they're missing
# (they'd require the full sphinx doc toolchain to generate). We don't ship docs
# in this package, so create the expected dirs empty to satisfy the check --
# `kitty --help` still works; only `man kitty` is unavailable.
mkdir -p docs/_build/man docs/_build/html

if [[ "${target_platform}" == osx-* ]]; then
    # macOS: the only packaging target is the .app bundle. Build it, then
    # install the bundle intact and expose its launchers on PATH via symlinks
    # (keeping the bundle whole so kitty's resource resolution still works).
    #
    # --ignore-compiler-warnings drops kitty's -Werror. conda's compiler targets
    # macOS 11 (the darwin20 triple), but kitty references a 12.0-introduced
    # symbol (kIOMainPortDefault, effectively the constant 0), which -Werror
    # would reject. Ignoring it is safe: the value works at runtime on all
    # supported versions.
    "$PYTHON" setup.py kitty.app --ignore-compiler-warnings --update-check-interval=0

    mkdir -p "$PREFIX/libexec" "$PREFIX/bin"
    cp -R kitty.app "$PREFIX/libexec/kitty.app"
    ln -sf ../libexec/kitty.app/Contents/MacOS/kitty  "$PREFIX/bin/kitty"
    ln -sf ../libexec/kitty.app/Contents/MacOS/kitten "$PREFIX/bin/kitten"

    # menuinst icon (macOS): lift kitty's own .icns out of the bundle.
    mkdir -p "$PREFIX/Menu"
    cp kitty.app/Contents/Resources/kitty.icns "$PREFIX/Menu/kitty.icns"
else
    # Linux: supported prefix install.
    "$PYTHON" setup.py linux-package --prefix="$PREFIX" \
        --ignore-compiler-warnings --update-check-interval=0
    # menuinst icon (Linux): kitty installs hicolor PNGs; grab a large one.
    mkdir -p "$PREFIX/Menu"
    cp "$PREFIX"/share/icons/hicolor/256x256/apps/kitty.png "$PREFIX/Menu/kitty.png" 2>/dev/null || true
fi

# menuinst shortcut definition (creates a ~/Applications shim .app on macOS and
# a .desktop entry on Linux when installed via `pixi global`).
install -m 0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
