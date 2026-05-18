#!/bin/bash
set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Building Launcher..."
swift build -c release --product Launcher
mkdir -p Sources/Appify/Resources
cp .build/release/Launcher Sources/Appify/Resources/Launcher

echo "Building Appify..."
swift build -c release --product Appify

echo ""
echo "Build complete. Example:"
echo "  .build/release/Appify https://monochrome.tf \"Monochrome\""
