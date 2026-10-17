# Lenovo ThinkVision M14t Multi-Touch, Smart Pencil & Trackpad Driver for macOS (2.1)

> A lightweight, zero-dependency macOS user-space driver that brings a full **tablet + Smart Pencil + MacBook trackpad gesture experience + HiDPI display scaling** to the **Lenovo ThinkVision M14t** over USB-C.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

macOS recognizes the M14t video signal via DisplayPort Alt-Mode, but its built-in Wacom multi-touch & Smart Pencil digitizer (`VID 0x2D1F`, `PID 0x524C`) either gets ignored or gets mapped by `WindowServer` onto the wrong display (your MacBook's internal screen).

**M14tTouch 2.1** solves this end-to-end:
1. **Locks exclusively to the M14t display** by auto-detecting its Lenovo EDID (`0x30AE:0x62A3` / `"M14t"`), listening to live display hotplug/rotation/resolution events, and mapping touch + pen coordinates directly to the M14t bounds.
2. **M14t Display Resolution & 75Hz Retina HiDPI Switcher**: Unlocks hidden macOS WindowServer 2x Retina modes and high-frequency 75Hz refresh rate:
   - `1920×1080 @ 75Hz` (2x Retina 4K `3840×2160` framebuffer — Ultra-smooth 75Hz, eliminates scrolling blur/shadowing)
   - `1600×900 @ 60Hz` (2x Retina QHD+ `3200×1800` framebuffer — Balanced 16:9 desktop UI)
   - `1344×756 @ 60Hz` (2x Retina 2.6K `2688×1512` framebuffer — Comfortable 16:9 UI)
   - `1280×720 @ 60Hz` (2x Retina 2.5K `2560×1440` framebuffer — Large 16:9 UI)
   - Native 1x 1080p modes (`1920×1080 @ 75Hz` and `60Hz`).
3. **Ghosting & Shadowing Elimination**:
   - High-frequency 75Hz mode reduces frame hold time from 16.7ms to 13.3ms.
   - Driver high-frequency 125Hz (8ms tick) subpixel inertial scroll engine eliminates micro-stutter.
   - Hardware tip: Set M14t OSD menu **Overdrive** to **Normal** (avoid *Extreme* which creates white ghost coronas, or *Off* which causes IPS pixel trail smearing).
4. **Full Smart Pencil (Lenovo Active Pen) Support (`ReportID 0x06` / `0x0B`)**:
   - **Hover & 4096-Level Pressure + X/Y Tilt (`-90°…+90°`)**: Native macOS `CGEvent` tablet pointer & proximity synthesis for Preview, Freeform, Photoshop, Illustrator, Concepts, and Blender.
   - **Both Side Barrel Buttons Configurable**:
     - **Bottom Barrel Button (`0x44`)**: Default **Right-Click / Context Drag** (configurable to Eraser, Middle-Click, Double-Click, Undo `⌘Z`, or Disabled).
     - **Top Barrel Button (`0x5A` / `0x45` / `0x3C`)**: Default **Native Tablet Eraser** (`NSPointingDeviceType.eraser` — auto-switches drawing/PDF apps to the Eraser tool while held; configurable to Right-Click, Middle-Click, Double-Click, Undo `⌘Z`, or Disabled).
   - **Hardware Palm Rejection**: Automatically ignores finger multi-touch contacts while the Smart Pencil is hovering in range (`InRange = true`) so you can rest your hand on the glass while writing.
4. **Full Tablet & MacBook Trackpad Gestures (`ReportID 0x0C`)**:
   - **1-Finger Tap / Double-Tap / Triple-Tap**: Left click, double-click to select word, triple-click to select line/paragraph.
   - **1-Finger Drag**: Natural **text selection**, window dragging, and slider control (or optional *iPad Scroll Mode* where 1 finger scrolls and hold-then-drag selects text).
   - **1-Finger Long Press (~0.5s)**: Right-click (context menu).
   - **2-Finger Tap**: Right-click (secondary click).
   - **2-Finger Pan**: Smooth pixel-accurate 2D trackpad scrolling with inertial momentum.
   - **2-Finger Pinch**: Native macOS trackpad **Pinch-to-Zoom** (`NSEvent.EventType.magnify`) in Safari, Chrome, Preview, Maps, Figma, Xcode, etc.
   - **3 / 4-Finger Swipe Left / Right**: Switch between macOS **Desktops / Full-Screen Spaces**.
   - **3 / 4-Finger Swipe Up**: **Mission Control**.
   - **3 / 4-Finger Swipe Down**: **App Exposé**.
5. **Auto-Return Pointer to Main Display**:
   - When enabled, touching the external display and moving the mouse pointer there will automatically snap the pointer back to the main display (restoring the previous position) as soon as the user touches their trackpad or mouse, eliminating tedious cross-screen cursor dragging.

---

## Quick Start

```bash
# Build, install to ~/.local/bin/m14ttouch, and enable background LaunchAgent at login:
./install.sh --autostart
```

Or run manually from the terminal:

```bash
swift build -c release
.build/release/m14ttouch --list                          # Verify M14t EDID & HiDPI status
.build/release/m14ttouch --list-modes                    # List all M14t display modes
.build/release/m14ttouch --set-resolution 1024x576-hidpi # Switch M14t to 2x Retina HiDPI
.build/release/m14ttouch                                 # Run driver
```

### Standalone Settings App, Installer Package & Release DMG

```bash
Scripts/build-app.sh  # creates .build/artifacts/M14tTouch.app
Scripts/build-pkg.sh  # creates .build/artifacts/M14tTouch.pkg
Scripts/build-dmg.sh  # creates .build/artifacts/M14tTouch-2.1.0.dmg
```

---

## Permissions

Grant both permissions once in **System Settings → Privacy & Security**:

| Permission | Purpose | Binary to Authorize |
|---|---|---|
| **Input Monitoring** | Read raw Wacom multi-touch & Smart Pencil HID reports | `~/.local/bin/m14ttouch` (or your Terminal app) |
| **Accessibility** | Synthesize clicks, tablet pen/eraser events, pinch-zoom, and Desktop switches | `~/.local/bin/m14ttouch` (or your Terminal app) |

If you rebuild and overwrite `~/.local/bin/m14ttouch`, toggle its entry off and back on in **Accessibility** and **Input Monitoring**, then restart the LaunchAgent:

```bash
launchctl kickstart -k "gui/$(id -u)/com.talesfonseca.m14ttouch"
```

---

## CLI Options

```
DISPLAY & RESOLUTION OPTIONS:
  --display N               Fallback display index if M14t EDID is not found (default: 1)
  --no-auto-display         Disable automatic M14t EDID/name detection and force --display N
  --resolution PRESET       Apply M14t display mode on startup:
                              1920x1080-75hz-hidpi (2x Retina 4K @ 75Hz — Recommended, ultra smooth)
                              1920x1080-60hz-hidpi (2x Retina 4K @ 60Hz — Crisp Full HD)
                              1600x900-hidpi       (2x Retina QHD+ @ 60Hz — Balanced 16:9 UI)
                              1344x756-hidpi       (2x Retina 2.6K @ 60Hz — Comfortable 16:9 UI)
                              1280x720-hidpi       (2x Retina 2.5K @ 60Hz — Large 16:9 UI)
                              1024x576-hidpi       (2x Retina 2K @ 60Hz)
                              960x540-hidpi        (2x Native Retina 1080p @ 60Hz)
                              1920x1080-75hz       (1x Native Full HD @ 75Hz — Max workspace)
                              1920x1080            (1x Native Full HD @ 60Hz)
                              system               (Keep macOS System Setting)
  --set-resolution PRESET   Immediately switch M14t display resolution to PRESET and exit
  --list                    List connected displays (with HiDPI status) and exit
  --list-modes              List all available display modes for the M14t and exit

SMART PENCIL (ACTIVE STYLUS) OPTIONS:
  --barrel-button ACTION    Bottom pen button: right (default), eraser, middle, double, undo, none
  --top-button ACTION       Top pen button: eraser (default), right, middle, double, undo, none
  --no-palm-rejection       Allow finger touch gestures while the Smart Pencil is hovering

TOUCH & TRACKPAD OPTIONS:
  --mode select|scroll      1-finger drag mode: 'select' (default, text selection & window drag)
                            or 'scroll' (iPad-style 1-finger scroll, hold-then-drag to select)
  --auto-return-cursor      Return pointer to main display when trackpad/mouse is used after touch
  --no-auto-return-cursor   Keep pointer on external display after touch
  --no-natural-scroll       Invert 2-finger scroll direction
  --no-natural-spaces       Invert 3/4-finger Desktop swipe direction
  --no-pinch-zoom           Disable 2-finger pinch-to-zoom
  --no-three-finger         Disable 3/4-finger Desktop & Mission Control swipes
  --no-long-press           Disable 1-finger long-press right-click
  --invert-x / --invert-y   Mirror horizontal or vertical axis
  --auto-calibrate          Learn custom raw touch bounds by touching all four corners
  --reset-calibration       Delete saved custom calibration and restore 12372×6960 factory bounds
  --debug                   Print HID frames, Smart Pencil samples, and recognized gestures
  --help, -h                Show help
```

---

## Testing

```bash
swift test
```

Covers binary decoding of Wacom `0x0C` multi-touch and `0x06`/`0x0B` Smart Pencil packets (including both barrel buttons and X/Y tilt), multi-display coordinate mapping with rotation, and the 1/2/3/4-finger + Smart Pencil `GestureEngine` state machine.
