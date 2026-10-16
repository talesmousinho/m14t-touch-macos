import Foundation

/// USB HID and EDID hardware constants for the Lenovo ThinkVision M14t.
public enum HID {

    /// Hardware identifiers for the M14t's integrated Wacom digitizer and Lenovo EDID.
    public enum Hardware {
        /// Wacom Co., Ltd. USB Vendor ID used in the M14t digitizer (`0x2D1F` / `11551` and `0x056A` / `1386`).
        public static let wacomVendorIDs: Set<Int> = [0x2D1F, 0x056A]
        /// M14t "Pen and multitouch sensor" USB Product ID (`0x524C` / `21068`).
        public static let m14tProductID: Int = 0x524C

        /// Lenovo EDID Manufacturer ID (`0x30AE` = "LEN") and M14t panel model (`0x62A3`).
        public static let lenovoDisplayVendorID: UInt32 = 0x30AE
        public static let m14tDisplayModelID: UInt32 = 0x62A3

        /// Native factory logical bounds for ReportID `0x0C` (Multi-Touch Finger).
        public static let touchMaxX: Double = 12372.0
        public static let touchMaxY: Double = 6960.0

        /// Native factory logical bounds for ReportID `0x06` / `0x20` (Active Stylus / Secondary Touch).
        public static let penMaxX: Double = 30931.0
        public static let penMaxY: Double = 17399.0
        public static let penMaxPressure: Double = 4095.0
    }

    /// HID Report IDs emitted or accepted by the Wacom M14t controller.
    public enum ReportID {
        /// Legacy single-touch mouse emulation report (`0...32767`). Ignored in favor of native multi-touch.
        public static let mouseFallback: UInt8 = 0x01
        /// Active Pen / Stylus report (`X: 0...30931`, `Y: 0...17399`, `Pressure: 0...4095`).
        public static let stylus: UInt8 = 0x06
        /// Wacom vendor-defined Active Stylus report (`0xFF11:0x02`, same binary layout as `0x06`).
        public static let stylusVendor: UInt8 = 0x0B
        /// Primary 5-slot Multi-Touch finger report (40 bytes, `X: 0...12372`, `Y: 0...6960`).
        public static let multiTouch: UInt8 = 0x0C
        /// Primary Device Configuration feature report (`InputMode`, `SurfaceSwitch`).
        public static let deviceConfigPrimary: UInt8 = 0x0E
        /// Secondary single-slot Touch report on interface 1 (11 bytes, `X: 0...30931`, `Y: 0...17399`).
        public static let secondaryTouch: UInt8 = 0x20
        /// Secondary Device Configuration feature report on interface 1.
        public static let deviceConfigSecondary: UInt8 = 0x23
    }

    public enum Page: UInt32 {
        case genericDesktop = 0x01
        case button         = 0x09
        case digitizer      = 0x0D
        case wacomVendor    = 0xFF11
    }

    public enum GenericDesktop: UInt32 {
        case pointer = 0x01
        case mouse   = 0x02
        case x       = 0x30
        case y       = 0x31
    }

    public enum Digitizer: UInt32 {
        case pen                     = 0x02
        case touchScreen             = 0x04
        case deviceConfig            = 0x0E
        case stylus                  = 0x20
        case finger                  = 0x22
        case deviceSettings          = 0x23
        case tipPressure             = 0x30
        case inRange                 = 0x32
        case batteryStrength         = 0x3B
        case invert                  = 0x3C
        case xTilt                   = 0x3D
        case yTilt                   = 0x3E
        case tipSwitch               = 0x42
        case barrelSwitch            = 0x44
        case eraser                  = 0x45
        case confidence              = 0x47
        case contactIdentifier       = 0x51
        case inputMode               = 0x52
        case surfaceSwitch           = 0x53
        case contactCount            = 0x54
        case contactCountMax         = 0x55
        case scanTime                = 0x56
        case secondaryBarrelSwitch   = 0x5A
        case transducerSerialNumber  = 0x5B
    }
}
