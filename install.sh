#!/usr/bin/env bash
#
# install.sh — build m14ttouch 2.0, install to ~/.local/bin/m14ttouch, and optionally register LaunchAgent.
#
# Usage:
#   ./install.sh              # build and install release binary (uses factory 12372×6960 M14t calibration)
#   ./install.sh --autostart  # build, install, and enable LaunchAgent at login
#   ./install.sh --calibrate  # also run interactive 4-corner custom calibration
#
set -euo pipefail

DISPLAY_INDEX="${DISPLAY_INDEX:-1}"
LABEL="com.talesfonseca.m14ttouch"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_BINARY="$INSTALL_DIR/m14ttouch"
AUTOSTART=false
CALIBRATE=false
BINARY_UPDATED=false

if ! [[ "$DISPLAY_INDEX" =~ ^[0-9]+$ ]]; then
    echo "❌ DISPLAY_INDEX must be a non-negative integer, got: '$DISPLAY_INDEX'" >&2
    exit 1
fi

usage() {
    cat <<EOF
Usage:
  ./install.sh              Build and install m14ttouch 2.0 (auto-detects M14t display & factory bounds)
  ./install.sh --autostart  Build, install, and run automatically at login via LaunchAgent
  ./install.sh --calibrate  Run interactive 4-corner calibration after building
EOF
}

for arg in "$@"; do
    case "$arg" in
        --autostart)
            AUTOSTART=true
            ;;
        --calibrate)
            CALIBRATE=true
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
    echo "🎯 Calibrating M14t touch panel…"
    echo "   Touch all four corners firmly. When the cursor mapping looks right, press Enter here."
    echo ""

    "$BINARY" --display "$DISPLAY_INDEX" --auto-calibrate </dev/null &
    calibration_pid="$!"

    read -r -p "Press Enter when calibration is done… "

    cleanup_calibration
    echo "✅ Calibration stopped. Saved calibration: $HOME/.m14ttouch.json"
}

echo "🔨 Building m14ttouch 2.0 release binary…"
swift build -c release

BUILD_BINARY="$(pwd)/.build/release/m14ttouch"
mkdir -p "$INSTALL_DIR"
if [[ -f "$INSTALL_BINARY" ]] && cmp -s "$BUILD_BINARY" "$INSTALL_BINARY"; then
    chmod +x "$INSTALL_BINARY"
else
    rm -f "$INSTALL_BINARY"
    cp "$BUILD_BINARY" "$INSTALL_BINARY"
    chmod +x "$INSTALL_BINARY"
    codesign --force --sign - --identifier "com.talesfonseca.m14ttouch" "$INSTALL_BINARY" >/dev/null 2>&1 || true
    BINARY_UPDATED=true
fi
BINARY="$INSTALL_BINARY"
echo "✅ Installed: $BINARY"

if [[ "$CALIBRATE" == true ]]; then
    calibrate
fi

if [[ "$AUTOSTART" == true ]]; then
    echo "📝 Installing LaunchAgent…"
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
        <string>--display</string>
        <string>${DISPLAY_INDEX}</string>
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
    <string>/tmp/m14ttouch.out.log</string>
</dict>
</plist>
EOF
    plutil -lint "$PLIST" >/dev/null
    launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true
    echo "✅ Autostart enabled (logs: /tmp/m14ttouch.out.log, /tmp/m14ttouch.err.log)"
    if [[ "$BINARY_UPDATED" == true ]]; then
        echo "   Note: If cursor movement is blocked after updating the binary, toggle Accessibility & Input Monitoring off/on for: $BINARY"
    fi
else
    echo ""
    echo "Run it with:"
    echo "  $BINARY"
    echo ""
    echo "Or enable autostart with:"
    echo "  ./install.sh --autostart"
fi
