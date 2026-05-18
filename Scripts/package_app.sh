#!/bin/bash
# Package the appify binary itself into a .app for distribution
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(grep VERSION version.env | cut -d= -f2)
BUILD_NUMBER=$(grep BUILD_NUMBER version.env | cut -d= -f2)

APP_NAME="Appify"
OUTPUT_DIR="$REPO_ROOT/dist"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release binary..."
swift build -c release

BINARY=".build/release/Appify"

echo "Assembling .app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/$APP_NAME"
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
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"

echo ""
echo "✓ Packaged: $APP_PATH"
echo "Install binary globally:"
echo "  sudo cp $MACOS/$APP_NAME /usr/local/bin/appify"
