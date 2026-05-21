#!/usr/bin/env bash
set -e

OS="$(uname -s)"
ARCH="$(uname -m)"

# Get latest release download URL from GitHub
LATEST_URL="https://api.github.com/repos/Tom94/tev/releases/latest"

echo "Fetching latest tev release..."

if [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        ASSET="tev.dmg"
    else
        ASSET="tev-intel.dmg"
    fi

    URL="$(curl -sL "$LATEST_URL" | grep "browser_download_url.*$ASSET" | head -1 | cut -d '"' -f 4)"
    if [ -z "$URL" ]; then
        echo "Error: could not find $ASSET in latest release" >&2
        exit 1
    fi

    TMPDIR="$(mktemp -d)"
    echo "Downloading $ASSET..."
    curl -sL "$URL" -o "$TMPDIR/tev.dmg"

    echo "Mounting and installing..."
    hdiutil attach -quiet "$TMPDIR/tev.dmg" -mountpoint "$TMPDIR/mnt"
    cp -R "$TMPDIR/mnt/tev.app" /Applications/tev.app
    hdiutil detach -quiet "$TMPDIR/mnt"
    rm -rf "$TMPDIR"

    echo "tev installed to /Applications/tev.app"

elif [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "aarch64" ]; then
        ASSET="tev-arm.appimage"
    else
        ASSET="tev.appimage"
    fi

    URL="$(curl -sL "$LATEST_URL" | grep "browser_download_url.*$ASSET" | head -1 | cut -d '"' -f 4)"
    if [ -z "$URL" ]; then
        echo "Error: could not find $ASSET in latest release" >&2
        exit 1
    fi

    echo "Downloading $ASSET..."
    mkdir -p ~/.local/bin
    curl -sL "$URL" -o ~/.local/bin/tev
    chmod +x ~/.local/bin/tev

    echo "tev installed to ~/.local/bin/tev"

else
    echo "Error: unsupported OS: $OS" >&2
    exit 1
fi
