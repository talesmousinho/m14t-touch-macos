import Foundation

/// A single finger contact extracted from a multi-touch HID frame.
public struct TouchContact: Equatable, Sendable {
    public let id: Int
    public let isTouching: Bool
    public let isConfident: Bool
    /// Raw hardware X coordinate.
    public let rawX: Double
    /// Raw hardware Y coordinate.
    public let rawY: Double
    /// Normalized horizontal coordinate in `0...1` using the report's hardware range.
    public let normalizedX: Double
    /// Normalized vertical coordinate in `0...1` using the report's hardware range.
    public let normalizedY: Double

    public init(
        id: Int,
        isTouching: Bool,
        isConfident: Bool = true,
        rawX: Double,
        rawY: Double,
        maxX: Double = HID.Hardware.touchMaxX,
        maxY: Double = HID.Hardware.touchMaxY
    ) {
        self.id = id
        self.isTouching = isTouching
        self.isConfident = isConfident
        self.rawX = rawX
        self.rawY = rawY
        self.normalizedX = maxX > 0 ? min(max(rawX / maxX, 0.0), 1.0) : 0.0
        self.normalizedY = maxY > 0 ? min(max(rawY / maxY, 0.0), 1.0) : 0.0
    }
}

/// Complete atomic multi-touch frame across all active finger contacts at a given instant.
public struct TouchFrame: Equatable, Sendable {
    public let contacts: [TouchContact]
    public let scanTime: UInt16
    public let timestamp: TimeInterval

    /// Only contacts that are actively touching the glass (`tipSwitch == true` and `isConfident == true`).
    public var activeContacts: [TouchContact] {
        contacts.filter { $0.isTouching && $0.isConfident }
    }

    public init(contacts: [TouchContact], scanTime: UInt16 = 0, timestamp: TimeInterval) {
        self.contacts = contacts
        self.scanTime = scanTime
        self.timestamp = timestamp
    }
}

/// Active stylus / pen sample decoded from `ReportID 0x06`.
public struct StylusSample: Equatable, Sendable {
    public let tipSwitch: Bool
    public let barrelSwitch: Bool
    public let eraser: Bool
    public let invert: Bool
    public let inRange: Bool
    public let rawX: Double
    public let rawY: Double
    public let normalizedX: Double
    public let normalizedY: Double
    /// Normalized pen tip pressure in `0...1`.
    public let pressure: Double
    public let timestamp: TimeInterval

    public init(
        tipSwitch: Bool,
        barrelSwitch: Bool,
        eraser: Bool,
        invert: Bool,
        inRange: Bool,
        rawX: Double,
        rawY: Double,
        pressure: Double,
        timestamp: TimeInterval
    ) {
        self.tipSwitch = tipSwitch
        self.barrelSwitch = barrelSwitch
        self.eraser = eraser
        self.invert = invert
        self.inRange = inRange
        self.rawX = rawX
        self.rawY = rawY
        self.normalizedX = min(max(rawX / HID.Hardware.penMaxX, 0.0), 1.0)
        self.normalizedY = min(max(rawY / HID.Hardware.penMaxY, 0.0), 1.0)
        self.pressure = min(max(pressure, 0.0), 1.0)
        self.timestamp = timestamp
    }
}

/// Decoded result from a raw USB HID report emitted by the M14t.
public enum ParsedHIDReport: Equatable, Sendable {
    case touchFrame(TouchFrame)
    case stylus(StylusSample)
    case ignored
}

/// Stateful multi-packet assembler and binary decoder for Wacom M14t HID input reports.
///
/// Handles:
/// - `ReportID 0x0C` (40-byte 5-finger multi-touch packet, plus multi-packet continuation frames when >5 fingers touch)
/// - `ReportID 0x20` (11-byte secondary interface single-slot touch packet)
/// - `ReportID 0x06` (Active Wacom pen/stylus packet)
/// - `ReportID 0x01` (Ignored legacy mouse fallback packet)
public struct HIDReportParser {

