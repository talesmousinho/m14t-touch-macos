import Foundation

/// Parses command-line arguments into a `TouchConfig` (or a control action).
///
/// Kept separate from `main.swift` so the parsing logic is a pure function of
/// its input array and could be unit tested without launching the driver.
enum ArgumentParser {

    /// The outcome of parsing — either run with a config, or perform a one-shot
    /// action and exit.
    enum Outcome {
        case run(TouchConfig)
        case listDisplays
        case printDisplayUUID(TouchConfig)
        case resetCalibration
        case help
        case error(String)
    }

    static func parse(_ arguments: [String]) -> Outcome {
        var config = TouchConfig()
        var printDisplayUUID = false
        var iterator = arguments.makeIterator()

        func nextDouble() -> Double? {
            guard let raw = iterator.next() else { return nil }
            return Double(raw)
        }

        while let arg = iterator.next() {
            switch arg {
            case "--help", "-h":       return .help
            case "--list":             return .listDisplays
            case "--reset-calibration": return .resetCalibration

            case "--display":
                guard let raw = iterator.next(), let idx = Int(raw) else {
                    return .error("--display requires an integer")
                }
                config.displayIndex = idx

            case "--display-uuid":
                guard let raw = iterator.next(), let uuid = UUID(uuidString: raw) else {
                    return .error("--display-uuid requires a UUID from --list")
                }
                config.displayUUID = uuid.uuidString
            case "--print-display-uuid": printDisplayUUID = true

            case "--invert-x":      config.invertX = true
            case "--invert-y":      config.invertY = true
            case "--debug":         config.debugMode = true
            case "--two-finger-scroll": config.twoFingerScroll = true
            case "--auto-calibrate": config.autoCalibrate = true
            case "--no-accessibility-prompt": config.promptForAccessibility = false

            case "--x-min": guard let v = nextDouble() else { return .error("--x-min requires a number") }; config.manualXMin = v
            case "--x-max": guard let v = nextDouble() else { return .error("--x-max requires a number") }; config.manualXMax = v
            case "--y-min": guard let v = nextDouble() else { return .error("--y-min requires a number") }; config.manualYMin = v
            case "--y-max": guard let v = nextDouble() else { return .error("--y-max requires a number") }; config.manualYMax = v

            default:
                return .error("Unknown option: \(arg)")
            }
        }

        return printDisplayUUID ? .printDisplayUUID(config) : .run(config)
    }

    static let usageText = """

    m14ttouch — touchscreen driver for the Lenovo ThinkVision M14t on macOS

    USAGE:
      m14ttouch [OPTIONS]

    OPTIONS:
      --display N          Initial display index (default: 1); tracked by UUID thereafter
      --display-uuid UUID  Stable display identity; overrides --display
      --print-display-uuid Print selected display UUID and exit
      --auto-calibrate     Learn the touch range as you touch all four corners,
                           then save it for future runs
      --invert-x           Mirror the horizontal axis
      --invert-y           Mirror the vertical axis
      --x-min N            Manual raw X minimum (overrides saved calibration)
      --x-max N            Manual raw X maximum
      --y-min N            Manual raw Y minimum
      --y-max N            Manual raw Y maximum
      --debug              Print every HID event and resulting action
      --two-finger-scroll  Gen 1: one finger taps/drags, two fingers scroll
      --no-accessibility-prompt
               Do not show the Accessibility prompt; useful for LaunchAgents
      --list               List connected displays and exit
      --reset-calibration  Delete saved calibration and exit
      --help, -h           Show this help and exit

    FIRST RUN:
      m14ttouch --list                       # find your M14t's display index
      m14ttouch --display 1 --auto-calibrate  # calibrate by touching 4 corners

    EVERYDAY:
      m14ttouch --display 1                   # uses saved calibration

    """
}
