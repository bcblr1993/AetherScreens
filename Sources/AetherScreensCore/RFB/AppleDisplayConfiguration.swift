import Foundation

/// Experimental fixed display preface. No virtual display/dynamic resize/HDR.
enum AppleDisplayConfiguration {
    /// Nil selects the combined aggregate; an ID selects one server display.
    static func selection(displayID: UInt32? = nil) -> Data {
        var packet = Data([0x0d, displayID == nil ? 1 : 0, 0, 0])
        withUnsafeBytes(of: (displayID ?? 0).bigEndian) { packet.append(contentsOf: $0) }
        return packet
    }
    static func fixed(width: Int, height: Int, logicalWidth: Int? = nil, logicalHeight: Int? = nil,
                      physicalSize: (width: Float, height: Float)? = nil) -> Data? {
        guard (logicalWidth == nil) == (logicalHeight == nil) else { return nil }
        let scaledWidth = logicalWidth ?? width, scaledHeight = logicalHeight ?? height
        guard (1...65_535).contains(width), (1...65_535).contains(height),
              (1...width).contains(scaledWidth), (1...height).contains(scaledHeight) else { return nil }
        // Server rejects zero millimeter sizes. When no measurement is available,
        // supply nominal 96-DPI geometry, not a claim about hardware dimensions.
        let physical = physicalSize ?? (Float(scaledWidth) * 25.4 / 96, Float(scaledHeight) * 25.4 / 96)
        guard physical.width.isFinite, physical.height.isFinite,
              physical.width > 0, physical.height > 0,
              physical.width <= 100_000, physical.height <= 100_000 else { return nil }
        var packet = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { packet.append(contentsOf: $0) }
        }
        packet.append(contentsOf: [0x1d, 0])
        append(UInt16(192)); append(UInt16(1)); append(UInt16(1)); append(UInt32(0))
        append(UInt16(184))
        packet.append(Data(repeating: 0, count: 120)) // unnamed display
        append(UInt32(0)); append(UInt32(0)) // static flags/type
        append(physical.width.bitPattern); append(physical.height.bitPattern)
        append(UInt32(width)); append(UInt32(height))
        append(UInt16(0)); append(UInt16(0)); append(UInt32(0)); append(UInt16(1))
        append(UInt32(width)); append(UInt32(height))
        append(UInt32(scaledWidth)); append(UInt32(scaledHeight))
        append(Double(60).bitPattern); append(UInt32(0))
        return packet
    }
}