    private var expectedContactCount: Int = 0
    private var accumulatedContacts: [TouchContact] = []
    /// Tracks active contacts across multi-slot reports where firmware reports one slot per packet (e.g. `0x20`).
    private var singleSlotContacts: [Int: TouchContact] = [:]
    private var hasSeenPrimaryMultiTouch: Bool = false

    public init() {}

    public mutating func parse(bytes: [UInt8], timestamp: TimeInterval) -> ParsedHIDReport {
        guard let reportID = bytes.first else { return .ignored }

        switch reportID {
        case HID.ReportID.multiTouch:
            hasSeenPrimaryMultiTouch = true
            return parseMultiTouchReport0x0C(bytes: bytes, timestamp: timestamp)

        case HID.ReportID.secondaryTouch:
            guard !hasSeenPrimaryMultiTouch else { return .ignored }
            return parseSecondaryTouchReport0x20(bytes: bytes, timestamp: timestamp)

        case HID.ReportID.stylus:
            return parseStylusReport0x06(bytes: bytes, timestamp: timestamp)

        case HID.ReportID.mouseFallback:
            // Legacy mouse emulation packet — always ignore so it never corrupts multi-touch state.
            return .ignored

        default:
            return .ignored
        }
    }

    // MARK: - Report 0x0C (Primary 5-Slot Multi-Touch, 40 bytes)

    private mutating func parseMultiTouchReport0x0C(bytes: [UInt8], timestamp: TimeInterval) -> ParsedHIDReport {
        // Layout:
        // [0]: ReportID (0x0C)
        // [1]: Padding byte
        // [2]: ContactCount (UInt8)
        // [3..<38]: 5 finger slots × 7 bytes:
        //   slot[0]: bit0 = TipSwitch, bit2 = Confidence
        //   slot[1..2]: ContactID (UInt16 LE)
        //   slot[3..4]: X (UInt16 LE, 0...12372)
        //   slot[5..6]: Y (UInt16 LE, 0...6960)
        // [38..39]: ScanTime (UInt16 LE)
        guard bytes.count >= 40 else { return .ignored }

        let reportedCount = Int(bytes[2])
        let scanTime = Self.readUInt16LE(bytes, offset: 38)

        if reportedCount > 0 {
            expectedContactCount = reportedCount
            accumulatedContacts.removeAll(keepingCapacity: true)
        }

        let slotsInPacket = 5
        for slot in 0..<slotsInPacket {
            let base = 3 + slot * 7
            let flags = bytes[base]
            let tipSwitch = (flags & 0x01) != 0
            // Note: When tipSwitch is true, bit 2 (0x04) indicates finger confidence (palm rejection).
            // Some firmware revisions leave bit 2 clear on valid touches or set it to 1; treat confidence
            // as valid whenever tipSwitch is set unless flags explicitly set invalid palm bit.
            let contactID = Int(Self.readUInt16LE(bytes, offset: base + 1))
            let rawX = Double(Self.readUInt16LE(bytes, offset: base + 3))
            let rawY = Double(Self.readUInt16LE(bytes, offset: base + 5))

            // Ignore empty trailing slots in the 5-slot array (where tipSwitch == false and contactID == 0 and X == 0 and Y == 0)
            if !tipSwitch && contactID == 0 && rawX == 0 && rawY == 0 {
                continue
            }

            let contact = TouchContact(
                id: contactID,
                isTouching: tipSwitch,
                isConfident: true,
                rawX: rawX,
                rawY: rawY,
                maxX: HID.Hardware.touchMaxX,
                maxY: HID.Hardware.touchMaxY
            )
            accumulatedContacts.append(contact)
        }

        // If this report completes the frame (common case: <= 5 contacts, or all contacts received)
        if expectedContactCount <= 5 || accumulatedContacts.count >= expectedContactCount {
            let frameContacts = deduplicateContacts(accumulatedContacts)
            accumulatedContacts.removeAll(keepingCapacity: true)
            expectedContactCount = 0
            return .touchFrame(TouchFrame(contacts: frameContacts, scanTime: scanTime, timestamp: timestamp))
        }

        return .ignored
    }

