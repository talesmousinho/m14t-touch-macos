import Foundation

/// Runtime configuration for the touch driver.
///
/// Populated from command-line arguments in `main.swift`. Kept as a plain
/// value type so it is trivial to construct in tests and pass around without
/// hidden state.
struct TouchConfig {

    /// Index of the display the M14t is mapped to (`0` is the main display).
    var displayIndex: Int = 1

    /// Stable display identity; takes precedence over the initial index.
    var displayUUID: String?

    /// Mirror the horizontal axis (use if touch is flipped left↔right).
    var invertX: Bool = false

    /// Mirror the vertical axis (use if touch is flipped top↔bottom).
    var invertY: Bool = false

    /// Print every raw HID event and resulting action. Useful for calibration.
    var debugMode: Bool = false

    /// Opt in to Gen 1 report-based two-finger scrolling.
    var twoFingerScroll: Bool = false

    /// Ask macOS to show the Accessibility permission prompt when access is missing.
    var promptForAccessibility: Bool = true

    /// Minimum movement, in screen pixels, before a finger-down is treated as a
    /// drag rather than a stationary press. Filters out jitter so a tap stays a
    /// clean click.
    var dragThreshold: Double = 1.5

    /// When `true`, the driver widens its coordinate range as it observes touch
    /// values, then persists the result. Touch all four corners once to calibrate.
    var autoCalibrate: Bool = false

    // MARK: Manual calibration overrides

    /// Explicit raw coordinate bounds. When set, these win over both the HID
    /// descriptor values and any persisted calibration.
    var manualXMin: Double?
    var manualXMax: Double?
    var manualYMin: Double?
    var manualYMax: Double?

    /// `true` when the user supplied any manual bound on the command line.
    var hasManualCalibration: Bool {
        manualXMin != nil || manualXMax != nil || manualYMin != nil || manualYMax != nil
    }
}
