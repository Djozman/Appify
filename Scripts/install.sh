#!/bin/bash
# Build both targets and install appify to /usr/local/bin
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Building Launcher binary..."
swift build -c release --product Launcher

echo "Embedding Launcher into Appify resources..."
mkdir -p Sources/Appify/Resources
cp .build/release/Launcher Sources/Appify/Resources/Launcher

echo "Building Appify CLI..."
swift build -c release --product Appify

INSTALL_PATH="/usr/local/bin/appify"
echo "Installing to $INSTALL_PATH..."
sudo cp .build/release/Appify "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

echo ""
echo "✓ Installed! Zero dependencies. Try:"
echo "  appify https://monochrome.tf \"Monochrome\""
