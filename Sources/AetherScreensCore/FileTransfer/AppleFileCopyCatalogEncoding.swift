import Foundation

extension AppleFileCopyCatalogMetadata {
    /// Cross-platform native catalog framing. The caller supplies observed
    /// metadata; no macOS-only Carbon API, made-up dates, or Finder conversion.
    func encode(dataForkBytes: UInt64, resourceForkBytes: UInt64, level: UInt16) throws -> Data {
        guard wireFinderInfo.count == 32,
              rawItemKind == 1 || rawItemKind == 2,
              (rawItemKind == 2) == (nodeFlags & 0x0010 != 0),
              rawItemKind != 2 || (dataForkBytes == 0 && resourceForkBytes == 0) else {
            throw Failure.invalidHeader
        }
        var bytes = [UInt8](repeating: 0, count: 104)
        func put<T: FixedWidthInteger>(_ value: T, at offset: Int) {
            for index in 0..<MemoryLayout<T>.size {
                bytes[offset + index] = UInt8(truncatingIfNeeded: value >> ((MemoryLayout<T>.size - index - 1) * 8))
            }
        }
        func date(_ value: Timestamp, at offset: Int) {
            put(value.highSeconds, at: offset)
            put(value.lowSeconds, at: offset + 2)
            put(value.fraction, at: offset + 6)
        }
        bytes[0] = rawItemKind
        bytes[1] = userAccess
        bytes.replaceSubrange(2..<34, with: wireFinderInfo)
        put(resourceForkBytes, at: 34)
        put(dataForkBytes, at: 42)
        date(created, at: 50)
        date(contentModified, at: 58)
        date(attributesModified, at: 66)
        date(accessed, at: 74)
        date(backedUp, at: 82)
        put(nodeFlags, at: 90)
        put(level, at: 92)
        put(permissionMode, at: 94)
        put(textEncodingHint, at: 96)
        return Data(bytes)
    }
}

extension AppleFileCopyCatalogMetadata.Timestamp {
    enum Failure: Error { case invalidDate }

    /// Native UTCDateTime uses unsigned 48-bit seconds since 1904 and a
    /// 1/65536-second fraction. Reject values that cannot be represented.
    init(date: Date) throws {
        let seconds = date.timeIntervalSince1970 + 2_082_844_800
        guard seconds.isFinite, seconds >= 0, seconds < 281_474_976_710_656 else {
            throw Failure.invalidDate
        }
        let whole = UInt64(seconds.rounded(.down))
        highSeconds = UInt16(whole >> 32)
        lowSeconds = UInt32(truncatingIfNeeded: whole)
        fraction = UInt16(min(65_535, ((seconds - Double(whole)) * 65_536).rounded(.down)))
    }
}
