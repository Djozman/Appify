#!/bin/bash
# Full release: universal binary → .app → .dmg
# Usage: ./Scripts/release.sh [version]
#   e.g: ./Scripts/release.sh 1.0.0
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Accept version as argument or read from version.env
if [ -n "$1" ]; then
  VERSION="$1"
  BUILD_NUMBER=$(( $(grep BUILD_NUMBER version.env 2>/dev/null | cut -d= -f2 || echo 0) + 1 ))
  echo "VERSION=$VERSION" > version.env
  echo "BUILD_NUMBER=$BUILD_NUMBER" >> version.env
else
  VERSION=$(grep VERSION version.env 2>/dev/null | cut -d= -f2 || echo "1.0.0")
fi

echo ""
echo "  ╔══════════════════════════════╗"
echo "  ║   Appify Release v$VERSION"
echo "  ╚══════════════════════════════╝"
echo ""

bash "$REPO_ROOT/Scripts/package_app.sh"
bash "$REPO_ROOT/Scripts/make_dmg.sh"

DMG_PATH="$REPO_ROOT/dist/Appify-$VERSION.dmg"

echo ""
echo "  Release complete!"
echo "  DMG: $DMG_PATH"
echo ""
echo "  To create a GitHub release:"
echo "    gh release create v$VERSION $DMG_PATH --title \"Appify v$VERSION\" --notes \"See CHANGELOG\""
echo ""
