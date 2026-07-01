#!/usr/bin/env bash
# fix-claude-code.sh — finalize claude-code's native binary.
#
# claude-code ships its platform-native binary via an npm postinstall
# (install.cjs). mise's npm backend installs with `--ignore-scripts`, so that step
# is skipped and `claude` errors with "native binary not installed" — every fresh
# install AND every `mise upgrade` of claude-code re-triggers this. This script
# runs the postinstall ourselves. It's idempotent and a no-op once `claude` works,
# so it's safe to call from sync.sh/update.sh or by hand any time claude breaks.
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$PATH"

if claude --version >/dev/null 2>&1; then
    exit 0   # already working — nothing to do
fi

cc="$HOME/.local/share/mise/installs/npm-anthropic-ai-claude-code/latest/lib/node_modules/@anthropic-ai/claude-code"
if [ ! -f "$cc/install.cjs" ]; then
    echo "!! claude-code install.cjs not found at $cc — is claude-code installed via mise?" >&2
    exit 0   # don't abort a larger sync/update over this
fi

echo "==> finalizing claude-code native binary (postinstall)"
if ( cd "$cc" && node install.cjs ) >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
    echo "   claude $(claude --version 2>/dev/null)"
else
    echo "!! claude-code postinstall did not fix it; try: (cd '$cc' && node install.cjs)" >&2
fi
