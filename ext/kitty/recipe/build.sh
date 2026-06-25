#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# Install kitty from its official prebuilt binaries (see recipe.yaml). The
# bundle is relocatable (binaries resolve their libs via $ORIGIN/../lib and
# /proc/self/exe), so we keep the tree intact under libexec/ and expose the
# launchers on PATH via symlinks.
mkdir -p "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/Menu"

if [[ "${target_platform}" == osx-* ]]; then
    # Mount the official .dmg and lift kitty.app out intact.
    mnt="$(mktemp -d)"
    hdiutil attach kitty.dmg -mountpoint "$mnt" -nobrowse -readonly -quiet
    cp -R "$mnt/kitty.app" "$PREFIX/libexec/kitty.app"
    hdiutil detach "$mnt" -quiet || true
    ln -sf ../libexec/kitty.app/Contents/MacOS/kitty  "$PREFIX/bin/kitty"
    ln -sf ../libexec/kitty.app/Contents/MacOS/kitten "$PREFIX/bin/kitten"
    cp "$PREFIX/libexec/kitty.app/Contents/Resources/kitty.icns" "$PREFIX/Menu/kitty.icns"
else
    # Linux: the .txz was extracted into dist/ (bin/ lib/ share/).
    cp -R dist "$PREFIX/libexec/kitty"
    ln -sf ../libexec/kitty/bin/kitty  "$PREFIX/bin/kitty"
    ln -sf ../libexec/kitty/bin/kitten "$PREFIX/bin/kitten"
    cp "$PREFIX/libexec/kitty/share/icons/hicolor/256x256/apps/kitty.png" "$PREFIX/Menu/kitty.png"
fi

# menuinst shortcut definition (creates a ~/Applications shim .app on macOS and
# a .desktop entry on Linux when installed via `pixi global`).
install -m 0644 "${RECIPE_DIR}/menu.json" "${PREFIX}/Menu/${PKG_NAME}_menu.json"
