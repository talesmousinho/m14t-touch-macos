import Foundation

/// How single-finger movement on the touchscreen is interpreted.
public enum OneFingerMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Moving 1 finger performs a standard left-mouse drag (selects text, moves windows, drags sliders).
    /// 2-finger pan scrolls content.
    case selectAndDrag = "select"
    /// Moving 1 finger immediately scrolls content like an iPad; holding briefly (~240ms) then dragging selects text.
    case scrollAndHoldToSelect = "scroll"
}

/// Runtime configuration for the M14t touch & gesture driver.
public struct TouchConfig: Equatable, Sendable {

    public var displayIndex: Int
    public var autoDetectM14tDisplay: Bool
    public var invertX: Bool
    public var invertY: Bool
    public var debugMode: Bool
    public var promptForAccessibility: Bool
    public var dragThreshold: Double
    public var autoCalibrate: Bool

    // Tablet & Trackpad Gesture Settings
    public var oneFingerMode: OneFingerMode
    public var tapToClick: Bool
    public var longPressRightClick: Bool
    public var longPressDuration: Double
    public var twoFingerRightClick: Bool
    public var twoFingerScroll: Bool
    public var naturalScrolling: Bool
    public var scrollSensitivity: Double
    public var pinchToZoom: Bool
    public var threeFingerSwipes: Bool
    public var naturalSpacesSwipe: Bool
    public var stylusEnabled: Bool

    // Manual calibration overrides
    public var manualXMin: Double?
    public var manualXMax: Double?
    public var manualYMin: Double?
    public var manualYMax: Double?

    public init(
        displayIndex: Int = 1,
        autoDetectM14tDisplay: Bool = true,
        invertX: Bool = false,
        invertY: Bool = false,
        debugMode: Bool = false,
        promptForAccessibility: Bool = true,
        dragThreshold: Double = 4.0,
        autoCalibrate: Bool = false,
        oneFingerMode: OneFingerMode = .selectAndDrag,
        tapToClick: Bool = true,
        longPressRightClick: Bool = false,
        longPressDuration: Double = 0.48,
        twoFingerRightClick: Bool = true,
        twoFingerScroll: Bool = true,
        naturalScrolling: Bool = true,
        scrollSensitivity: Double = 1.25,
        pinchToZoom: Bool = true,
        threeFingerSwipes: Bool = true,
        naturalSpacesSwipe: Bool = true,
        stylusEnabled: Bool = true,
        manualXMin: Double? = nil,
        manualXMax: Double? = nil,
        manualYMin: Double? = nil,
        manualYMax: Double? = nil
    ) {
        self.displayIndex = displayIndex
        self.autoDetectM14tDisplay = autoDetectM14tDisplay
        self.invertX = invertX
        self.invertY = invertY
        self.debugMode = debugMode
        self.promptForAccessibility = promptForAccessibility
        self.dragThreshold = dragThreshold
        self.autoCalibrate = autoCalibrate
        self.oneFingerMode = oneFingerMode
        self.tapToClick = tapToClick
        self.longPressRightClick = longPressRightClick
        self.longPressDuration = longPressDuration
        self.twoFingerRightClick = twoFingerRightClick
        self.twoFingerScroll = twoFingerScroll
        self.naturalScrolling = naturalScrolling
        self.scrollSensitivity = scrollSensitivity
        self.pinchToZoom = pinchToZoom
        self.threeFingerSwipes = threeFingerSwipes
        self.naturalSpacesSwipe = naturalSpacesSwipe
        self.stylusEnabled = stylusEnabled
        self.manualXMin = manualXMin
        self.manualXMax = manualXMax
        self.manualYMin = manualYMin
        self.manualYMax = manualYMax
    }

    public var hasManualCalibration: Bool {
        manualXMin != nil || manualXMax != nil || manualYMin != nil || manualYMax != nil
    }
}
