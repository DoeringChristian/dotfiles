#!/usr/bin/env bash
set -e

# Portable realpath fallback (macOS lacks realpath by default)
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$PROJECT_DIR"

nix flake update
./sync.sh
