import Foundation

/// The raw coordinate range a touch panel reports.
///
/// The M14t's primary multi-touch collection (`ReportID 0x0C`) uses a factory
/// coordinate grid of `0...12372` × `0...6960`, so `m14tFactory` works out of
/// the box without manual corner calibration. Optional custom bounds can still
/// be persisted to `~/.m14ttouch.json` when fine-tuning bezel margins.
public struct CalibrationData: Codable, Equatable, Sendable {
    public var xMin: Double
    public var xMax: Double
    public var yMin: Double
    public var yMax: Double

    public init(xMin: Double, xMax: Double, yMin: Double, yMax: Double) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
    }

    /// Factory hardware coordinate bounds for the M14t's Wacom multi-touch panel (`ReportID 0x0C`).
    public static let m14tFactory = CalibrationData(
        xMin: 0,
        xMax: HID.Hardware.touchMaxX,
        yMin: 0,
        yMax: HID.Hardware.touchMaxY
    )

    /// Legacy 15-bit default range kept for backward compatibility.
    public static let identity = CalibrationData(xMin: 0, xMax: 32767, yMin: 0, yMax: 32767)
}

/// Reads and writes optional custom calibration to `~/.m14ttouch.json`.
public enum CalibrationStore {

    public static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".m14ttouch.json")

    public static func load() -> CalibrationData? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CalibrationData.self, from: data) else {
            return nil
        }
        // Reject corrupted or tiny partial calibrations (e.g. from an incomplete auto-calibrate run)
        guard (decoded.xMax - decoded.xMin) > 2000,
              (decoded.yMax - decoded.yMin) > 1000 else {
            return nil
        }
        return decoded
    }

    public static func save(_ calibration: CalibrationData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(calibration) else { return }
        try? data.write(to: url, options: .atomic)
    }

    @discardableResult
    public static func reset() -> Bool {
        (try? FileManager.default.removeItem(at: url)) != nil
    }
}
