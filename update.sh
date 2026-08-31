#!/usr/bin/env bash
# update.sh — bring the whole toolset to the newest version.
#   brew formulae/casks: brew upgrade.  --HEAD formulae (neovim, sshr, passage):
#   refreshed from git via brew upgrade --fetch-HEAD.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
TAP="doeringc/local"

for p in "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -x "$p" ] && {
        eval "$("$p" shellenv)"
        break
    }
done
command -v brew >/dev/null 2>&1 || {
    echo "brew not found — run ./setup.sh first" >&2
    exit 1
}

# Keep Homebrew's modern Node ahead of an old distro Node. npm's env-based
# launcher otherwise fails on imports such as `node:path`.
brew list --versions node >/dev/null 2>&1 || brew install node
export PATH="$(brew --prefix node)/bin:$PATH"
hash -r

if [ "$(uname -s)" = Linux ]; then
    export HOMEBREW_MAKE_JOBS="${HOMEBREW_MAKE_JOBS:-2}"
fi

# refresh the tap in case Formula/*.rb changed in the repo
brew tap-new "$TAP" --no-git >/dev/null 2>&1 || true
cp -f "$REPO/Formula/"*.rb "$(brew --repo "$TAP")/Formula/" 2>/dev/null || true
brew trust "$TAP" >/dev/null 2>&1 || true

echo "==> brew update && upgrade"
brew update && brew upgrade
# --greedy so version:latest casks (claude-code@latest) re-fetch; casks work on Linux too.
brew upgrade --cask --greedy
echo "==> rebuild --HEAD formulae (neovim, sshr, passage) from latest git"
brew upgrade --fetch-HEAD neovim "$TAP/sshr" "$TAP/passage" 2>/dev/null || true
# brew bundle's npm entry only installs-if-missing, so bump npm globals (gemini-cli).
echo "==> npm globals -> latest"
command -v npm >/dev/null 2>&1 && npm update -g 2>/dev/null || true
echo "==> done."