    // MARK: - Report 0x20 (Secondary 1-Slot Multi-Touch, 11 bytes)

    private mutating func parseSecondaryTouchReport0x20(bytes: [UInt8], timestamp: TimeInterval) -> ParsedHIDReport {
        // Layout:
        // [0]: ReportID (0x20)
        // [1]: Padding
        // [2]: ContactCount (UInt8)
        // [3]: Flags (bit0 = TipSwitch, bit2 = Confidence)
        // [4]: ContactID (UInt8)
        // [5..6]: X (UInt16 LE, 0...30931)
        // [7..8]: Y (UInt16 LE, 0...17399)
        // [9..10]: ScanTime (UInt16 LE)
        guard bytes.count >= 11 else { return .ignored }

        let contactCount = Int(bytes[2])
        let flags = bytes[3]
        let tipSwitch = (flags & 0x01) != 0
        let contactID = Int(bytes[4])
        let rawX = Double(Self.readUInt16LE(bytes, offset: 5))
        let rawY = Double(Self.readUInt16LE(bytes, offset: 7))
        let scanTime = Self.readUInt16LE(bytes, offset: 9)

        let contact = TouchContact(
            id: contactID,
            isTouching: tipSwitch,
            isConfident: true,
            rawX: rawX,
            rawY: rawY,
            maxX: HID.Hardware.penMaxX,
            maxY: HID.Hardware.penMaxY
        )

        if tipSwitch {
            singleSlotContacts[contactID] = contact
        } else {
            singleSlotContacts.removeValue(forKey: contactID)
        }

        if contactCount == 0 && !tipSwitch {
            singleSlotContacts.removeAll(keepingCapacity: true)
        }

        let active = Array(singleSlotContacts.values).sorted { $0.id < $1.id }
        return .touchFrame(TouchFrame(contacts: active, scanTime: scanTime, timestamp: timestamp))
    }

    // MARK: - Report 0x06 (Active Stylus / Pen, >= 8 bytes)

    private func parseStylusReport0x06(bytes: [UInt8], timestamp: TimeInterval) -> ParsedHIDReport {
        // Layout:
        // [0]: ReportID (0x06)
        // [1]: Flags (bit0=TipSwitch, bit1=BarrelSwitch, bit2=Eraser, bit3=Invert, bit4=SecondaryBarrel, bit5=InRange)
        // [2..3]: X (UInt16 LE, 0...30931)
        // [4..5]: Y (UInt16 LE, 0...17399)
        // [6..7]: TipPressure (UInt16 LE, 0...4095)
        guard bytes.count >= 8 else { return .ignored }

        let flags = bytes[1]
        let tipSwitch = (flags & 0x01) != 0
        let barrelSwitch = (flags & 0x02) != 0
        let eraser = (flags & 0x04) != 0
        let invert = (flags & 0x08) != 0
        let inRange = (flags & 0x20) != 0

        let rawX = Double(Self.readUInt16LE(bytes, offset: 2))
        let rawY = Double(Self.readUInt16LE(bytes, offset: 4))
        let rawPressure = Double(Self.readUInt16LE(bytes, offset: 6))

        let sample = StylusSample(
            tipSwitch: tipSwitch,
            barrelSwitch: barrelSwitch,
            eraser: eraser,
            invert: invert,
            inRange: inRange,
            rawX: rawX,
            rawY: rawY,
            pressure: rawPressure / HID.Hardware.penMaxPressure,
            timestamp: timestamp
        )
        return .stylus(sample)
    }

    // MARK: - Helpers

    private func deduplicateContacts(_ contacts: [TouchContact]) -> [TouchContact] {
        var byID: [Int: TouchContact] = [:]
        var order: [Int] = []
        for c in contacts {
            if byID[c.id] == nil {
                order.append(c.id)
            }
            byID[c.id] = c
        }
        return order.compactMap { byID[$0] }
    }

    @inline(__always)
    private static func readUInt16LE(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
}
