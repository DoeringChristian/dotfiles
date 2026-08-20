#!/usr/bin/env bash
# update.sh — bring the whole toolset to the newest version that exists.
#   brew formulae/casks: brew upgrade.  --HEAD formulae (neovim, sshr, passage) and
#   self/npm/uv tools: re-running install.sh rebuilds/re-fetches them at latest.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
done
echo "==> brew update && upgrade"
brew update && brew upgrade
[ "$(uname -s)" = Darwin ] && brew upgrade --cask
echo "==> brew upgrade --fetch-HEAD (neovim/sshr/passage) + self/npm/uv via install.sh"
brew upgrade --fetch-HEAD $(brew list --formula 2>/dev/null | grep -xE 'neovim|sshr|passage') 2>/dev/null || true
bash "$DIR/install.sh"
