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

echo "==> Building M14tTouch-Driver.pkg (binary driver only)..."
PKG_PATH="$("$ROOT/Scripts/build-pkg.sh" | tail -n 1)"

echo "==> Preparing DMG staging folder..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 1. Copy Application
cp -R "$APP_PATH" "$STAGING_DIR/M14tTouch.app"

# 2. Add /Applications symlink for drag-and-drop install
ln -s /Applications "$STAGING_DIR/Applications"

# 3. Include binary-driver-only PKG installer
cp "$PKG_PATH" "$STAGING_DIR/M14tTouch-Driver.pkg"

# 4. Instructions
cat > "$STAGING_DIR/READ_ME_FIRST.txt" << 'EOF'
Lenovo ThinkVision M14t Multi-Touch, Smart Pencil & HiDPI Driver for macOS (v2.1)
================================================================================

INSTALLATION STEPS:
-------------------
1. Install Companion App:
   Drag "M14tTouch.app" into the "Applications" folder shortcut.

2. Install Binary Driver (Optional / Standalone CLI):
   Opening M14tTouch.app automatically installs the background driver binary to
   ~/.local/bin/m14ttouch. You can also run "M14tTouch-Driver.pkg" to install
   the standalone "m14ttouch" binary to /usr/local/bin/m14ttouch and
   ~/.local/bin/m14ttouch.

3. If macOS Gatekeeper blocks first launch (unidentified developer):
   Right-click (or Control-click) M14tTouch.app -> Open, or run in Terminal:
     xattr -cr /Applications/M14tTouch.app ~/.local/bin/m14ttouch

FIRST-TIME SETUP & PERMISSIONS:
-------------------------------
macOS requires Accessibility and Input Monitoring permissions for the background
helper binary to read the USB digitizer and synthesize gestures:

1. Open M14tTouch from /Applications.
2. In the "Service & Permissions" tab, click "1. Reveal Binary in Finder",
   "2. Open Accessibility Settings", and "3. Open Input Monitoring".
3. Drag the highlighted "m14ttouch" binary into:
   - System Settings -> Privacy & Security -> Accessibility (toggle ON)
   - System Settings -> Privacy & Security -> Input Monitoring (toggle ON)
4. In M14tTouch, toggle "Start driver automatically at macOS login" and click Save.

KEY FEATURES:
-------------
- 75Hz Retina HiDPI: Unlocks true 2x HiDPI rendering and 75Hz high frequency
  (1920x1080 @ 75Hz Retina 4K framebuffer, eliminating scroll shadowing).
- Smart Pencil Support: 4096 pressure levels, tilt, bottom barrel button
  (Right-Click), top barrel button (Tablet Eraser), and palm rejection.
- MacBook Trackpad Gestures: 1-finger drag selection, 2-finger smooth scroll,
  2-finger pinch-to-zoom, and 3/4-finger Desktop spaces & Mission Control swipes.

MONITOR OSD TIP:
----------------
Press the hardware button on the side of the M14t, open the on-screen menu,
and ensure "Overdrive" is set to "Normal" for optimal pixel response time.
EOF

# 5. Build DMG with hdiutil
echo "==> Creating disk image: ${DMG_OUTPUT}..."
xattr -cr "$STAGING_DIR" 2>/dev/null || true
find "$STAGING_DIR" -name '._*' -delete 2>/dev/null || true
rm -f "$DMG_OUTPUT"

hdiutil create \
    -volname "M14tTouch v${APP_VERSION}" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT" >/dev/null

# 6. Sign DMG only if a real Developer ID Application identity is available
# (Never ad-hoc sign a .dmg with `codesign --sign -`; an ad-hoc code directory on a disk image
# causes macOS Gatekeeper / DiskImages-helper to reject mounting the .dmg itself.)
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    codesign --force --sign "$DEVELOPER_ID_APP" "$DMG_OUTPUT" >/dev/null
fi

# Clean up staging
rm -rf "$STAGING_DIR"

echo "==> DMG created successfully:"
echo "$DMG_OUTPUT"
