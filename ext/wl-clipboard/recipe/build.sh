#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# --wrap-mode=nodownload keeps meson from fetching subproject fallbacks; the
# conda host deps (wayland, wayland-protocols) satisfy everything.
meson setup build --prefix="$PREFIX" --buildtype=release --wrap-mode=nodownload
ninja -C build install
