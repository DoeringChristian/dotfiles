#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

# Refresh conda deps to their latest allowed versions. For source packages that
# track a moving ref (neovim nightly, sshr main), force a fresh build:
#   pixi clean && ./sync.sh
export PIXI_BUILD_BACKEND_OVERRIDE="pixi-build-npm=$PROJECT_DIR/ext/pixi-build-npm/pixi-build-npm"
pixi update
UPDATE=1 ./sync.sh
