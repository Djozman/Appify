#!/bin/bash
# Build Appify.app — a real double-click macOS app that wraps AppifyGUI
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/version.env"

LAUNCHER_ARM="$ROOT/.build/arm64-apple-macosx/release/Launcher"
LAUNCHER_X86="$ROOT/.build/x86_64-apple-macosx/release/Launcher"
CORE_RES="$ROOT/Sources/AppifyCore/Resources"
APP="/Applications/Appify.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

# ---- Step 1: Remove old app ----
rm -rf "$APP"

# ---- Step 2: Build Launcher first (both arches) ----
echo "===> Building Launcher (arm64 + x86_64)..."
cd "$ROOT"
swift build -c release --arch arm64  --product Launcher
swift build -c release --arch x86_64 --product Launcher

# ---- Step 3: Embed universal Launcher into AppifyCore/Resources ----
# SPM will bundle it at compile-time so Bundle.module can find it at runtime.
echo "===> Embedding Launcher into AppifyCore/Resources..."
mkdir -p "$CORE_RES"
lipo -create -output "$CORE_RES/Launcher" "$LAUNCHER_ARM" "$LAUNCHER_X86"
chmod +x "$CORE_RES/Launcher"

# ---- Step 4: Build AppifyGUI (Launcher is now in the resource bundle) ----
echo "===> Building AppifyGUI (arm64 + x86_64)..."
swift build -c release --arch arm64  --product AppifyGUI
swift build -c release --arch x86_64 --product AppifyGUI

# ---- Step 5: Assemble Appify.app ----
echo "===> Assembling Appify.app..."
mkdir -p "$MACOS" "$RES"

ARCH_ARM="$ROOT/.build/arm64-apple-macosx/release/AppifyGUI"
ARCH_X86="$ROOT/.build/x86_64-apple-macosx/release/AppifyGUI"
lipo -create -output "$MACOS/AppifyGUI" "$ARCH_ARM" "$ARCH_X86"
chmod +x "$MACOS/AppifyGUI"

# Also place Launcher in Contents/Resources as a fallback for the distributed app
lipo -create -output "$RES/Launcher" "$LAUNCHER_ARM" "$LAUNCHER_X86"
chmod +x "$RES/Launcher"

# ---- Step 6: Info.plist + PkgInfo ----
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

# ---- Step 7: App icon ----
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$RES/AppIcon.icns"
else
    echo "  [warning] No Assets/AppIcon.icns found — app will use default icon"
fi

echo ""
echo "Done!"
echo "  App : $APP"
echo ""
echo "To test: open \"$APP\""
