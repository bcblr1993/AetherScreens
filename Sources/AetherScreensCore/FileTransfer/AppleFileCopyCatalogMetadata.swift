import Foundation

/// Known command101 catalog fields. Finder bytes remain in wire representation.
struct AppleFileCopyCatalogMetadata: Equatable, Sendable {
    enum Failure: Error { case invalidHeader }
    struct Timestamp: Equatable, Sendable {
        let highSeconds: UInt16
        let lowSeconds: UInt32
        let fraction: UInt16
        var wholeSeconds: UInt64 { UInt64(highSeconds) << 32 | UInt64(lowSeconds) }
        /// Matches UCConvertUTCDateTimeToCFAbsoluteTime: seconds since 1904
        /// and a fraction measured in 1/65536-second units.
        var date: Date {
            Date(timeIntervalSince1970: Double(wholeSeconds) - 2_082_844_800 + Double(fraction) / 65_536)
        }
    }
    let rawItemKind: UInt8
    let userAccess: UInt8
    let wireFinderInfo: Data
    let created: Timestamp
    let contentModified: Timestamp
    let attributesModified: Timestamp
    let accessed: Timestamp
    let backedUp: Timestamp
    let nodeFlags: UInt16
    let permissionMode: UInt16
    let textEncodingHint: UInt32

    /// Native SetUNIXPermissions clears setuid/setgid before chmod. File type
    /// bits are not chmod permissions; preserve sticky and ordinary access bits.
    var restoredPermissions: UInt16 { permissionMode & 0o1777 }

    /// FSGetCatalogInfo swaps a folder's first four UInt16 fields, while the
    /// sender swaps them as two UInt32 fields. Undo that word order for xattrs.
    var finderInfoAttribute: Data {
        guard nodeFlags & 0x0010 != 0 else { return wireFinderInfo }
        var bytes = [UInt8](wireFinderInfo)
        for offset in [0, 4] {
            bytes.swapAt(offset, offset + 2)
            bytes.swapAt(offset + 1, offset + 3)
        }
        return Data(bytes)
    }

    static func decode(_ header: Data) throws -> Self {
        guard header.count == 104 else { throw Failure.invalidHeader }
        let bytes = [UInt8](header)
        func u16(_ offset: Int) -> UInt16 { UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1]) }
        func u32(_ offset: Int) -> UInt32 {
            bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        func timestamp(_ offset: Int) -> Timestamp {
            .init(highSeconds: u16(offset), lowSeconds: u32(offset + 2), fraction: u16(offset + 6))
        }
        return .init(rawItemKind: bytes[0], userAccess: bytes[1], wireFinderInfo: Data(bytes[2..<34]),
            created: timestamp(50), contentModified: timestamp(58), attributesModified: timestamp(66),
            accessed: timestamp(74), backedUp: timestamp(82), nodeFlags: u16(90),
            permissionMode: u16(94), textEncodingHint: u32(96))
    }
}
