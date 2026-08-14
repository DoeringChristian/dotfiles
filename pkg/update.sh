#!/usr/bin/env bash
# update.sh — bring the whole toolset to the newest version that exists.
#   pkg tools : brew upgrade (macOS) / pixi global update (Linux)
#   everything else re-runs install.sh, whose self/npm/uv/source/github methods all
#   re-fetch latest (git main, newest release, latest npm, the self-updater, …).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

if [ "$OS" = Darwin ]; then
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
    echo "==> brew update && upgrade"; brew update && brew upgrade && brew upgrade --cask
else
    export PATH="$HOME/.pixi/bin:$PATH"
    echo "==> pixi global update"; pixi global update
fi

echo "==> re-running install.sh (self/npm/uv/source/github tools -> latest)"
bash "$DIR/install.sh"
