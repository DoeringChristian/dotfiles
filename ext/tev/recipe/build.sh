#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

cmake -G Ninja -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build build --parallel "${CPU_COUNT}"

if [[ "${target_platform}" == osx-* ]]; then
    # On macOS the `tev` target is built as an app bundle, and `cmake --install`
    # would drop a tev.app under $PREFIX/Applications plus a symlink. For a CLI
    # conda package we just lift the real binary out of the bundle.
    mkdir -p "$PREFIX/bin"
    cp build/tev.app/Contents/MacOS/tev "$PREFIX/bin/tev"
else
    cmake --install build
fi
