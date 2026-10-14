#!/usr/bin/env bash
#
# install.sh — build m14ttouch, calibrate, and optionally register a login launch agent.
#
# Usage:
#   ./install.sh              # build release binary and calibrate
#   ./install.sh --autostart  # build, calibrate, and install a LaunchAgent
#
set -euo pipefail

DISPLAY_INDEX="${DISPLAY_INDEX:-1}"
LABEL="com.talesfonseca.m14ttouch"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BINARY="$INSTALL_DIR/m14ttouch"
AUTOSTART=false
BINARY_UPDATED=false
TWO_FINGER_SCROLL=false
SKIP_CALIBRATION=false

if ! [[ "$DISPLAY_INDEX" =~ ^[0-9]+$ ]]; then
    echo "❌ DISPLAY_INDEX must be a non-negative integer, got: '$DISPLAY_INDEX'" >&2
    exit 1
fi

usage() {
    cat <<EOF
Usage:
  ./install.sh              Build and calibrate display index ${DISPLAY_INDEX}
  ./install.sh --autostart  Build, calibrate, and run automatically at login
  Add --two-finger-scroll   Enable Gen 1 two-finger scrolling
  Add --skip-calibration    Keep existing ~/.m14ttouch.json

Set DISPLAY_INDEX=N to target a different display.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --autostart)
            AUTOSTART=true
            ;;
        --two-finger-scroll)
            TWO_FINGER_SCROLL=true
            ;;
        --skip-calibration)
            SKIP_CALIBRATION=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$SKIP_CALIBRATION" == true && ! -s "$HOME/.m14ttouch.json" ]]; then
    echo "❌ No saved calibration; run without --skip-calibration first." >&2
    exit 1
fi
SCROLL_ARGUMENT_XML=""
if [[ "$TWO_FINGER_SCROLL" == true ]]; then
    SCROLL_ARGUMENT_XML="        <string>--two-finger-scroll</string>"
fi

calibration_pid=""

cleanup_calibration() {
    local pid="$calibration_pid"
    calibration_pid=""

    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    kill -TERM "$pid" 2>/dev/null || true

    for _ in {1..30}; do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
    fi

    wait "$pid" 2>/dev/null || true
}

trap cleanup_calibration EXIT
trap 'cleanup_calibration; exit 130' INT
trap 'cleanup_calibration; exit 143' TERM

calibrate() {
    echo ""
    echo "🎯 Calibrating display index ${DISPLAY_INDEX}…"
    echo "   Touch all four corners firmly. When the cursor mapping looks right, press Enter here."
    echo "   If macOS asks for Accessibility or Input Monitoring, grant it and rerun this installer."
    echo ""

    "$BINARY" "${DRIVER_ARGS[@]}" --auto-calibrate </dev/null &
    calibration_pid="$!"

    read -r -p "Press Enter when calibration is done… "

    cleanup_calibration
    echo "✅ Calibration stopped. Saved calibration: $HOME/.m14ttouch.json"
}

echo "🔨 Building release binary…"
swift build -c release

# Resolve the current index before stopping a working agent. Persist identity,
# since indices change when the main display or connection order changes.
BUILD_BINARY="$(pwd)/.build/release/m14ttouch"
DISPLAY_UUID="$("$BUILD_BINARY" --display "$DISPLAY_INDEX" --print-display-uuid)"
DRIVER_ARGS=(--display-uuid "$DISPLAY_UUID")
if [[ "$TWO_FINGER_SCROLL" == true ]]; then
    DRIVER_ARGS+=(--two-finger-scroll)
fi

# Do not run the old login agent alongside the calibration process.
if [[ "$AUTOSTART" == true ]]; then
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
fi

mkdir -p "$INSTALL_DIR"
if [[ -f "$INSTALL_BINARY" ]] && cmp -s "$BUILD_BINARY" "$INSTALL_BINARY"; then
    chmod +x "$INSTALL_BINARY"
else
    cp "$BUILD_BINARY" "$INSTALL_BINARY"
    chmod +x "$INSTALL_BINARY"
    BINARY_UPDATED=true
fi
BINARY="$INSTALL_BINARY"
echo "✅ Installed: $BINARY"

if [[ "$SKIP_CALIBRATION" == true ]]; then
    echo "✅ Keeping saved calibration: $HOME/.m14ttouch.json"
else
    calibrate
fi

if [[ "$AUTOSTART" == true ]]; then
    echo "📝 Installing LaunchAgent for display index ${DISPLAY_INDEX}…"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY}</string>
        <string>--display-uuid</string>
        <string>${DISPLAY_UUID}</string>
${SCROLL_ARGUMENT_XML}
        <string>--no-accessibility-prompt</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardInPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/tmp/m14ttouch.err.log</string>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
</dict>
</plist>
EOF
    plutil -lint "$PLIST" >/dev/null
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true
    echo "✅ Autostart enabled. Background stdout is discarded; errors: /tmp/m14ttouch.err.log"
    if [[ "$BINARY_UPDATED" == true ]]; then
        echo "   The installed binary was updated; macOS may require re-adding Accessibility for: $BINARY"
    fi
    echo "   If it does not stay running, remove any old m14ttouch Accessibility entry, add: $BINARY"
    echo "   Then restart it without rebuilding: launchctl kickstart -k gui/$(id -u)/$LABEL"
    echo "   To disable: launchctl bootout gui/$(id -u) $PLIST && rm $PLIST"
else
    echo ""
    echo "Run it with:"
    echo "  $BINARY ${DRIVER_ARGS[*]}"
    echo ""
    echo "Or enable autostart with:"
    echo "  ./install.sh --autostart"
fi
