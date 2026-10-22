#!/usr/bin/env bash
# Run a TeX command with Homebrew's TeX Live first on PATH, so a stray
# pdflatex from MacTeX or a conda env never builds the writeup.
set -euo pipefail
prefix=$(brew --prefix texlive 2>/dev/null || true)
if [ -z "$prefix" ] || [ ! -x "$prefix/bin/pdflatex" ]; then
    echo "error: Homebrew texlive not found; install it with: brew install texlive" >&2
    exit 1
fi
export PATH="$prefix/bin:$PATH"
exec "$@"
