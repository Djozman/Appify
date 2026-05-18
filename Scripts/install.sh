#!/bin/bash
# Build and install appify to /usr/local/bin
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Building Appify..."
swift build -c release

BINARY=".build/release/Appify"
INSTALL_PATH="/usr/local/bin/appify"

echo "Installing to $INSTALL_PATH..."
sudo cp "$BINARY" "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

echo ""
echo "✓ Installed! Try:"
echo "  appify https://monochrome.tf \"Monochrome\""
