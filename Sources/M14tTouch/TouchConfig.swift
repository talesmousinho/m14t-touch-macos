import Foundation

/// How single-finger movement on the touchscreen is interpreted.
public enum OneFingerMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Moving 1 finger performs a standard left-mouse drag (selects text, moves windows, drags sliders).
    /// 2-finger pan scrolls content.
    case selectAndDrag = "select"
    /// Moving 1 finger immediately scrolls content like an iPad; holding briefly (~240ms) then dragging selects text.
    case scrollAndHoldToSelect = "scroll"
}

/// Action assigned to either of the M14t Smart Pencil's two side barrel buttons.
public enum StylusButtonAction: String, Codable, CaseIterable, Equatable, Sendable {
    /// Right-click / context menu (or right-drag when moving the pen).
    case rightClick = "right"
    /// Native macOS Tablet Eraser mode (`NSPointingDeviceType.eraser`) — auto-switches drawing/PDF apps to Eraser.
    case eraser = "eraser"
    /// Middle mouse button click / pan (useful in Figma, Blender, CAD, and browsers).
    case middleClick = "middle"
    /// Double-click at the pen cursor location.
    case doubleClick = "double"
    /// Sends `⌘Z` (Undo) when the button is pressed.
    case undo = "undo"
    /// Ignore the barrel button.
    case disabled = "none"

    public var label: String {
        switch self {
        case .rightClick:  return "Right-Click / Context Menu"
        case .eraser:      return "Eraser Tool (Tablet Eraser)"
        case .middleClick: return "Middle-Click / Pan"
        case .doubleClick: return "Double-Click"
        case .undo:        return "Undo (⌘Z)"
        case .disabled:    return "Disabled"
        }
    }
}

/// Display resolution & HiDPI scaling presets for the Lenovo ThinkVision M14t (14" 1920×1080 panel).
public enum DisplayResolutionPreset: String, Codable, CaseIterable, Equatable, Sendable {
    /// Do not change macOS display mode automatically.
    case systemDefault = "system"
    /// 1920×1080 @ 75Hz (2x Retina 4K UHD 3840×2160 — High Frequency 75Hz + Crisp Retina).
    case hidpi1920x1080_75hz = "1920x1080-75hz-hidpi"
    /// 1920×1080 @ 60Hz (2x Retina 4K UHD 3840×2160 — Crisp Retina Full HD).
    case hidpi1920x1080_60hz = "1920x1080-60hz-hidpi"
    /// 1600×900 @ 60Hz (2x Retina QHD+ 3200×1800 — Balanced 16:9 Desktop Sizing).
    case hidpi1600x900 = "1600x900-hidpi"
    /// 1344×756 @ 60Hz (2x Retina 2.6K 2688×1512 — Comfortable 16:9 Sizing).
    case hidpi1344x756 = "1344x756-hidpi"
    /// 1280×720 @ 60Hz (2x Retina 2.5K 2560×1440 — Large 16:9 Sizing, Windows 150%).
    case hidpi1280x720 = "1280x720-hidpi"
    /// Native `1024×576 @ 2x HiDPI` (`2048×1152` Retina framebuffer).
    case hidpi1024x576 = "1024x576-hidpi"
    /// Native `960×540 @ 2x HiDPI` (`1920×1080` 2:1 Retina framebuffer).
    case hidpi960x540 = "960x540-hidpi"
    /// Native `1920×1080 @ 75Hz` (`1x` Full HD — 75Hz High Frequency, maximum space).
    case native1080p_75hz = "1920x1080-75hz"
    /// Native `1920×1080 @ 60Hz` (`1x` Full HD — 60Hz 1:1 pixels).
    case native1080p = "1920x1080"
    /// Legacy alias for 1600×900 HiDPI.
    case scaled1600x900 = "1600x900"
    /// Legacy alias for 1344×756 HiDPI.
    case scaled1344x756 = "1344x756"

