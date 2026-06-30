#!/usr/bin/env bash
# update.sh — refresh the mise-managed toolset (mise edition).
#
#   ./update.sh             Advance every tool within its version spec and update
#                           mise.lock; "latest" tools (claude-code, gemini-cli,
#                           neovim nightly, app:kitty/app:tev) re-resolve to the
#                           newest upstream. Then re-sync configs.
#
#   ./update.sh <tool>...   Upgrade only the named tools, e.g.
#                           `./update.sh app:kitty claude-code`.
#
# Most tools just need `mise upgrade`. The exception is moving-ref source builds
# (`src:sshr` tracks `main`): mise sees a static version string, so it won't
# rebuild on its own — we force-reinstall them (mirrors pixi update.sh, which
# force-rebuilt its moving-ref ext/ packages).
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Moving-ref source builds to force-rebuild on a full update.
MOVING_REF=("src:sshr")

bash "$PROJECT_DIR/scripts/link-plugins.sh"

if [ "$#" -gt 0 ]; then
    echo "==> upgrading: $*"
    mise upgrade "$@"
else
    echo "==> upgrading all tools to latest allowed versions"
    mise upgrade
    echo "==> force-rebuilding moving-ref source builds: ${MOVING_REF[*]}"
    mise install --force "${MOVING_REF[@]}" || true
fi

# Re-install/upgrade mise tools + re-apply stow/fonts/dconf.
echo "==> re-syncing configs"
./sync.sh
