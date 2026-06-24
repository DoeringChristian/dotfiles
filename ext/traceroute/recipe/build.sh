#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

make
# `prefix=` (not DESTDIR) gives $PREFIX/bin/traceroute and $PREFIX/share/man.
make prefix="$PREFIX" install
