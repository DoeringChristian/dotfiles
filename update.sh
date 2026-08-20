#!/usr/bin/env bash
# update.sh — bring the whole toolset to the newest version.
#   brew formulae/casks: brew upgrade.  --HEAD formulae (neovim, sshr, passage):
#   refreshed from git via brew upgrade --fetch-HEAD.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
TAP="doeringc/local"

for p in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && eval "$("$p" shellenv)"
done

# refresh the tap in case Formula/*.rb changed in the repo
brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
cp -f "$REPO/Formula/"*.rb "$(brew --repo "$TAP")/Formula/" 2>/dev/null || true
brew trust "$TAP" >/dev/null 2>&1 || true

echo "==> brew update && upgrade"
brew update && brew upgrade
[ "$(uname -s)" = Darwin ] && brew upgrade --cask
echo "==> rebuild --HEAD formulae (neovim, sshr, passage) from latest git"
brew upgrade --fetch-HEAD neovim "$TAP/sshr" "$TAP/passage" 2>/dev/null || true
echo "==> done."
