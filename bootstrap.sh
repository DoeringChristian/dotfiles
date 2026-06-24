#!/usr/bin/env bash
# One-line bootstrap for these dotfiles on a fresh machine.
#
#   curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
#
# It installs the only two prerequisites (git + curl), clones the repo, and hands
# off to setup.sh -- which installs pixi and lets pixi pull in everything else.
#
# Env overrides:
#   DOTFILES_REPO       git URL to clone (default: this repo)
#   DOTFILES_DIR        where to clone   (default: ~/dotfiles)
#   DOTFILES_NO_UPDATE  =1 to use an existing checkout as-is (no clone/pull)
#   SKIP_SECRETS        =1 to skip age key decryption (passed to setup.sh)
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/doeringchristian/dotfiles.git}"
DEST="${DOTFILES_DIR:-$HOME/dotfiles}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 1. Minimal prerequisites: git + curl. pixi (installed by setup.sh) brings the rest.
ensure_prereqs() {
    have git && have curl && return 0
    log "Installing prerequisites (git, curl)..."
    local sudo=""
    [ "$(id -u)" -ne 0 ] && have sudo && sudo=sudo
    if   have apt-get; then $sudo apt-get update -qq && $sudo apt-get install -y -qq git curl ca-certificates
    elif have dnf;     then $sudo dnf install -y -q git curl
    elif have pacman;  then $sudo pacman -Sy --noconfirm --needed git curl
    elif have zypper;  then $sudo zypper --non-interactive install git curl
    elif have apk;     then $sudo apk add --no-cache git curl
    elif have brew;    then brew install git curl
    elif [ "$(uname)" = Darwin ]; then xcode-select --install 2>/dev/null || true
    else log "Could not auto-install git/curl. Install them and re-run."; exit 1
    fi
}

# 2. Clone or update the repo (skippable for local testing).
fetch_repo() {
    if [ "${DOTFILES_NO_UPDATE:-0}" = 1 ]; then
        [ -d "$DEST" ] || { log "DOTFILES_NO_UPDATE=1 but $DEST is missing"; exit 1; }
        log "Using existing checkout at $DEST (DOTFILES_NO_UPDATE=1)"
    elif [ -d "$DEST/.git" ]; then
        log "Updating $DEST"; git -C "$DEST" pull --ff-only
    else
        log "Cloning $REPO -> $DEST"; git clone "$REPO" "$DEST"
    fi
}

ensure_prereqs
fetch_repo
log "Handing off to setup.sh..."
cd "$DEST"
exec ./setup.sh
