import CoreGraphics
import ColorSync

/// A connected display. UUID persists across changes to ordering and display IDs.
struct DisplayInfo: Equatable {
    let index: Int
    let id: CGDirectDisplayID
    let uuid: String
    let bounds: CGRect
    let isMain: Bool
}

/// Pins the initial selection to one physical display. Never falls back to main.
struct DisplayTarget {
    let uuid: String?
    private(set) var current: DisplayInfo?

    init(index: Int, uuid: String?, displays: [DisplayInfo]) {
        self.uuid = uuid ?? displays.first(where: { $0.index == index })?.uuid
        current = displays.first(where: { $0.uuid == self.uuid })
    }

    /// Returns true when mapping or availability changed.
    mutating func refresh(_ displays: [DisplayInfo]) -> Bool {
        let next = displays.first(where: { $0.uuid == uuid })
        guard next != current else { return false }
        current = next
        return true
    }
}

enum DisplayResolver {
    private static let maxDisplays = 16

    static func all() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: maxDisplays)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(maxDisplays), &ids, &count) == .success else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let value = CGDisplayCreateUUIDFromDisplayID(ids[i]) else { return nil }
            let uuid = CFUUIDCreateString(nil, value.takeRetainedValue()) as String
            return DisplayInfo(index: i, id: ids[i], uuid: uuid,
                bounds: CGDisplayBounds(ids[i]), isMain: CGDisplayIsMain(ids[i]) != 0)
        }
    }
}
