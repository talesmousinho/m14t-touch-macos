# Lenovo ThinkVision M14t Multi-Touch & Trackpad Driver for macOS (2.0)

> A lightweight, zero-dependency macOS user-space driver that brings a full **tablet + MacBook trackpad gesture experience** to the **Lenovo ThinkVision M14t** over USB-C.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

macOS recognizes the M14t video signal via DisplayPort Alt-Mode, but its built-in Wacom multi-touch digitizer (`VID 0x2D1F`, `PID 0x524C`) either gets ignored or gets mapped by `WindowServer` onto the wrong display (your MacBook's internal screen).

**M14tTouch 2.0** solves both problems from scratch:
1. **Locks exclusively to the M14t display** by auto-detecting its Lenovo EDID (`0x30AE:0x62A3` / `"M14t"`), listening to live display hotplug/rotation events, switching the Wacom sensor into native multi-touch mode (`Feature Report 0x0E`), and blocking `WindowServer` from hijacking touches onto the main screen.
2. **Decodes full 5-finger atomic HID packets (`ReportID 0x0C`) and Active Stylus packets (`ReportID 0x06`)** using the panel's factory coordinate grid (`12372 × 6960` touch, `30931 × 17399` pen) — **no manual corner calibration required**.
3. **Full Tablet & MacBook Trackpad Gestures**:
   - **1-Finger Tap / Double-Tap / Triple-Tap**: Left click, double-click to select word, triple-click to select line/paragraph.
   - **1-Finger Drag**: Natural **text selection**, window dragging, and slider control (or optional *iPad Scroll Mode* where 1 finger scrolls and hold-then-drag selects text).
   - **1-Finger Long Press (~0.5s)**: Right-click (context menu).
   - **2-Finger Tap**: Right-click (secondary click).
   - **2-Finger Pan**: Smooth pixel-accurate 2D trackpad scrolling with inertial momentum.
   - **2-Finger Pinch**: Native macOS trackpad **Pinch-to-Zoom** (`NSEvent.EventType.magnify`) in Safari, Chrome, Preview, Maps, Figma, Xcode, etc.
   - **3 / 4-Finger Swipe Left / Right**: Switch between macOS **Desktops / Full-Screen Spaces**.
   - **3 / 4-Finger Swipe Up**: **Mission Control**.
   - **3 / 4-Finger Swipe Down**: **App Exposé**.
   - **Active Pen / Stylus**: Hover cursor tracking, 4096-level pressure drawing, and barrel-button right-click.

---

## Quick Start

```bash
# Build, install to ~/.local/bin/m14ttouch, and enable background LaunchAgent at login:
./install.sh --autostart
```

Or run manually from the terminal:

```bash
swift build -c release
.build/release/m14ttouch --list   # Verify M14t EDID detection
.build/release/m14ttouch          # Run with automatic M14t display matching
```

### Standalone Settings App & Installer Package

```bash
Scripts/build-app.sh  # creates .build/artifacts/M14tTouch.app
Scripts/build-pkg.sh  # creates .build/artifacts/M14tTouch.pkg
```

---

## Permissions

Grant both permissions once in **System Settings → Privacy & Security**:

| Permission | Purpose | Binary to Authorize |
|---|---|---|
| **Input Monitoring** | Read raw Wacom multi-touch & stylus HID reports | `~/.local/bin/m14ttouch` (or your Terminal app) |
| **Accessibility** | Synthesize clicks, text selection, pinch-zoom, and Desktop switches | `~/.local/bin/m14ttouch` (or your Terminal app) |

If you rebuild and overwrite `~/.local/bin/m14ttouch`, toggle its entry off and back on in **Accessibility** and **Input Monitoring**, then restart the LaunchAgent:

```bash
launchctl kickstart -k "gui/$(id -u)/com.talesfonseca.m14ttouch"
```

---

## CLI Options

```
--display N               Fallback display index if M14t EDID is not found (default: 1)
--no-auto-display         Disable automatic M14t EDID/name detection and force --display N
--mode select|scroll      1-finger drag mode: 'select' (default, text selection & window drag)
                          or 'scroll' (iPad-style 1-finger scroll, hold-then-drag to select)
--no-natural-scroll       Invert 2-finger scroll direction
--no-natural-spaces       Invert 3/4-finger Desktop swipe direction
--no-pinch-zoom           Disable 2-finger pinch-to-zoom
--no-three-finger         Disable 3/4-finger Desktop & Mission Control swipes
--no-long-press           Disable 1-finger long-press right-click
--invert-x / --invert-y   Mirror horizontal or vertical axis
--auto-calibrate          Learn custom raw touch bounds by touching all four corners
--reset-calibration       Delete saved custom calibration and restore 12372×6960 factory bounds
--debug                   Print HID frames and recognized gestures
--list                    List connected displays and exit
--help, -h                Show help
```

---

## Testing

```bash
swift test
```

Covers binary decoding of Wacom `0x0C` multi-touch and `0x06` stylus packets, multi-display coordinate mapping with rotation, and the 1/2/3/4-finger `GestureEngine` state machine.
