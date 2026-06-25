#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# Install tev from its official prebuilt binaries (see recipe.yaml).
mkdir -p "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/Menu"

if [[ "${target_platform}" == osx-* ]]; then
    # Mount the .dmg and lift the tev binary + icon out of tev.app. The macOS
    # binary uses system frameworks (no bundled dylibs), so the binary alone
    # is enough; the menuinst shim (made by `pixi global`) is the GUI launcher.
    mnt="$(mktemp -d)"
    hdiutil attach tev.dmg -mountpoint "$mnt" -nobrowse -readonly -quiet
    cp "$mnt/tev.app/Contents/MacOS/tev" "$PREFIX/bin/tev"
    cp "$mnt/tev.app/Contents/Resources/icon.icns" "$PREFIX/Menu/tev.icns"
    hdiutil detach "$mnt" -quiet || true
else
    # Linux: extract the AppImage's AppDir and keep it intact under libexec/
    # (the binary resolves its bundled libs via rpath $ORIGIN/../lib).
    chmod +x tev.appimage
    ./tev.appimage --appimage-extract >/dev/null
    cp -R squashfs-root "$PREFIX/libexec/tev"
    # Symlink the real binary onto PATH (locate it defensively).
    real="$(cd "$PREFIX/libexec/tev" && find . -type f -name tev -path '*bin/*' | head -1)"
    real="${real#./}"
    ln -sf "../libexec/tev/${real}" "$PREFIX/bin/tev"
    # menuinst icon: grab the AppDir's tev.png.
    icon="$(find "$PREFIX/libexec/tev" -name 'tev.png' | head -1)"
    [ -n "$icon" ] && cp "$icon" "$PREFIX/Menu/tev.png" || true
fi

# menuinst shortcut definition (~/Applications shim .app on macOS / .desktop on Linux).
install -m 0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
