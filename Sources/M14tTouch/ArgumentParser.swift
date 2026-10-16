import Foundation

/// Parses command-line arguments into a `TouchConfig` (or a control action).
public enum ArgumentParser {

    public enum Outcome: Equatable {
        case run(TouchConfig)
        case listDisplays
        case resetCalibration
        case help
        case error(String)
    }

    public static func parse(_ arguments: [String], defaults: TouchConfig = TouchConfig()) -> Outcome {
        var config = defaults
        var iterator = arguments.makeIterator()

        func nextDouble() -> Double? {
            guard let raw = iterator.next() else { return nil }
            return Double(raw)
        }

        while let arg = iterator.next() {
            switch arg {
            case "--help", "-h":           return .help
            case "--list":                 return .listDisplays
            case "--reset-calibration":    return .resetCalibration

            case "--display":
                guard let raw = iterator.next(), let idx = Int(raw) else {
                    return .error("--display requires an integer")
                }
                config.displayIndex = idx

            case "--no-auto-display":      config.autoDetectM14tDisplay = false
            case "--invert-x":             config.invertX = true
            case "--invert-y":             config.invertY = true
            case "--debug":                config.debugMode = true
            case "--auto-calibrate":       config.autoCalibrate = true
            case "--no-accessibility-prompt": config.promptForAccessibility = false

            case "--mode":
                guard let raw = iterator.next(),
                      let mode = OneFingerMode(rawValue: raw.lowercased()) else {
                    return .error("--mode requires 'select' or 'scroll'")
                }
                config.oneFingerMode = mode

            case "--no-natural-scroll":    config.naturalScrolling = false
            case "--no-natural-spaces":    config.naturalSpacesSwipe = false
            case "--no-pinch-zoom":        config.pinchToZoom = false
            case "--no-three-finger":      config.threeFingerSwipes = false
            case "--no-long-press":        config.longPressRightClick = false

            case "--x-min": guard let v = nextDouble() else { return .error("--x-min requires a number") }; config.manualXMin = v
            case "--x-max": guard let v = nextDouble() else { return .error("--x-max requires a number") }; config.manualXMax = v
            case "--y-min": guard let v = nextDouble() else { return .error("--y-min requires a number") }; config.manualYMin = v
            case "--y-max": guard let v = nextDouble() else { return .error("--y-max requires a number") }; config.manualYMax = v

            default:
                return .error("Unknown option: \(arg)")
            }
        }

        return .run(config)
    }

    public static let usageText = """

    m14ttouch — Multi-touch tablet & trackpad driver for Lenovo ThinkVision M14t on macOS

    USAGE:
      m14ttouch [OPTIONS]

    OPTIONS:
      --display N               Fallback display index if M14t EDID is not found (default: 1)
      --no-auto-display         Disable automatic M14t EDID/name detection and force --display N
      --mode select|scroll      1-finger drag mode: 'select' (default, text selection & window drag)
                                or 'scroll' (iPad-style 1-finger scroll, hold-then-drag to select)
      --no-natural-scroll       Invert 2-finger scroll direction
      --no-natural-spaces       Invert 3/4-finger Desktop swipe direction
      --no-pinch-zoom           Disable 2-finger pinch-to-zoom
      --no-three-finger         Disable 3/4-finger Desktop & Mission Control swipes
      --no-long-press           Disable 1-finger long-press right-click
      --invert-x                Mirror the horizontal axis
      --invert-y                Mirror the vertical axis
      --auto-calibrate          Learn custom raw touch bounds by touching all four corners
      --x-min / --x-max N       Manual raw X bounds override
      --y-min / --y-max N       Manual raw Y bounds override
      --debug                   Print HID frames and recognized gestures
      --no-accessibility-prompt Do not trigger the macOS Accessibility prompt (used by LaunchAgent)
      --list                    List connected displays (highlighting detected M14t) and exit
      --reset-calibration       Delete saved custom calibration and exit
      --help, -h                Show this help and exit

    GESTURES:
      1 Finger Tap              Left click (Double-tap: select word, Triple-tap: select line)
      1 Finger Drag             Select text, drag windows, or move sliders (in 'select' mode)
      1 Finger Long-Press       Right-click / context menu (~0.5s stationary hold)
      2 Finger Tap              Right-click / context menu
      2 Finger Drag             Smooth inertial 2D trackpad scroll
      2 Finger Pinch            Native trackpad pinch-to-zoom (Safari, Chrome, Preview, Figma, etc.)
      3 / 4 Finger Swipe L/R    Switch between macOS Desktops / Full-Screen Spaces
      3 / 4 Finger Swipe Up     Mission Control
      3 / 4 Finger Swipe Down   App Exposé
      Active Pen / Stylus       Hover, pressure-sensitive drawing, barrel-button right-click

    """
}
