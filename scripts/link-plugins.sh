#!/usr/bin/env bash
# Link the in-repo mise backend plugins locally so mise.toml can reference them
# WITHOUT publishing them to GitHub. The plugin sources live in this repo, so
# they're present on every machine that clones it:
#   app  — GUI apps from prebuilt GitHub binaries (kitty, tev)
#   src  — from-source builds for tools with no binary backend (stow, passage)
#
# Run this BEFORE `mise install`. It uses `mise plugins link` directly (not a
# mise task) because `mise run` resolves the tool env first — which would fail
# while the plugins are still unlinked. Idempotent; safe to re-run.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root

mise plugins link --force app "$HERE/plugins/mise-app"
mise plugins link --force src "$HERE/plugins/mise-src"

echo "linked local plugins: app (GUI-app backend), src (from-source backend)"