    public var label: String {
        switch self {
        case .systemDefault:          return "Keep macOS System Setting"
        case .hidpi1920x1080_75hz:    return "1920×1080 @ 75Hz (2x Retina 4K — 75Hz Ultra Smooth)"
        case .hidpi1920x1080_60hz:    return "1920×1080 @ 60Hz (2x Retina 4K — Crisp Full HD)"
        case .hidpi1600x900,
             .scaled1600x900:         return "1600×900 @ 60Hz (2x Retina QHD+ — Balanced 16:9)"
        case .hidpi1344x756,
             .scaled1344x756:         return "1344×756 @ 60Hz (2x Retina 2.6K — Comfortable 16:9)"
        case .hidpi1280x720:          return "1280×720 @ 60Hz (2x Retina 2.5K — Large 16:9)"
        case .hidpi1024x576:          return "1024×576 @ 60Hz (2x Retina 2K)"
        case .hidpi960x540:           return "960×540 @ 60Hz (2x Retina 1080p)"
        case .native1080p_75hz:       return "1920×1080 @ 75Hz (1x Full HD 75Hz — Max Space)"
        case .native1080p:            return "1920×1080 @ 60Hz (1x Full HD — Max Space)"
        }
    }

    /// Clean unique list of presets to present in UI pickers (excluding legacy aliases).
    public static var selectablePresets: [DisplayResolutionPreset] {
        [
            .systemDefault,
            .hidpi1920x1080_75hz,
            .hidpi1920x1080_60hz,
            .hidpi1600x900,
            .hidpi1344x756,
            .hidpi1280x720,
            .hidpi1024x576,
            .hidpi960x540,
            .native1080p_75hz,
            .native1080p
        ]
    }
}

/// Runtime configuration for the M14t touch & gesture driver.
public struct TouchConfig: Codable, Equatable, Sendable {

    public var displayIndex: Int
    public var autoDetectM14tDisplay: Bool
    public var displayResolutionPreset: DisplayResolutionPreset
    public var invertX: Bool
    public var invertY: Bool
    public var debugMode: Bool
    public var promptForAccessibility: Bool
    public var dragThreshold: Double
    public var autoCalibrate: Bool

    // Display & Cursor Tracking Settings
    public var returnCursorToMainDisplay: Bool

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

    // Smart Pencil (Active Stylus) Settings
    public var stylusEnabled: Bool
    public var barrelButtonAction: StylusButtonAction
    public var secondaryBarrelButtonAction: StylusButtonAction
    public var palmRejectionWhileStylusInRange: Bool

    // Manual calibration overrides
    public var manualXMin: Double?
    public var manualXMax: Double?
    public var manualYMin: Double?
    public var manualYMax: Double?

