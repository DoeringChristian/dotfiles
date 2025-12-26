#!/usr/bin/env bash
set -e

# Goto the directory this executable is located in
PROJECT_DIR=$(dirname "$(realpath $0)")
cd $PROJECT_DIR

nix flake update
./sync.sh
