#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

cmake -G Ninja -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build build --parallel "${CPU_COUNT}"

mkdir -p "$PREFIX/Menu"
if [[ "${target_platform}" == osx-* ]]; then
    # macOS builds an app bundle; the menuinst shim (created by `pixi global`)
    # is the GUI launcher, so we just need the CLI binary + the icon.
    mkdir -p "$PREFIX/bin"
    cp build/tev.app/Contents/MacOS/tev "$PREFIX/bin/tev"
    cp build/tev.app/Contents/Resources/icon.icns "$PREFIX/Menu/tev.icns"
else
    cmake --install build
    # menuinst icon (Linux): tev installs hicolor PNGs.
    cp "$PREFIX"/share/icons/hicolor/*/apps/tev.png "$PREFIX/Menu/tev.png" 2>/dev/null || true
fi

# menuinst shortcut definition (~/Applications shim .app on macOS / .desktop on Linux).
install -m 0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