    public init(
        displayIndex: Int = 1,
        autoDetectM14tDisplay: Bool = true,
        displayResolutionPreset: DisplayResolutionPreset = .systemDefault,
        invertX: Bool = false,
        invertY: Bool = false,
        debugMode: Bool = false,
        promptForAccessibility: Bool = true,
        dragThreshold: Double = 4.0,
        autoCalibrate: Bool = false,
        returnCursorToMainDisplay: Bool = false,
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
        barrelButtonAction: StylusButtonAction = .rightClick,
        secondaryBarrelButtonAction: StylusButtonAction = .eraser,
        palmRejectionWhileStylusInRange: Bool = true,
        manualXMin: Double? = nil,
        manualXMax: Double? = nil,
        manualYMin: Double? = nil,
        manualYMax: Double? = nil
    ) {
        self.displayIndex = displayIndex
        self.autoDetectM14tDisplay = autoDetectM14tDisplay
        self.displayResolutionPreset = displayResolutionPreset
        self.invertX = invertX
        self.invertY = invertY
        self.debugMode = debugMode
        self.promptForAccessibility = promptForAccessibility
        self.dragThreshold = dragThreshold
        self.autoCalibrate = autoCalibrate
        self.returnCursorToMainDisplay = returnCursorToMainDisplay
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
        self.barrelButtonAction = barrelButtonAction
        self.secondaryBarrelButtonAction = secondaryBarrelButtonAction
        self.palmRejectionWhileStylusInRange = palmRejectionWhileStylusInRange
        self.manualXMin = manualXMin
        self.manualXMax = manualXMax
        self.manualYMin = manualYMin
        self.manualYMax = manualYMax
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayIndex = try c.decodeIfPresent(Int.self, forKey: .displayIndex) ?? 1
        autoDetectM14tDisplay = try c.decodeIfPresent(Bool.self, forKey: .autoDetectM14tDisplay) ?? true
        displayResolutionPreset = try c.decodeIfPresent(DisplayResolutionPreset.self, forKey: .displayResolutionPreset) ?? .systemDefault
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? false
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
        debugMode = try c.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        promptForAccessibility = try c.decodeIfPresent(Bool.self, forKey: .promptForAccessibility) ?? true
        dragThreshold = try c.decodeIfPresent(Double.self, forKey: .dragThreshold) ?? 4.0
        autoCalibrate = try c.decodeIfPresent(Bool.self, forKey: .autoCalibrate) ?? false
        returnCursorToMainDisplay = try c.decodeIfPresent(Bool.self, forKey: .returnCursorToMainDisplay) ?? false
        oneFingerMode = try c.decodeIfPresent(OneFingerMode.self, forKey: .oneFingerMode) ?? .selectAndDrag
        tapToClick = try c.decodeIfPresent(Bool.self, forKey: .tapToClick) ?? true
        longPressRightClick = try c.decodeIfPresent(Bool.self, forKey: .longPressRightClick) ?? false
        longPressDuration = try c.decodeIfPresent(Double.self, forKey: .longPressDuration) ?? 0.48
        twoFingerRightClick = try c.decodeIfPresent(Bool.self, forKey: .twoFingerRightClick) ?? true
        twoFingerScroll = try c.decodeIfPresent(Bool.self, forKey: .twoFingerScroll) ?? true
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) ?? true
        scrollSensitivity = try c.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 1.25
        pinchToZoom = try c.decodeIfPresent(Bool.self, forKey: .pinchToZoom) ?? true
        threeFingerSwipes = try c.decodeIfPresent(Bool.self, forKey: .threeFingerSwipes) ?? true
        naturalSpacesSwipe = try c.decodeIfPresent(Bool.self, forKey: .naturalSpacesSwipe) ?? true
        stylusEnabled = try c.decodeIfPresent(Bool.self, forKey: .stylusEnabled) ?? true
        barrelButtonAction = try c.decodeIfPresent(StylusButtonAction.self, forKey: .barrelButtonAction) ?? .rightClick
        secondaryBarrelButtonAction = try c.decodeIfPresent(StylusButtonAction.self, forKey: .secondaryBarrelButtonAction) ?? .eraser
        palmRejectionWhileStylusInRange = try c.decodeIfPresent(Bool.self, forKey: .palmRejectionWhileStylusInRange) ?? true
        manualXMin = try c.decodeIfPresent(Double.self, forKey: .manualXMin)
        manualXMax = try c.decodeIfPresent(Double.self, forKey: .manualXMax)
        manualYMin = try c.decodeIfPresent(Double.self, forKey: .manualYMin)
        manualYMax = try c.decodeIfPresent(Double.self, forKey: .manualYMax)
    }

    public var hasManualCalibration: Bool {
        manualXMin != nil || manualXMax != nil || manualYMin != nil || manualYMax != nil
    }

    /// Evaluates whether driver runtime behavior would differ between two configurations,
    /// excluding transient one-shot CLI flags like `promptForAccessibility` and `autoCalibrate`.
    public func requiresRestart(comparedTo other: TouchConfig) -> Bool {
        displayIndex != other.displayIndex ||
        autoDetectM14tDisplay != other.autoDetectM14tDisplay ||
        displayResolutionPreset != other.displayResolutionPreset ||
        invertX != other.invertX ||
        invertY != other.invertY ||
        debugMode != other.debugMode ||
        dragThreshold != other.dragThreshold ||
        returnCursorToMainDisplay != other.returnCursorToMainDisplay ||
        oneFingerMode != other.oneFingerMode ||
        tapToClick != other.tapToClick ||
        longPressRightClick != other.longPressRightClick ||
        longPressDuration != other.longPressDuration ||
        twoFingerRightClick != other.twoFingerRightClick ||
        twoFingerScroll != other.twoFingerScroll ||
        naturalScrolling != other.naturalScrolling ||
        scrollSensitivity != other.scrollSensitivity ||
        pinchToZoom != other.pinchToZoom ||
        threeFingerSwipes != other.threeFingerSwipes ||
        naturalSpacesSwipe != other.naturalSpacesSwipe ||
        stylusEnabled != other.stylusEnabled ||
        barrelButtonAction != other.barrelButtonAction ||
        secondaryBarrelButtonAction != other.secondaryBarrelButtonAction ||
        palmRejectionWhileStylusInRange != other.palmRejectionWhileStylusInRange ||
        manualXMin != other.manualXMin ||
        manualXMax != other.manualXMax ||
        manualYMin != other.manualYMin ||
        manualYMax != other.manualYMax
    }
}
