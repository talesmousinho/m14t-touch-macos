import Foundation

public struct AppPreferences: Codable, Equatable, Sendable {
    public var displayIndex: Int
    public var autoDetectM14tDisplay: Bool
    public var displayResolutionPreset: DisplayResolutionPreset
    public var invertX: Bool
    public var invertY: Bool
    public var debugMode: Bool
    public var dragThreshold: Double
    public var runAtLogin: Bool
    public var returnCursorToMainDisplay: Bool

    // Tablet & Trackpad settings
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

    // Smart Pencil (Active Stylus) settings
    public var stylusEnabled: Bool
    public var barrelButtonAction: StylusButtonAction
    public var secondaryBarrelButtonAction: StylusButtonAction
    public var palmRejectionWhileStylusInRange: Bool

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
        dragThreshold: Double = 4.0,
        runAtLogin: Bool = false,
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
        self.dragThreshold = dragThreshold
        self.runAtLogin = runAtLogin
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

    // Resilient decoding so existing config.json files without newer keys still load cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayIndex = try c.decodeIfPresent(Int.self, forKey: .displayIndex) ?? 1
        autoDetectM14tDisplay = try c.decodeIfPresent(Bool.self, forKey: .autoDetectM14tDisplay) ?? true
        displayResolutionPreset = try c.decodeIfPresent(DisplayResolutionPreset.self, forKey: .displayResolutionPreset) ?? .systemDefault
        invertX = try c.decodeIfPresent(Bool.self, forKey: .invertX) ?? false
        invertY = try c.decodeIfPresent(Bool.self, forKey: .invertY) ?? false
        debugMode = try c.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        dragThreshold = try c.decodeIfPresent(Double.self, forKey: .dragThreshold) ?? 4.0
        runAtLogin = try c.decodeIfPresent(Bool.self, forKey: .runAtLogin) ?? false
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

    public var touchConfig: TouchConfig {
        TouchConfig(
            displayIndex: displayIndex,
            autoDetectM14tDisplay: autoDetectM14tDisplay,
            displayResolutionPreset: displayResolutionPreset,
            invertX: invertX,
            invertY: invertY,
            debugMode: debugMode,
            dragThreshold: dragThreshold,
            returnCursorToMainDisplay: returnCursorToMainDisplay,
            oneFingerMode: oneFingerMode,
            tapToClick: tapToClick,
            longPressRightClick: longPressRightClick,
            longPressDuration: longPressDuration,
            twoFingerRightClick: twoFingerRightClick,
            twoFingerScroll: twoFingerScroll,
            naturalScrolling: naturalScrolling,
            scrollSensitivity: scrollSensitivity,
            pinchToZoom: pinchToZoom,
            threeFingerSwipes: threeFingerSwipes,
            naturalSpacesSwipe: naturalSpacesSwipe,
            stylusEnabled: stylusEnabled,
            barrelButtonAction: barrelButtonAction,
            secondaryBarrelButtonAction: secondaryBarrelButtonAction,
            palmRejectionWhileStylusInRange: palmRejectionWhileStylusInRange,
            manualXMin: manualXMin,
            manualXMax: manualXMax,
            manualYMin: manualYMin,
            manualYMax: manualYMax
        )
    }

    public init(touchConfig: TouchConfig, runAtLogin: Bool = false) {
        self.init(
            displayIndex: touchConfig.displayIndex,
            autoDetectM14tDisplay: touchConfig.autoDetectM14tDisplay,
            displayResolutionPreset: touchConfig.displayResolutionPreset,
            invertX: touchConfig.invertX,
            invertY: touchConfig.invertY,
            debugMode: touchConfig.debugMode,
            dragThreshold: touchConfig.dragThreshold,
            runAtLogin: runAtLogin,
            returnCursorToMainDisplay: touchConfig.returnCursorToMainDisplay,
            oneFingerMode: touchConfig.oneFingerMode,
            tapToClick: touchConfig.tapToClick,
            longPressRightClick: touchConfig.longPressRightClick,
            longPressDuration: touchConfig.longPressDuration,
            twoFingerRightClick: touchConfig.twoFingerRightClick,
            twoFingerScroll: touchConfig.twoFingerScroll,
            naturalScrolling: touchConfig.naturalScrolling,
            scrollSensitivity: touchConfig.scrollSensitivity,
            pinchToZoom: touchConfig.pinchToZoom,
            threeFingerSwipes: touchConfig.threeFingerSwipes,
            naturalSpacesSwipe: touchConfig.naturalSpacesSwipe,
            stylusEnabled: touchConfig.stylusEnabled,
            barrelButtonAction: touchConfig.barrelButtonAction,
            secondaryBarrelButtonAction: touchConfig.secondaryBarrelButtonAction,
            palmRejectionWhileStylusInRange: touchConfig.palmRejectionWhileStylusInRange,
            manualXMin: touchConfig.manualXMin,
            manualXMax: touchConfig.manualXMax,
            manualYMin: touchConfig.manualYMin,
            manualYMax: touchConfig.manualYMax
        )
    }
}

public enum PreferencesStore {
    public static let directoryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/M14tTouch", isDirectory: true)

    public static let url: URL = directoryURL.appendingPathComponent("config.json")

    public static func load(from url: URL = Self.url) -> AppPreferences? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppPreferences.self, from: data)
    }

    public static func save(_ preferences: AppPreferences, to url: URL = Self.url) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public static func reset(at url: URL = Self.url) -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}

public struct DaemonState: Codable, Sendable, Equatable {
    public var pid: Int
    public var isAccessibilityTrusted: Bool
    public var isInputMonitoringTrusted: Bool
    public var binaryPath: String
    public var timestamp: TimeInterval

    public init(
        pid: Int,
        isAccessibilityTrusted: Bool,
        isInputMonitoringTrusted: Bool,
        binaryPath: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.pid = pid
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.isInputMonitoringTrusted = isInputMonitoringTrusted
        self.binaryPath = binaryPath
        self.timestamp = timestamp
    }
}

public enum DaemonStateStore {
    public static let url = PreferencesStore.directoryURL.appendingPathComponent("daemon_state.json")

    public static func load(from url: URL = Self.url) -> DaemonState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DaemonState.self, from: data)
    }

    public static func save(_ state: DaemonState, to url: URL = Self.url) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

