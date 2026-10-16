#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/.build/artifacts}"
PAYLOAD_DIR="$DIST_DIR/pkg-root"
APP_PATH="$DIST_DIR/M14tTouch.app"
PKG_COMPONENT="$DIST_DIR/M14tTouch-component.pkg"
COMPONENT_PLIST="$DIST_DIR/M14tTouch-component.plist"
PKG_OUTPUT="${PKG_OUTPUT:-$DIST_DIR/M14tTouch.pkg}"
APP_ID="${APP_ID:-com.talesfonseca.M14tTouch}"
APP_VERSION="${APP_VERSION:-1.0.0}"

APP_PATH="$("$ROOT/Scripts/build-app.sh" | tail -n 1)"

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR/Applications"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Applications/M14tTouch.app"

pkgbuild --analyze --root "$PAYLOAD_DIR" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"

PKGBUILD_ARGS=(
    --root "$PAYLOAD_DIR"
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

productbuild "${PRODUCTBUILD_ARGS[@]}" "$PKG_OUTPUT" >/dev/null

echo "$PKG_OUTPUT"
