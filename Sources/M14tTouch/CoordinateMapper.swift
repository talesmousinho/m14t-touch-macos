import CoreGraphics

/// Translates touch or stylus coordinates into global macOS screen coordinates
/// on the target display, accounting for display rotation (`0°`, `90°`, `180°`, `270°`)
/// and optional axis inversion.
public struct CoordinateMapper: Equatable, Sendable {

    public var calibration: CalibrationData
    public var displayBounds: CGRect
    public var invertX: Bool
    public var invertY: Bool
    /// Display rotation in degrees clockwise (`0`, `90`, `180`, `270`).
    public var rotationDegrees: Int

    public init(
        calibration: CalibrationData = .m14tFactory,
        displayBounds: CGRect,
        invertX: Bool = false,
        invertY: Bool = false,
        rotationDegrees: Int = 0
    ) {
        self.calibration = calibration
        self.displayBounds = displayBounds
        self.invertX = invertX
        self.invertY = invertY
        self.rotationDegrees = rotationDegrees
    }

    /// Map a raw `(rawX, rawY)` touch sample using `calibration` into an absolute screen point.
    public func map(rawX: Double, rawY: Double) -> CGPoint {
        let rangeX = calibration.xMax - calibration.xMin
        let rangeY = calibration.yMax - calibration.yMin
        guard rangeX > 0, rangeY > 0 else { return displayBounds.origin }

        let u = (rawX - calibration.xMin) / rangeX
        let v = (rawY - calibration.yMin) / rangeY
        return mapNormalized(u: u, v: v)
    }

    /// Map a normalized `(u, v)` coordinate in `0...1` into an absolute screen point on `displayBounds`.
    public func mapNormalized(u: Double, v: Double) -> CGPoint {
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return displayBounds.origin
        }

        var rx = u.clamped(to: 0.0...1.0)
        var ry = v.clamped(to: 0.0...1.0)

        // Apply display hardware rotation before axis inversion.
        let normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        switch normalizedRotation {
        case 90:
            let oldX = rx
            rx = 1.0 - ry
            ry = oldX
        case 180:
            rx = 1.0 - rx
            ry = 1.0 - ry
        case 270:
            let oldX = rx
            rx = ry
            ry = 1.0 - oldX
        default:
            break
        }

        if invertX { rx = 1.0 - rx }
        if invertY { ry = 1.0 - ry }

        // Clamp 1px inside the right/bottom edge so macOS never spills the cursor onto an adjacent monitor.
        let maxX = max(displayBounds.minX, displayBounds.maxX - 0.5)
        let maxY = max(displayBounds.minY, displayBounds.maxY - 0.5)

        let screenX = (displayBounds.minX + rx * displayBounds.width).clamped(to: displayBounds.minX...maxX)
        let screenY = (displayBounds.minY + ry * displayBounds.height).clamped(to: displayBounds.minY...maxY)

        return CGPoint(x: screenX, y: screenY)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
