import Foundation

/// Matches the independently verified bootstrap packet. Bitmap semantics beyond
/// that profile remain experimental; this does not enable high-performance mode.
enum AppleViewerInfo {
    static func encode(osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Data {
        var payload = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { payload.append(contentsOf: $0) }
        }
        append(UInt16(1)); append(UInt32(2))
        for value: UInt32 in [1, 0, 0] { append(value) }
        for value in [osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion] {
            append(UInt32(clamping: value))
        }
        var mask = [UInt8](repeating: 0, count: 32)
        for bit in [0, 2, 3, 20, 30, 31, 32, 35, 81] { mask[bit / 8] |= UInt8(1 << (7 - bit % 8)) }
        payload.append(contentsOf: mask)
        var packet = Data([0x21, 0])
        withUnsafeBytes(of: UInt16(payload.count).bigEndian) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }
}
