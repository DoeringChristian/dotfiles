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
# Unlike the pixi update.sh there are no build caches to bust — mise installs
# prebuilt artifacts, so `mise upgrade` is the whole story.
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

bash "$PROJECT_DIR/scripts/link-plugins.sh"

if [ "$#" -gt 0 ]; then
    echo "==> upgrading: $*"
    mise upgrade "$@"
else
    echo "==> upgrading all tools to latest allowed versions"
    mise upgrade
fi

# Re-install/upgrade mise tools + re-apply stow/fonts/dconf.
echo "==> re-syncing configs"
./sync.sh
