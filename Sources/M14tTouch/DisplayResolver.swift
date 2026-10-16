import AppKit
import CoreGraphics
import Foundation

/// Metadata for an active macOS display.
public struct DisplayInfo: Equatable, Sendable {
    public let index: Int
    public let id: CGDirectDisplayID
    public let name: String
    public let bounds: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isMain: Bool
    public let vendorID: UInt32
    public let modelID: UInt32
    public let rotationDegrees: Int
    public let isM14t: Bool

    public var isHiDPI: Bool {
        pixelWidth > Int(bounds.width.rounded()) && Int(bounds.width.rounded()) > 0
    }

    public init(
        index: Int,
        id: CGDirectDisplayID,
        name: String = "",
        bounds: CGRect,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        refreshRate: Double = 60.0,
        isMain: Bool,
        vendorID: UInt32 = 0,
        modelID: UInt32 = 0,
        rotationDegrees: Int = 0,
        isM14t: Bool = false
    ) {
        self.index = index
        self.id = id
        self.name = name
        self.bounds = bounds
        self.pixelWidth = pixelWidth > 0 ? pixelWidth : Int(bounds.width.rounded())
        self.pixelHeight = pixelHeight > 0 ? pixelHeight : Int(bounds.height.rounded())
        self.refreshRate = refreshRate
        self.isMain = isMain
        self.vendorID = vendorID
        self.modelID = modelID
        self.rotationDegrees = rotationDegrees
        self.isM14t = isM14t
    }
}

/// Summary of an available CoreGraphics display mode.
public struct DisplayModeSummary: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double

    public var isHiDPI: Bool {
        pixelWidth > width
    }

    public var description: String {
        let scaleTag = isHiDPI ? "2x HiDPI (pixels: \(pixelWidth)×\(pixelHeight))" : "1x LoDPI"
        let hz = Int(refreshRate.rounded())
        return "\(width)×\(height) @ \(hz)Hz — \(scaleTag)"
    }
}

/// Enumerates connected displays, auto-detects the Lenovo ThinkVision M14t by
/// EDID (`0x30AE:0x62A3`) or screen name, switches HiDPI / native display modes,
/// and observes live display topology changes.
public enum DisplayResolver {

    private static let maxDisplays = 16

