import AppKit
import CoreGraphics
import Foundation

/// Metadata for an active macOS display.
public struct DisplayInfo: Equatable, Sendable {
    public let index: Int
    public let id: CGDirectDisplayID
    public let name: String
    public let bounds: CGRect
    public let isMain: Bool
    public let vendorID: UInt32
    public let modelID: UInt32
    public let rotationDegrees: Int
    public let isM14t: Bool

    public init(
        index: Int,
        id: CGDirectDisplayID,
        name: String = "",
        bounds: CGRect,
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
        self.isMain = isMain
        self.vendorID = vendorID
        self.modelID = modelID
        self.rotationDegrees = rotationDegrees
        self.isM14t = isM14t
    }
}

/// Enumerates connected displays, auto-detects the Lenovo ThinkVision M14t by
/// EDID (`0x30AE:0x62A3`) or screen name, and observes live display topology changes.
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

            let matchesEDID = (vendor == HID.Hardware.lenovoDisplayVendorID && model == HID.Hardware.m14tDisplayModelID)
            let matchesName = name.localizedCaseInsensitiveContains("M14t")
                || name.localizedCaseInsensitiveContains("ThinkVision")

            return DisplayInfo(
                index: i,
                id: id,
                name: name,
                bounds: CGDisplayBounds(id),
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
