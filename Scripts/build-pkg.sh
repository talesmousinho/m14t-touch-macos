#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/.build/artifacts}"
PAYLOAD_DIR="$DIST_DIR/pkg-root"
SCRIPTS_DIR="$DIST_DIR/pkg-scripts"
APP_PATH="$DIST_DIR/M14tTouch.app"
PKG_COMPONENT="$DIST_DIR/M14tTouch-component.pkg"
COMPONENT_PLIST="$DIST_DIR/M14tTouch-component.plist"
PKG_OUTPUT="${PKG_OUTPUT:-$DIST_DIR/M14tTouch-Installer.pkg}"
APP_ID="${APP_ID:-com.talesfonseca.M14tTouch}"
APP_VERSION="${APP_VERSION:-2.1.0}"

APP_PATH="$("$ROOT/Scripts/build-app.sh" | tail -n 1)"
HELPER_BIN="$APP_PATH/Contents/Resources/m14ttouch"

rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$PKG_COMPONENT" "$COMPONENT_PLIST"
mkdir -p "$PAYLOAD_DIR/Applications" "$PAYLOAD_DIR/usr/local/bin" "$SCRIPTS_DIR"

# 1. Companion App (/Applications/M14tTouch.app)
cp -R "$APP_PATH" "$PAYLOAD_DIR/Applications/M14tTouch.app"

# 2. Binary Driver (/usr/local/bin/m14ttouch)
cp "$HELPER_BIN" "$PAYLOAD_DIR/usr/local/bin/m14ttouch"
chmod 755 "$PAYLOAD_DIR/usr/local/bin/m14ttouch"

# 3. Postinstall script to also install ~/.local/bin/m14ttouch for the logged-in user
cat > "$SCRIPTS_DIR/postinstall" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HELPER_SRC="/Applications/M14tTouch.app/Contents/Resources/m14ttouch"

CONSOLE_USER="${SUDO_USER:-}"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" ]]; then
    CONSOLE_USER="$(stat -f "%Su" /dev/console 2>/dev/null || true)"
fi

if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" && "$CONSOLE_USER" != "loginwindow" && "$CONSOLE_USER" != "_mbsetupuser" ]]; then
    USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}' || true)"
    if [[ -n "$USER_HOME" && -d "$USER_HOME" && -f "$HELPER_SRC" ]]; then
        LOCAL_BIN="$USER_HOME/.local/bin"
        mkdir -p "$LOCAL_BIN"
        cp -f "$HELPER_SRC" "$LOCAL_BIN/m14ttouch"
        chmod 755 "$LOCAL_BIN/m14ttouch"
        chown "$CONSOLE_USER:staff" "$USER_HOME/.local" "$LOCAL_BIN" "$LOCAL_BIN/m14ttouch" 2>/dev/null || true
        xattr -cr "$LOCAL_BIN/m14ttouch" 2>/dev/null || true
    fi
fi

xattr -cr "/Applications/M14tTouch.app" "/usr/local/bin/m14ttouch" 2>/dev/null || true
exit 0
EOF
chmod 755 "$SCRIPTS_DIR/postinstall"

pkgbuild --analyze --root "$PAYLOAD_DIR" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$COMPONENT_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"

PKGBUILD_ARGS=(
    --root "$PAYLOAD_DIR"
    --scripts "$SCRIPTS_DIR"
    --component-plist "$COMPONENT_PLIST"
    --identifier "$APP_ID"
    --version "$APP_VERSION"
    --install-location "/"
)

if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
    PKGBUILD_ARGS+=(--sign "$DEVELOPER_ID_INSTALLER")
fi

pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_COMPONENT" >/dev/null

PRODUCTBUILD_ARGS=(
    --package "$PKG_COMPONENT"
)

if [[ -n "${DEVELOPER_ID_INSTALLER:-}" ]]; then
    PRODUCTBUILD_ARGS+=(--sign "$DEVELOPER_ID_INSTALLER")
fi

rm -f "$PKG_OUTPUT"
productbuild "${PRODUCTBUILD_ARGS[@]}" "$PKG_OUTPUT" >/dev/null

rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$PKG_COMPONENT" "$COMPONENT_PLIST"

echo "$PKG_OUTPUT"
