#!/usr/bin/env bash
# bootstrap.sh — first-time setup: install git+curl, clone the repo, install
# Homebrew, run update.sh (packages + configs).
#
#   curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
#   # workstation profile:  ... | bash -s -- --type workstation
#   # rootless (no sudo):   ... | bash -s -- --no-root
#   # or, in a clone:  ./bootstrap.sh [--type workstation] [--no-root]
#
# Day-to-day after this: ./update.sh (install new packages, upgrade everything,
# apply configs).
#
# Env overrides:
#   DOTFILES_REPO       git URL to clone (default: this repo)
#   DOTFILES_DIR        where to clone   (default: ~/dotfiles)
#   DOTFILES_NO_UPDATE  =1 to use an existing checkout as-is (no clone/pull)
#   BREW_PREFIX         e.g. "$HOME/.homebrew" for a ROOTLESS install (no sudo).
#       Caveat: a non-standard prefix has no prebuilt bottles, so most formulae
#       build from source (needs a compiler). Use only where you can't get the
#       standard prefix.
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/doeringchristian/dotfiles.git}"
DEST="${DOTFILES_DIR:-$HOME/dotfiles}"
# Run from a checkout (not piped from curl): use that checkout as-is.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$(dirname "$SELF")/update.sh" ]; then
    DEST="$(cd "$(dirname "$SELF")" && pwd)"
    DOTFILES_NO_UPDATE=1
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 1. Minimal prerequisites: git + curl. Homebrew brings the rest.
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

# 2. Clone or update the repo (skipped when run from a checkout).
fetch_repo() {
    if [ "${DOTFILES_NO_UPDATE:-0}" = 1 ]; then
        [ -d "$DEST" ] || { log "DOTFILES_NO_UPDATE=1 but $DEST is missing"; exit 1; }
        log "Using existing checkout at $DEST"
    elif [ -d "$DEST/.git" ]; then
        log "Updating $DEST"; git -C "$DEST" pull --ff-only
    else
        log "Cloning $REPO -> $DEST"; git clone "$REPO" "$DEST"
    fi
}

# 3. Homebrew (standard prefix, or rootless into $BREW_PREFIX).
ensure_brew() {
    BREW_PREFIX="${BREW_PREFIX:-}"
    if ! have brew && ! { [ -n "$BREW_PREFIX" ] && [ -x "$BREW_PREFIX/bin/brew" ]; }; then
        if [ -n "$BREW_PREFIX" ]; then
            log "Installing Homebrew (rootless) into $BREW_PREFIX"
            mkdir -p "$BREW_PREFIX" && chmod 755 "$BREW_PREFIX"
            curl -fsSL https://github.com/Homebrew/brew/tarball/main | tar xz --strip-components 1 -C "$BREW_PREFIX"
        else
            log "Installing Homebrew"
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
    fi
    for p in "${BREW_PREFIX:+$BREW_PREFIX/bin/brew}" \
             "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew \
             /home/linuxbrew/.linuxbrew/bin/brew; do
        [ -n "$p" ] && [ -x "$p" ] && { eval "$("$p" shellenv)"; break; }
    done
    if [ -n "$BREW_PREFIX" ]; then brew update --force --quiet 2>/dev/null || true; fi
}

# Parse --no-root (remaining args forwarded to update.sh).
NOROOT=""
FORWARD_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --no-root) NOROOT=1; shift ;;
    *)         FORWARD_ARGS+=("$1"); shift ;;
    esac
done
[ "$NOROOT" = 1 ] && BREW_PREFIX="${BREW_PREFIX:-$HOME/.homebrew}"

ensure_prereqs
fetch_repo
cd "$DEST"
ensure_brew
# 4. Packages + configs — the same script as day-to-day updates. Forwards
#    --type <profile> and --no-root.
bash ./update.sh ${NOROOT:+"--no-root"} "${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}"

cat <<'EOF'

==> Setup complete. Restart your terminal.
    Day-to-day: ./update.sh (new packages, upgrades, configs).
EOF
