import CoreGraphics

enum M14tReport {
    /// Gen 1 Android/Chrome report 0x0c, verified against its USB HID descriptor.
    /// Byte 1 is padding; byte 2 is contact count. Each of five slots contains
    /// flags, a little-endian 16-bit contact ID, X and Y; scan time follows.
    /// Other reports (including the secondary digitizer and pen) are ignored.
    static func decode(_ bytes: [UInt8]) -> [TouchContact]? {
        guard bytes.count == 40, bytes[0] == 0x0c, bytes[2] <= 5 else { return nil }
        func word(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        var contacts: [TouchContact] = []
        var ids = Set<Int>()
        var touching = 0
        for slot in 0..<5 {
            let offset = 3 + slot * 7
            guard bytes[offset] & 1 != 0 else { continue }
            touching += 1
            guard bytes[offset] & 4 != 0 else { continue } // Confidence: reject palms.
            let id = word(offset + 1)
            guard ids.insert(id).inserted else { return nil }
            contacts.append(TouchContact(id: id, point: CGPoint(x: word(offset + 3), y: word(offset + 5))))
        }
        // Lift reports can retain the contact count while Tip Switch becomes 0.
        guard touching <= Int(bytes[2]) else { return nil }
        return contacts
    }
}
