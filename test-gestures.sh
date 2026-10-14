#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/m14ttouch-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/M14tTouch/Calibration.swift Sources/M14tTouch/CoordinateMapper.swift \
    Sources/M14tTouch/TouchGestures.swift Sources/M14tTouch/M14tReport.swift \
    Sources/M14tTouch/DisplayResolver.swift Sources/M14tTouch/TouchConfig.swift Sources/M14tTouch/ArgumentParser.swift \
    Tests/GestureReplay/Checks.swift Tests/GestureReplay/main.swift -o "$TEST_DIR/gesture-tests"
"$TEST_DIR/gesture-tests"
