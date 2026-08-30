#!/usr/bin/env bash
# setup.sh — first-time setup: install Homebrew, then sync (packages + configs via
# sync.sh), then decrypt the age secret.
#
#   ./setup.sh                       # base toolset
#   ./setup.sh --type workstation    # base + Brewfile.workstation (GUI apps, …)
#   SKIP_SECRETS=1 ./setup.sh        # skip the age key (CI / minimal)
#   BREW_PREFIX="$HOME/.homebrew" ./setup.sh   # ROOTLESS install (no sudo). Caveat:
#       a non-standard prefix has no prebuilt bottles, so most formulae build from
#       source (needs a compiler). Use only where you can't get the standard prefix.
#
# Day-to-day after this: ./sync.sh (install new packages + apply configs),
# ./update.sh (upgrade everything to latest).
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"; cd "$REPO"
have() { command -v "$1" >/dev/null 2>&1; }

# 1. Homebrew (standard prefix, or rootless into $BREW_PREFIX).
BREW_PREFIX="${BREW_PREFIX:-}"
if ! have brew && ! { [ -n "$BREW_PREFIX" ] && [ -x "$BREW_PREFIX/bin/brew" ]; }; then
    if [ -n "$BREW_PREFIX" ]; then
        echo "==> installing Homebrew (rootless) into $BREW_PREFIX"
        mkdir -p "$BREW_PREFIX"
        curl -fsSL https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C "$BREW_PREFIX"
    else
        echo "==> installing Homebrew"
        /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
fi
for p in "${BREW_PREFIX:+$BREW_PREFIX/bin/brew}" \
         "$HOME/.homebrew/bin/brew" /opt/homebrew/bin/brew /usr/local/bin/brew \
         /home/linuxbrew/.linuxbrew/bin/brew; do
    [ -n "$p" ] && [ -x "$p" ] && { eval "$("$p" shellenv)"; break; }
done
[ -n "$BREW_PREFIX" ] && brew update --force --quiet 2>/dev/null || true

# 2. Packages + configs (install everything, stow) — shared with ./sync.sh.
#    Forwards --type <profile> (e.g. `./setup.sh --type workstation`).
bash "$REPO/sync.sh" "$@"

# 3. Secrets: decrypt the age key (age is a brew tool now on PATH).
if [ "${SKIP_SECRETS:-0}" != 1 ] && [ -f ./setup/age-key.age ]; then
    echo "==> decrypting age key"
    mkdir -p ~/.local/share/age ~/.passage
    age -d ./setup/age-key.age > ~/.local/share/age/key.txt
    chmod 600 ~/.local/share/age/key.txt
    cp ~/.local/share/age/key.txt ~/.passage/identities
fi

cat <<'EOF'

==> setup complete. Everything is Homebrew (+ the sshr/passage tap formulae).
    Day-to-day: ./sync.sh (new packages + configs), ./update.sh (upgrade all).
EOF
