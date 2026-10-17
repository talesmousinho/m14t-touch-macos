#!/usr/bin/env bash
#
# install-prebuilt.sh — Download prebuilt M14tTouch.app and m14ttouch binary driver
# via curl (zero Gatekeeper quarantine warnings) and install to:
#   - /Applications/M14tTouch.app
#   - ~/.local/bin/m14ttouch
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/talesmousinho/m14t-touch-macos/main/install-prebuilt.sh | bash
#
set -euo pipefail

APP_VERSION="${APP_VERSION:-2.1.0}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/talesmousinho/m14t-touch-macos/main}"
DMG_URL="${DMG_URL:-${REPO_RAW_BASE}/.build/artifacts/M14tTouch-${APP_VERSION}.dmg}"

APP_DEST="/Applications/M14tTouch.app"
LOCAL_BIN_DIR="$HOME/.local/bin"
LOCAL_BIN_DEST="$LOCAL_BIN_DIR/m14ttouch"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/m14ttouch-install.XXXXXX")"
TMP_DMG="$TMP_DIR/M14tTouch-${APP_VERSION}.dmg"
MOUNT_POINT="$TMP_DIR/mount"

cleanup() {
    if [[ -d "$MOUNT_POINT" ]]; then
        hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> Downloading M14tTouch v${APP_VERSION}..."
curl -fL --progress-bar "$DMG_URL" -o "$TMP_DMG"
xattr -cr "$TMP_DMG" 2>/dev/null || true

echo "==> Mounting disk image..."
mkdir -p "$MOUNT_POINT"
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet

if [[ ! -d "$MOUNT_POINT/M14tTouch.app" ]]; then
    echo "❌ Error: M14tTouch.app not found inside disk image." >&2
    exit 1
fi

echo "==> Installing M14tTouch.app to /Applications..."
if pgrep -x "M14tTouch" >/dev/null 2>&1; then
    killall "M14tTouch" 2>/dev/null || true
    sleep 0.3
fi

if [[ -w "/Applications" ]]; then
    rm -rf "$APP_DEST"
    ditto "$MOUNT_POINT/M14tTouch.app" "$APP_DEST"
    xattr -cr "$APP_DEST" 2>/dev/null || true
else
    sudo rm -rf "$APP_DEST"
    sudo ditto "$MOUNT_POINT/M14tTouch.app" "$APP_DEST"
    sudo xattr -cr "$APP_DEST" 2>/dev/null || true
fi

echo "==> Installing m14ttouch binary driver to ${LOCAL_BIN_DEST}..."
mkdir -p "$LOCAL_BIN_DIR"
HELPER_SRC="$APP_DEST/Contents/Resources/m14ttouch"

if [[ -f "$LOCAL_BIN_DEST" ]] && cmp -s "$HELPER_SRC" "$LOCAL_BIN_DEST"; then
    chmod 755 "$LOCAL_BIN_DEST"
else
    cp -f "$HELPER_SRC" "$LOCAL_BIN_DEST"
    chmod 755 "$LOCAL_BIN_DEST"
fi
xattr -cr "$LOCAL_BIN_DEST" 2>/dev/null || true

echo ""
echo "✅ Installed M14tTouch.app       -> $APP_DEST"
echo "✅ Installed m14ttouch driver    -> $LOCAL_BIN_DEST"
echo ""
echo "==> Launching M14tTouch..."
open "$APP_DEST" || true
