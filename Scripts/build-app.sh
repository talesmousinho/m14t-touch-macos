#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
BUILD_DIR="$ROOT/.build/$CONFIGURATION"
DIST_DIR="${DIST_DIR:-$ROOT/.build/artifacts}"
APP="$DIST_DIR/M14tTouch.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_EXECUTABLE="$MACOS/M14tTouch"
HELPER_EXECUTABLE="$RESOURCES/m14ttouch"
APP_ID="${APP_ID:-com.talesfonseca.M14tTouch}"
APP_VERSION="${APP_VERSION:-2.1.0}"
APP_BUILD="${APP_BUILD:-210}"

swift build -c "$CONFIGURATION" --product M14tTouchApp
swift build -c "$CONFIGURATION" --product m14ttouch

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/M14tTouchApp" "$APP_EXECUTABLE"
cp "$BUILD_DIR/m14ttouch" "$HELPER_EXECUTABLE"
chmod +x "$APP_EXECUTABLE" "$HELPER_EXECUTABLE"

if [[ -f "$ROOT/Assets/M14tTouch.icns" ]]; then
    cp "$ROOT/Assets/M14tTouch.icns" "$RESOURCES/M14tTouch.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>M14tTouch</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>M14tTouch</string>
    <key>CFBundleDisplayName</key>
    <string>M14tTouch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
PLIST

if [[ -f "$RESOURCES/M14tTouch.icns" ]]; then
    cat >> "$CONTENTS/Info.plist" <<PLIST
    <key>CFBundleIconFile</key>
    <string>M14tTouch</string>
PLIST
fi

cat >> "$CONTENTS/Info.plist" <<PLIST
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist" >/dev/null

if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$HELPER_EXECUTABLE"
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP"
else
    codesign --force --sign - --identifier "com.talesfonseca.m14ttouch" "$HELPER_EXECUTABLE" >/dev/null
    codesign --force --sign - "$APP" >/dev/null
fi

xattr -cr "$APP"

echo "$APP"
