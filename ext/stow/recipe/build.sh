#!/usr/bin/env bash
set -o xtrace -o nounset -o pipefail -o errexit

# `--with-pmdir` pins the Perl module dir under $PREFIX. Without it, stow's
# configure auto-detects perl's sitelib (which lives in the *build* prefix),
# so Stow.pm would be captured at a build-specific junk path and the package
# wouldn't relocate. This is the no-patch equivalent of conda-forge's fix.
./configure --prefix="$PREFIX" --with-pmdir="$PREFIX/share/perl5"
make
make install
