#!/usr/bin/env bash
# Spin up an ISOLATED, throwaway shell to test a toolbox mise config.
#
# It copies the config to a fresh temp dir OUTSIDE this repo (so it does NOT
# inherit the full toolbox mise.toml), points all mise data at that temp dir,
# links the in-repo plugins (app, brew), and drops you into a shell with the
# tools active. Nothing global is touched. Exit the shell, then delete the temp
# dir it prints to wipe everything.
#
# Usage:
#   bash scripts/test-shell.sh                 # tests examples/test.mise.toml
#   bash scripts/test-shell.sh /path/to/mise.toml
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-$REPO/examples/test.mise.toml}"

if [[ ! -f "$CONFIG" ]]; then echo "config not found: $CONFIG" >&2; exit 1; fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/toolbox-test.XXXXXX")"
cp "$CONFIG" "$WORK/mise.toml"
: > "$WORK/global.toml"     # empty global config -> ignore the user's real one

export MISE_DATA_DIR="$WORK/.data"
export MISE_STATE_DIR="$WORK/.state"
export MISE_CACHE_DIR="$WORK/.cache"
export MISE_GLOBAL_CONFIG_FILE="$WORK/global.toml"
export MISE_TRUSTED_CONFIG_PATHS="$WORK"
export npm_config_cache="$WORK/.npm"          # sidestep a root-owned ~/.npm
export MISE_APP_LAUNCHER_DIR="$WORK/launchers" # app: backend writes .app/.desktop here, not ~/
mkdir -p "$MISE_DATA_DIR/shims"

# cd into the throwaway workdir FIRST: every mise invocation parses the config
# in cwd, and the repo's own (untrusted-here) mise.toml would otherwise abort
# even `mise plugins link`.
cd "$WORK"
mise trust "$WORK" >/dev/null
bash "$REPO/scripts/link-plugins.sh"          # links into THIS sandbox's plugin dir

# Shim dir on PATH makes installed tools runnable; survives `exec` (it's an
# exported env var), and new installs reshim into the same dir.
export PATH="$MISE_DATA_DIR/shims:$PATH"

cat <<EOF

+- toolbox test shell ----------------------------------------------
| config  : $CONFIG
| workdir : $WORK
|           (throwaway; nothing global is touched)
|
| 1. install FIRST (nothing is on PATH until you do):
|      mise install                    # everything in the config
|      mise install ripgrep app:kitty  # just a few
| 2. run  : rg --version / claude --version / kitty --version
|      'which kitty' should point INTO the workdir above, not ~/.pixi/bin
| leave : exit        wipe: rm -rf "$WORK"
+-------------------------------------------------------------------
EOF

# Launch the interactive shell with an ISOLATED rc. Your normal rc (sourced for
# prompt/aliases) prepends ~/.pixi/bin, which would shadow the test shims — so we
# source it, then re-prepend the test shims and activate mise so toolbox tools
# win. Without this the shell isn't actually isolated from your global pixi.
SHIMS="$MISE_DATA_DIR/shims"
case "$(basename "${SHELL:-zsh}")" in
  zsh)
    export ZDOTDIR="$WORK/.zdotdir"; mkdir -p "$ZDOTDIR"
    cat > "$ZDOTDIR/.zshrc" <<RC
[ -f "\$HOME/.zshrc" ] && source "\$HOME/.zshrc"
export PATH="$SHIMS:\$PATH"
command -v mise >/dev/null 2>&1 && eval "\$(mise activate zsh)"
RC
    exec zsh -i ;;
  bash)
    cat > "$WORK/.bashrc.test" <<RC
[ -f "\$HOME/.bashrc" ] && source "\$HOME/.bashrc"
export PATH="$SHIMS:\$PATH"
command -v mise >/dev/null 2>&1 && eval "\$(mise activate bash)"
RC
    exec bash --rcfile "$WORK/.bashrc.test" -i ;;
  fish)
    exec fish -C "set -gx PATH $SHIMS \$PATH; command -v mise >/dev/null 2>&1; and mise activate fish | source" ;;
  *)
    exec "${SHELL:-/bin/sh}" -i ;;
esac
