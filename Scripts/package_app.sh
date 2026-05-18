#!/bin/bash
# Build a universal (arm64 + x86_64) binary and package into a .app bundle
# Usage: ./Scripts/package_app.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(grep VERSION version.env 2>/dev/null | cut -d= -f2 || echo "1.0.0")
BUILD_NUMBER=$(grep BUILD_NUMBER version.env 2>/dev/null | cut -d= -f2 || echo "1")

APP_NAME="Appify"
OUTPUT_DIR="$REPO_ROOT/dist"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo ""
echo "  Appify Release Builder"
echo "  Version: $VERSION ($BUILD_NUMBER)"
echo "  --------------------------------"
echo ""

# ── Step 1: Build Launcher for both arches ──────────────────────────────────
echo "  [1/5] Building Launcher (arm64)..."
swift build -c release --product Launcher --arch arm64 2>&1 | tail -2

echo "  [1/5] Building Launcher (x86_64)..."
swift build -c release --product Launcher --arch x86_64 2>&1 | tail -2

echo "  [1/5] Merging Launcher into universal binary..."
lipo -create \
  .build/arm64-apple-macosx/release/Launcher \
  .build/x86_64-apple-macosx/release/Launcher \
  -output .build/Launcher-universal

# ── Step 2: Embed universal Launcher into resources ─────────────────────────
echo "  [2/5] Embedding Launcher into resources..."
mkdir -p Sources/Appify/Resources
cp .build/Launcher-universal Sources/Appify/Resources/Launcher
chmod +x Sources/Appify/Resources/Launcher

# ── Step 3: Build Appify CLI for both arches ─────────────────────────────────
echo "  [3/5] Building Appify CLI (arm64)..."
swift build -c release --product Appify --arch arm64 2>&1 | tail -2

echo "  [3/5] Building Appify CLI (x86_64)..."
swift build -c release --product Appify --arch x86_64 2>&1 | tail -2

echo "  [3/5] Merging Appify CLI into universal binary..."
lipo -create \
  .build/arm64-apple-macosx/release/Appify \
  .build/x86_64-apple-macosx/release/Appify \
  -output .build/Appify-universal

# Verify universal
echo "  Arch check:"
lipo -info .build/Appify-universal

# ── Step 4: Assemble .app bundle ─────────────────────────────────────────────
echo "  [4/5] Assembling .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

cp .build/Appify-universal "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>com.appify.cli</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD_NUMBER</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

# ── App icon ────────────────────────────────────────────────────────────────
if [ -f "$REPO_ROOT/Assets/AppIcon.icns" ]; then
    cp "$REPO_ROOT/Assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "  [4/5] App icon copied"
else
    echo "  [4/5] No Assets/AppIcon.icns found — skipping icon"
fi

echo ""
echo "  ✓ Built: $APP_PATH"
echo ""
