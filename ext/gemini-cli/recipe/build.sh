#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# Keep npm's cache inside the build sandbox (don't touch ~/.npm).
export npm_config_cache="${SRC_DIR}/.npm-cache"

# Install the exact version into $PREFIX (bin/gemini + lib/node_modules/...).
npm install -g "@google/gemini-cli@${PKG_VERSION}" --prefix "$PREFIX"
