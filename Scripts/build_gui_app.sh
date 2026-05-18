#!/bin/bash
# Build Appify.app — a real double-click macOS app that wraps AppifyGUI
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/version.env"

ARCH_ARM="$ROOT/.build/arm64-apple-macosx/release/AppifyGUI"
ARCH_X86="$ROOT/.build/x86_64-apple-macosx/release/AppifyGUI"
LAUNCHER_ARM="$ROOT/.build/arm64-apple-macosx/release/Launcher"
LAUNCHER_X86="$ROOT/.build/x86_64-apple-macosx/release/Launcher"
DIST="$ROOT/dist"
APP="$DIST/Appify.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "===> Building AppifyGUI (arm64 + x86_64)..."
cd "$ROOT"
swift build -c release --arch arm64   --product AppifyGUI
swift build -c release --arch x86_64  --product AppifyGUI
swift build -c release --arch arm64   --product Launcher
swift build -c release --arch x86_64  --product Launcher

echo "===> Assembling universal binaries..."
mkdir -p "$MACOS" "$RES"

lipo -create -output "$MACOS/AppifyGUI" "$ARCH_ARM" "$ARCH_X86"
lipo -create -output "$MACOS/Launcher"  "$LAUNCHER_ARM" "$LAUNCHER_X86"
chmod +x "$MACOS/AppifyGUI" "$MACOS/Launcher"

echo "===> Writing Info.plist..."
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>           <string>Appify</string>
    <key>CFBundleDisplayName</key>    <string>Appify</string>
    <key>CFBundleExecutable</key>     <string>AppifyGUI</string>
    <key>CFBundleIdentifier</key>     <string>com.djozman.appify</string>
    <key>CFBundleVersion</key>        <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundlePackageType</key>    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSMinimumSystemVersion</key> <string>13.0</string>
    <key>NSPrincipalClass</key>       <string>NSApplication</string>
    <key>CFBundleIconFile</key>       <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

# Copy bundled Launcher so GUI can embed it into created apps
cp "$MACOS/Launcher" "$RES/Launcher"

echo "===> Copying app icon..."
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$RES/AppIcon.icns"
else
    echo "  [warning] No Assets/AppIcon.icns found — app will use default icon"
fi

echo "===> Creating DMG..."
DMG_PATH="$DIST/Appify-${VERSION}.dmg"
hdiutil create -volname "Appify" \
    -srcfolder "$APP" \
    -ov -format UDZO \
    -o "$DMG_PATH"

echo ""
echo "Done!"
echo "  App : $APP"
echo "  DMG : $DMG_PATH"
echo ""
echo "Double-click to test: open \"$APP\""
