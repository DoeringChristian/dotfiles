#!/usr/bin/env bash
# Test the bootstrap end-to-end on a clean Linux container.
#
#   tests/run.sh [distro] [--full|--remote]
#
#   distro : ubuntu (default) | debian | fedora | arch
#   (no flag) : smoke test -- bootstrap the LOCAL working tree with a minimal
#               channel-only manifest. Fast (~couple min); checks the plumbing
#               (prereqs -> pixi -> sync -> ~/.pixi/bin -> stow).
#   --full    : same, but with the REAL pixi-global.toml -> builds every ext/
#               source package (kitty, tev, neovim, ...). Slow (~15-20 min).
#   --remote  : run the actual `curl | bash` one-liner from GitHub (tests the
#               *pushed* main, incl. clone + git-lfs + full build). Slow.
#
# Needs docker (or set DOCKER=podman). The local modes copy the working tree in,
# so they test uncommitted changes; --remote tests what's on origin/main.
set -euo pipefail

DISTRO=ubuntu; MODE=smoke
for a in "$@"; do
    case "$a" in
        --full)   MODE=full ;;
        --remote) MODE=remote ;;
        ubuntu|debian|fedora|arch) DISTRO="$a" ;;
        *) echo "usage: tests/run.sh [ubuntu|debian|fedora|arch] [--full|--remote]" >&2; exit 1 ;;
    esac
done

case "$DISTRO" in
    ubuntu) IMAGE=ubuntu:24.04 ;;
    debian) IMAGE=debian:stable-slim ;;
    fedora) IMAGE=fedora:latest ;;
    arch)   IMAGE=archlinux:latest ;;
esac

DOCKER="${DOCKER:-docker}"
command -v "$DOCKER" >/dev/null || { echo "need '$DOCKER' on PATH (set DOCKER=podman to use podman)" >&2; exit 1; }
REPO=$(cd "$(dirname "$0")/.." && pwd)

# Assertions run inside the container after the bootstrap. $-vars are escaped so
# they evaluate in the container, not here.
read -r -d '' ASSERT <<'A' || true
export PATH="$HOME/.pixi/bin:$PATH"
echo "--- verifying ---"
fail=0
for t in rg fish stow git; do
    if command -v "$t" >/dev/null; then echo "  ok: $t -> $(command -v "$t")"; else echo "  MISSING: $t"; fail=1; fi
done
# stow may "fold" (symlink the whole ~/.config/fish dir) on a fresh machine, so
# check that config.fish *resolves* into the repo rather than being a symlink itself.
cfg=$(readlink -f "$HOME/.config/fish/config.fish" 2>/dev/null || true)
case "$cfg" in
    */common/.config/fish/config.fish) [ -f "$cfg" ] && echo "  ok: config.fish -> $cfg" || { echo "  MISSING: config.fish target"; fail=1; } ;;
    *) echo "  MISSING: config.fish not stow-linked (resolved: ${cfg:-none})"; fail=1 ;;
esac
[ "$fail" = 0 ] && echo "==> PASS" || { echo "==> FAIL"; exit 1; }
A

if [ "$MODE" = remote ]; then
    echo "==> [$DISTRO/$IMAGE] remote: curl | bash from origin/main (full build, slow)"
    "$DOCKER" run --rm -i "$IMAGE" bash -c "
        set -euo pipefail
        command -v curl >/dev/null || { \
            command -v apt-get >/dev/null && apt-get update -qq && apt-get install -y -qq curl ca-certificates || \
            command -v dnf >/dev/null && dnf install -y -q curl || \
            command -v pacman >/dev/null && pacman -Sy --noconfirm curl; }
        export SKIP_SECRETS=1
        curl -fsSL https://raw.githubusercontent.com/doeringchristian/dotfiles/main/bootstrap.sh | bash
        $ASSERT
    "
else
    manifest_env=""
    [ "$MODE" = smoke ] && manifest_env="PIXI_GLOBAL_MANIFEST=/root/dotfiles/tests/fixtures/minimal-global.toml"
    echo "==> [$DISTRO/$IMAGE] local $MODE: bootstrap working tree $([ "$MODE" = smoke ] && echo '(minimal manifest, fast)' || echo '(real manifest, slow)')"
    # Stream the working tree in (skip .git / built env), then bootstrap it.
    tar -C "$REPO" --exclude='./.git' --exclude='./.pixi' -czf - . | \
    "$DOCKER" run --rm -i "$IMAGE" bash -c "
        set -euo pipefail
        mkdir -p /root/dotfiles && tar -C /root/dotfiles -xzf -
        cd /root/dotfiles
        DOTFILES_NO_UPDATE=1 SKIP_SECRETS=1 $manifest_env bash bootstrap.sh
        $ASSERT
    "
fi
