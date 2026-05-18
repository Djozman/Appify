#!/bin/bash
# Dev loop: build release and show usage
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Building..."
swift build -c release

BINARY=".build/release/Appify"
echo ""
echo "Build succeeded. Binary at: $BINARY"
echo ""
echo "Example:"
echo "  $BINARY https://monochrome.tf \"Monochrome\""
