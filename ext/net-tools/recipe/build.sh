#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# net-tools has an interactive `make config`; feed it blank lines to accept all
# defaults (this is upstream's own non-interactive method, used by `distcheck`).
yes "" | make config
make

# BASEDIR is the prefix; force every binary onto $PREFIX/bin (default splits
# some into sbin, which conda doesn't put on PATH) and man into share/man.
make BASEDIR="$PREFIX" BINDIR=/bin SBINDIR=/bin mandir="$PREFIX/share/man" install
