#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# The `all` target is a no-op; `install` lays down the script + completions.
make install PREFIX="$PREFIX" WITH_ALLCOMP=yes
