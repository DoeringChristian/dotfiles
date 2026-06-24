#!/usr/bin/env bash

set -o xtrace -o nounset -o pipefail -o errexit

# Build only the bundled tree-sitter language parsers; every other dependency
# (libuv, luajit, lpeg, tree-sitter runtime, unibilium, utf8proc, luv) comes
# from the conda-forge host dependencies declared in recipe.yaml.
cmake -S cmake.deps -B .deps \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BUNDLED=OFF \
    -DUSE_BUNDLED_TS_PARSERS=ON
cmake --build .deps

extra_args=()
if [[ "${target_platform}" == osx-* ]]; then
    extra_args+=(-DLIBINTL_LIBRARY="${PREFIX}/lib/libintl${SHLIB_EXT}")
fi

cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TRANSLATIONS=ON \
    -DLIBUV_LIBRARY="${PREFIX}/lib/libuv${SHLIB_EXT}" \
    -DLPEG_LIBRARY="${PREFIX}/lib/liblpeg${SHLIB_EXT}" \
    "${extra_args[@]}" \
    ${CMAKE_ARGS}
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build --parallel "${CPU_COUNT}"

# Tell `pixi global` not to set CONDA_PREFIX when activating this tool.
# https://pixi.sh/latest/global_tools/introduction/#opt-out-of-conda_prefix
mkdir -p "${PREFIX}/etc/pixi/nvim"
touch "${PREFIX}/etc/pixi/nvim/global-ignore-conda-prefix"
