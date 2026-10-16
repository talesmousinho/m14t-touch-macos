#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/.build/artifacts}"
APP_VERSION="${APP_VERSION:-2.1.0}"
DMG_OUTPUT="${DMG_OUTPUT:-$DIST_DIR/M14tTouch-${APP_VERSION}.dmg}"
STAGING_DIR="$DIST_DIR/dmg-root"

echo "==> Building M14tTouch.app (v${APP_VERSION})..."
APP_PATH="$("$ROOT/Scripts/build-app.sh" | tail -n 1)"

echo "==> Building M14tTouch.pkg installer..."
PKG_PATH="$("$ROOT/Scripts/build-pkg.sh" | tail -n 1)"

echo "==> Preparing DMG staging folder..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 1. Copy Application
cp -R "$APP_PATH" "$STAGING_DIR/M14tTouch.app"

# 2. Add /Applications symlink for drag-and-drop install
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Include PKG installer
cp "$PKG_PATH" "$STAGING_DIR/M14tTouch-Installer.pkg"

# 4. Instructions
cat > "$STAGING_DIR/READ_ME_FIRST.txt" << 'EOF'
Lenovo ThinkVision M14t Multi-Touch, Smart Pencil & HiDPI Driver for macOS (v2.1)
================================================================================

INSTALLATION OPTIONS:
---------------------
Option 1: Drag & Drop
  Drag "M14tTouch.app" into the "Applications" shortcut icon.
  Then launch M14tTouch from your Applications folder.

Option 2: Automated Installer (.pkg)
  Double-click "M14tTouch-Installer.pkg" and follow the installer prompts.

FIRST-TIME SETUP & PERMISSIONS:
-------------------------------
macOS requires two security permissions to read touchscreen HID packets
and synthesize mouse/trackpad events:

1. Open M14tTouch from Applications.
2. Click "Request & Verify Permissions".
3. In macOS System Settings -> Privacy & Security:
   - Enable "Accessibility" for M14tTouch (or ~/.local/bin/m14ttouch).
   - Enable "Input Monitoring" for M14tTouch (or ~/.local/bin/m14ttouch).
4. Click "Enable LaunchAgent" to keep the driver active automatically at login.

KEY FEATURES:
-------------
- 75Hz Retina HiDPI: Unlocks true 2x HiDPI rendering and 75Hz high frequency
  (1920x1080 @ 75Hz Retina 4K framebuffer, eliminating scroll shadowing).
- Smart Pencil Support: 4096 pressure levels, tilt, bottom barrel button
  (Right-Click), top barrel button (Tablet Eraser), and palm rejection.
- MacBook Trackpad Gestures: 1-finger drag selection, 2-finger smooth scroll,
  2-finger pinch-to-zoom, and 3-finger Desktop spaces & Mission Control swipes.

MONITOR OSD TIP:
----------------
Press the hardware button on the side of the M14t, open the on-screen menu,
and ensure "Overdrive" is set to "Normal" for optimal pixel response time.
EOF

# 5. Build DMG with hdiutil
echo "==> Creating disk image: ${DMG_OUTPUT}..."
rm -f "$DMG_OUTPUT"

hdiutil create \
    -volname "M14tTouch v${APP_VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT" >/dev/null

# 6. Sign DMG if signing identity is available
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    codesign --force --sign "$DEVELOPER_ID_APP" "$DMG_OUTPUT" >/dev/null
else
    codesign --force --sign - "$DMG_OUTPUT" >/dev/null 2>&1 || true
fi

# Clean up staging
rm -rf "$STAGING_DIR"

echo "==> DMG created successfully:"
echo "$DMG_OUTPUT"
