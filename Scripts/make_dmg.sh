#!/bin/bash
# Create a distributable DMG from the built Appify.app
# Run AFTER package_app.sh
# Usage: ./Scripts/make_dmg.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=$(grep VERSION version.env 2>/dev/null | cut -d= -f2 || echo "1.0.0")
APP_NAME="Appify"
DIST_DIR="$REPO_ROOT/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="Appify-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TMP_DMG="$DIST_DIR/tmp_$DMG_NAME"
VOLUME_NAME="Appify $VERSION"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH not found. Run ./Scripts/package_app.sh first."
  exit 1
fi

echo ""
echo "  DMG Builder"
echo "  ----------------------------"
echo "  App    : $APP_PATH"
echo "  Output : $DMG_PATH"
echo ""

# Cleanup old
rm -f "$DMG_PATH" "$TMP_DMG"

# ── Step 1: Writable staging DMG ────────────────────────────────────────────
echo "  [1/4] Creating staging DMG..."
hdiutil create \
  -srcfolder "$APP_PATH" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,b=16" \
  -format UDRW \
  -size 60m \
  "$TMP_DMG" > /dev/null

# ── Step 2: Mount and configure layout ───────────────────────────────────────
echo "  [2/4] Configuring DMG layout..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | \
         egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT="/Volumes/$VOLUME_NAME"

sleep 2  # let Finder catch up

# Add symlink to /Applications
ln -sf /Applications "$MOUNT/Applications"

# Set icon positions and window layout via AppleScript
echo '   tell application "Finder"
     tell disk "'"$VOLUME_NAME"'"
       open
       set current view of container window to icon view
       set toolbar visible of container window to false
       set statusbar visible of container window to false
       set bounds of container window to {400, 100, 900, 440}
       set viewOptions to the icon view options of container window
       set arrangement of viewOptions to not arranged
       set icon size of viewOptions to 128
       set position of item "Appify.app" of container window to {130, 170}
       set position of item "Applications" of container window to {370, 170}
       close
       open
       update without registering applications
       delay 2
     end tell
   end tell' | osascript

# Hide background & DS_Store artifacts
SetFile -a V "$MOUNT/.DS_Store" 2>/dev/null || true

sync
hdiutil detach "$DEVICE" > /dev/null

# ── Step 3: Convert to compressed read-only DMG ───────────────────────────────
echo "  [3/4] Compressing DMG..."
hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" > /dev/null
rm -f "$TMP_DMG"

# ── Step 4: Summary ───────────────────────────────────────────────────────────
SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo "  [4/4] Done."
echo ""
echo "  ✓ $DMG_NAME ($SIZE)"
echo "  Path: $DMG_PATH"
echo ""
echo "  Next steps:"
echo "    1. Test: open $DMG_PATH"
if command -v codesign &>/dev/null; then
  echo "    2. Sign:  codesign --deep --sign \"Developer ID Application: YOUR NAME\" $APP_PATH"
  echo "    3. Notarize: xcrun notarytool submit $DMG_PATH --apple-id YOU@EMAIL --team-id TEAMID --wait"
fi
