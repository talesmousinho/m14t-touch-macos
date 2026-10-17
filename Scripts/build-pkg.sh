#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR="$ROOT/.build/$CONFIGURATION"
DIST_DIR="${DIST_DIR:-$ROOT/.build/artifacts}"
PAYLOAD_DIR="$DIST_DIR/pkg-root"
SCRIPTS_DIR="$DIST_DIR/pkg-scripts"
PKG_COMPONENT="$DIST_DIR/m14ttouch-driver-component.pkg"
PKG_OUTPUT="${PKG_OUTPUT:-$DIST_DIR/M14tTouch-Driver.pkg}"
DRIVER_ID="${DRIVER_ID:-com.talesfonseca.m14ttouch.driver}"
APP_VERSION="${APP_VERSION:-2.1.0}"

swift build -c "$CONFIGURATION" --product m14ttouch
HELPER_BIN="$BUILD_DIR/m14ttouch"

rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$PKG_COMPONENT"
mkdir -p "$PAYLOAD_DIR/usr/local/bin" "$SCRIPTS_DIR"

# Binary Driver Only (/usr/local/bin/m14ttouch)
cp "$HELPER_BIN" "$PAYLOAD_DIR/usr/local/bin/m14ttouch"
chmod 755 "$PAYLOAD_DIR/usr/local/bin/m14ttouch"

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$PAYLOAD_DIR/usr/local/bin/m14ttouch"
else
    codesign --force --sign - --identifier "com.talesfonseca.m14ttouch" "$PAYLOAD_DIR/usr/local/bin/m14ttouch" >/dev/null
fi

xattr -cr "$PAYLOAD_DIR" 2>/dev/null || true
find "$PAYLOAD_DIR" -name '._*' -delete 2>/dev/null || true

# Postinstall script to also install ~/.local/bin/m14ttouch for the logged-in user
cat > "$SCRIPTS_DIR/postinstall" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

HELPER_SRC="/usr/local/bin/m14ttouch"

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

xattr -cr "/usr/local/bin/m14ttouch" 2>/dev/null || true
exit 0
EOF
chmod 755 "$SCRIPTS_DIR/postinstall"

PKGBUILD_ARGS=(
    --root "$PAYLOAD_DIR"
    --scripts "$SCRIPTS_DIR"
    --identifier "$DRIVER_ID"
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

rm -rf "$PAYLOAD_DIR" "$SCRIPTS_DIR" "$PKG_COMPONENT"

echo "$PKG_OUTPUT"