    /// Enumerate all active displays in CoreGraphics order.
    public static func all() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: maxDisplays)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(maxDisplays), &ids, &count)

        let screenNamesByID = currentScreenNames()

        return (0..<Int(count)).map { i in
            let id = ids[i]
            let vendor = CGDisplayVendorNumber(id)
            let model = CGDisplayModelNumber(id)
            let rotation = Int(CGDisplayRotation(id).rounded())
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let fallbackName = isBuiltIn ? "Built-in Display" : "External Display \(i)"
            let name = screenNamesByID[id] ?? fallbackName

            let currentMode = CGDisplayCopyDisplayMode(id)
            let bounds = CGDisplayBounds(id)
            let pxW = currentMode?.pixelWidth ?? Int(bounds.width.rounded())
            let pxH = currentMode?.pixelHeight ?? Int(bounds.height.rounded())
            let hz = currentMode?.refreshRate ?? 60.0

            let matchesEDID = (vendor == HID.Hardware.lenovoDisplayVendorID && model == HID.Hardware.m14tDisplayModelID)
            let matchesName = name.localizedCaseInsensitiveContains("M14t")
                || name.localizedCaseInsensitiveContains("ThinkVision")

            return DisplayInfo(
                index: i,
                id: id,
                name: name,
                bounds: bounds,
                pixelWidth: pxW,
                pixelHeight: pxH,
                refreshRate: hz > 0 ? hz : 60.0,
                isMain: CGDisplayIsMain(id) != 0,
                vendorID: vendor,
                modelID: model,
                rotationDegrees: rotation,
                isM14t: matchesEDID || matchesName
            )
        }
    }

    /// Resolve the best target display for the M14t touch panel.
    ///
    /// - Priority 1: Any connected display whose EDID or localized name matches the Lenovo ThinkVision M14t.
    /// - Priority 2: The requested `index` if valid.
    /// - Priority 3: Any non-built-in external display.
    /// - Priority 4: Main display (`index 0`) as a last resort.
    public static func resolve(forIndex index: Int, preferAutoDetectM14t: Bool = true) -> DisplayInfo? {
        let displays = all()
        guard !displays.isEmpty else { return nil }

        if preferAutoDetectM14t, let m14t = displays.first(where: { $0.isM14t }) {
            return m14t
        }

        if index >= 0, index < displays.count {
            return displays[index]
        }

        if let external = displays.first(where: { !$0.isMain }) {
            return external
        }

        return displays[0]
    }

    /// Backward-compatible bounds resolver.
    public static func bounds(forIndex index: Int) -> (bounds: CGRect, resolvedIndex: Int) {
        guard let resolved = resolve(forIndex: index, preferAutoDetectM14t: true) else {
            return (.zero, 0)
        }
        return (resolved.bounds, resolved.index)
    }

    // MARK: - SkyLight / CGS Display Mode Management

    @_silgen_name("CGSGetNumberOfDisplayModes")
    private static func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: UnsafeMutablePointer<Int32>) -> CGError

    @_silgen_name("CGSGetDisplayModeDescriptionOfLength")
    private static func CGSGetDisplayModeDescriptionOfLength(_ display: CGDirectDisplayID, _ idx: Int32, _ desc: UnsafeMutableRawPointer, _ len: Int32) -> CGError

    @_silgen_name("CGSGetCurrentDisplayMode")
    private static func CGSGetCurrentDisplayMode(_ display: CGDirectDisplayID, _ modeNum: UnsafeMutablePointer<Int32>) -> CGError

    @_silgen_name("CGSConfigureDisplayMode")
    private static func CGSConfigureDisplayMode(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ modeNum: Int32) -> CGError

    public struct CGSModeDescriptor: Equatable, Sendable {
        public let modeNumber: Int32
        public let width: Int
        public let height: Int
        public let refreshRate: Double
        public let isHiDPI: Bool
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    /// Enumerate all internal SkyLight display modes (including hidden 2x Retina & 75Hz high-frequency modes).
    public static func cgsDisplayModes(for displayID: CGDirectDisplayID) -> [CGSModeDescriptor] {
        var count: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &count) == .success, count > 0 else {
            return []
        }

        var results: [CGSModeDescriptor] = []
        var buf = [UInt8](repeating: 0, count: 0xd4)
        for i in 0..<count {
            buf.withUnsafeMutableBytes { ptr in
                guard CGSGetDisplayModeDescriptionOfLength(displayID, i, ptr.baseAddress!, 0xd4) == .success else { return }
                let modeNum = ptr.loadUnaligned(fromByteOffset: 0x00, as: Int32.self)
                let flags   = ptr.loadUnaligned(fromByteOffset: 0x04, as: UInt32.self)
                let w       = Int(ptr.loadUnaligned(fromByteOffset: 0x08, as: Int32.self))
                let h       = Int(ptr.loadUnaligned(fromByteOffset: 0x0c, as: Int32.self))
                let hz      = Double(ptr.loadUnaligned(fromByteOffset: 0x24, as: Int32.self))
                let isHiDPI = (flags & 0x200000) != 0
                let scale   = isHiDPI ? 2 : 1

                results.append(CGSModeDescriptor(
                    modeNumber: modeNum,
                    width: w,
                    height: h,
                    refreshRate: hz,
                    isHiDPI: isHiDPI,
                    pixelWidth: w * scale,
                    pixelHeight: h * scale
                ))
            }
        }
        return results
    }

    /// Returns all usable desktop display modes exposed by macOS for the given display.
    public static func availableModes(for displayID: CGDirectDisplayID) -> [DisplayModeSummary] {
        var summaries: [DisplayModeSummary] = []

        // Internal SkyLight WindowServer modes (discovers 2x Retina downsampled modes and 75Hz)
        for cgs in cgsDisplayModes(for: displayID) {
            let summary = DisplayModeSummary(
                width: cgs.width,
                height: cgs.height,
                pixelWidth: cgs.pixelWidth,
                pixelHeight: cgs.pixelHeight,
                refreshRate: cgs.refreshRate > 0 ? cgs.refreshRate : 60.0
            )
            if !summaries.contains(summary) {
                summaries.append(summary)
            }
        }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        if let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] {
            for mode in modes where mode.isUsableForDesktopGUI() {
                let summary = DisplayModeSummary(
                    width: mode.width,
                    height: mode.height,
                    pixelWidth: mode.pixelWidth,
                    pixelHeight: mode.pixelHeight,
                    refreshRate: mode.refreshRate > 0 ? mode.refreshRate : 60.0
                )
                if !summaries.contains(summary) {
                    summaries.append(summary)
                }
            }
        }

        return summaries.sorted {
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI && !$1.isHiDPI }
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.refreshRate > $1.refreshRate
        }
    }

    /// Applies a `DisplayResolutionPreset` to the target display (or auto-detected M14t).
    @discardableResult
    public static func applyResolutionPreset(
        _ preset: DisplayResolutionPreset,
        to displayID: CGDirectDisplayID? = nil,
        fallbackIndex: Int = 1,
        preferAutoDetectM14t: Bool = true
    ) -> Result<String, NSError> {
        guard preset != .systemDefault else {
            return .success("Using macOS System Settings display resolution")
        }

        let targetID: CGDirectDisplayID
        if let displayID {
            targetID = displayID
        } else if let resolved = resolve(forIndex: fallbackIndex, preferAutoDetectM14t: preferAutoDetectM14t) {
            targetID = resolved.id
        } else {
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No active target display found"]
            ))
        }

        let target: (width: Int, height: Int, preferHiDPI: Bool, prefer75Hz: Bool)
        switch preset {
        case .systemDefault:
            return .success("Using macOS System Settings display resolution")
        case .hidpi1920x1080_75hz:
            target = (1920, 1080, true, true)
        case .hidpi1920x1080_60hz:
            target = (1920, 1080, true, false)
        case .hidpi1600x900, .scaled1600x900:
            target = (1600, 900, true, false)
        case .hidpi1344x756, .scaled1344x756:
            target = (1344, 756, true, false)
        case .hidpi1280x720:
            target = (1280, 720, true, false)
        case .hidpi1024x576:
            target = (1024, 576, true, false)
        case .hidpi960x540:
            target = (960, 540, true, false)
        case .native1080p_75hz:
            target = (1920, 1080, false, true)
        case .native1080p:
            target = (1920, 1080, false, false)
        }

        // 1. Try SkyLight CGS modes (supports hidden 2x Retina & 75Hz high frequency)
        let cgsModes = cgsDisplayModes(for: targetID)
        let cgsCandidates = cgsModes.filter { m in
            (m.width == target.width && m.height == target.height) ||
            (m.width == target.height && m.height == target.width)
        }

        if let selectedCGS = cgsCandidates.max(by: { a, b in
            if target.preferHiDPI && a.isHiDPI != b.isHiDPI {
                return !a.isHiDPI && b.isHiDPI
            }
            if !target.preferHiDPI && a.isHiDPI != b.isHiDPI {
                return a.isHiDPI && !b.isHiDPI
            }
            if target.prefer75Hz {
                if (a.refreshRate >= 74) != (b.refreshRate >= 74) {
                    return a.refreshRate < 74
                }
            }
            return a.refreshRate < b.refreshRate
        }) {
            var currentModeNum: Int32 = -1
            _ = CGSGetCurrentDisplayMode(targetID, &currentModeNum)
            if currentModeNum == selectedCGS.modeNumber {
                let scaleTag = selectedCGS.isHiDPI ? "2x Retina HiDPI" : "1x"
                return .success("Display already at \(selectedCGS.width)×\(selectedCGS.height) (\(scaleTag), framebuffer: \(selectedCGS.pixelWidth)×\(selectedCGS.pixelHeight) @ \(Int(selectedCGS.refreshRate.rounded()))Hz)")
            }

            var configRef: CGDisplayConfigRef?
            let beginErr = CGBeginDisplayConfiguration(&configRef)
            guard beginErr == .success, let config = configRef else {
                return .failure(NSError(
                    domain: "M14tTouch.DisplayResolver",
                    code: Int(beginErr.rawValue),
                    userInfo: [NSLocalizedDescriptionKey: "CGBeginDisplayConfiguration failed (\(beginErr.rawValue))"]
                ))
            }

            let cgsErr = CGSConfigureDisplayMode(config, targetID, selectedCGS.modeNumber)
            guard cgsErr == .success else {
                CGCancelDisplayConfiguration(config)
                return .failure(NSError(
                    domain: "M14tTouch.DisplayResolver",
                    code: Int(cgsErr.rawValue),
                    userInfo: [NSLocalizedDescriptionKey: "CGSConfigureDisplayMode failed (\(cgsErr.rawValue))"]
                ))
            }

            let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
            guard completeErr == .success else {
                return .failure(NSError(
                    domain: "M14tTouch.DisplayResolver",
                    code: Int(completeErr.rawValue),
                    userInfo: [NSLocalizedDescriptionKey: "CGCompleteDisplayConfiguration failed (\(completeErr.rawValue))"]
                ))
            }

            let scaleTag = selectedCGS.isHiDPI ? "2x Retina HiDPI" : "1x"
            return .success("Switched M14t to \(selectedCGS.width)×\(selectedCGS.height) (\(scaleTag), framebuffer: \(selectedCGS.pixelWidth)×\(selectedCGS.pixelHeight) @ \(Int(selectedCGS.refreshRate.rounded()))Hz)")
        }

        // 2. Fallback to standard CoreGraphics display modes
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(targetID, options) as? [CGDisplayMode] else {
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not enumerate display modes"]
            ))
        }

        let candidates = modes.filter { mode in
            mode.isUsableForDesktopGUI() && (
                (mode.width == target.width && mode.height == target.height) ||
                (mode.width == target.height && mode.height == target.width)
            )
        }

        let bestMode = candidates.max { a, b in
            let aHiDPI = a.pixelWidth > a.width
            let bHiDPI = b.pixelWidth > b.width
            if target.preferHiDPI && aHiDPI != bHiDPI {
                return !aHiDPI && bHiDPI
            }
            if !target.preferHiDPI && aHiDPI != bHiDPI {
                return aHiDPI && !bHiDPI
            }
            if target.prefer75Hz {
                if (a.refreshRate >= 74) != (b.refreshRate >= 74) {
                    return a.refreshRate < 74
                }
            }
            return a.refreshRate < b.refreshRate
        }

        guard let selectedMode = bestMode else {
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Mode \(target.width)×\(target.height) not available on display \(targetID)"]
            ))
        }

        if let current = CGDisplayCopyDisplayMode(targetID),
           current.width == selectedMode.width,
           current.height == selectedMode.height,
           current.pixelWidth == selectedMode.pixelWidth,
           current.pixelHeight == selectedMode.pixelHeight {
            let scaleTag = selectedMode.pixelWidth > selectedMode.width ? "2x HiDPI" : "1x"
            return .success("Display already at \(selectedMode.width)×\(selectedMode.height) (\(scaleTag), pixels: \(selectedMode.pixelWidth)×\(selectedMode.pixelHeight))")
        }

        var configRef: CGDisplayConfigRef?
        let beginErr = CGBeginDisplayConfiguration(&configRef)
        guard beginErr == .success, let config = configRef else {
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: Int(beginErr.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "CGBeginDisplayConfiguration failed (\(beginErr.rawValue))"]
            ))
        }

        let configErr = CGConfigureDisplayWithDisplayMode(config, targetID, selectedMode, nil)
        guard configErr == .success else {
            CGCancelDisplayConfiguration(config)
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: Int(configErr.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "CGConfigureDisplayWithDisplayMode failed (\(configErr.rawValue))"]
            ))
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        guard completeErr == .success else {
            return .failure(NSError(
                domain: "M14tTouch.DisplayResolver",
                code: Int(completeErr.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "CGCompleteDisplayConfiguration failed (\(completeErr.rawValue))"]
            ))
        }

        let scaleTag = selectedMode.pixelWidth > selectedMode.width ? "2x HiDPI" : "1x"
        return .success("Switched M14t to \(selectedMode.width)×\(selectedMode.height) (\(scaleTag), pixels: \(selectedMode.pixelWidth)×\(selectedMode.pixelHeight) @ \(Int(selectedMode.refreshRate.rounded()))Hz)")
    }

    private static func currentScreenNames() -> [CGDirectDisplayID: String] {
        var map: [CGDirectDisplayID: String] = [:]
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[key] as? CGDirectDisplayID {
                map[id] = screen.localizedName
            }
        }
        return map
    }
}

/// Listens for live macOS display reconfiguration events (plug/unplug, sleep/wake,
/// arrangement changes, resolution scaling, and rotation).
public final class DisplayReconfigurationObserver {

    private let onChange: () -> Void
    private var isRegistered = false

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    public func start() {
        guard !isRegistered else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(Self.callback, context)
        isRegistered = true
    }

    public func stop() {
        guard isRegistered else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(Self.callback, context)
        isRegistered = false
    }

    deinit {
        stop()
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        // Ignore the pre-change notification; act once the display change finishes.
        if flags.contains(.beginConfigurationFlag) {
            return
        }
        let observer = Unmanaged<DisplayReconfigurationObserver>.fromOpaque(userInfo).takeUnretainedValue()
        observer.onChange()
    }
}
