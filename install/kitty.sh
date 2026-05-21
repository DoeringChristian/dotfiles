#!/usr/bin/env bash
set -e

echo "Installing/updating kitty..."
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
