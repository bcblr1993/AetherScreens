import Foundation

/// The native `ext1` envelope and version-one attribute table. Parsing alone
/// does not apply attributes to the filesystem.
struct AppleFileCopyAttributeBlock: Equatable, Sendable {
    enum Failure: Error, Equatable { case invalidLength, invalidTable, invalidName }
    struct Entry: Equatable, Sendable {
        let name: Data
        let value: Data
    }
    let flags: UInt16
    let version: UInt16
    let payload: Data
    let trailingBytes: Data

    /// Encode the verified version-one table for outgoing metadata. Enforce the
    /// envelope's UInt16 size before allocating the combined packet.
    static func encode(entries: [Entry]) throws -> Data {
        let maximum = Int(UInt16.max)
        guard entries.count <= (maximum - 18) / 8 else { throw Failure.invalidLength }
        var length = 18 + entries.count * 8
        for entry in entries {
            guard !entry.name.isEmpty, !entry.name.contains(0) else { throw Failure.invalidName }
            guard entry.name.count < maximum - length else { throw Failure.invalidLength }
            length += entry.name.count + 1
            guard entry.value.count <= maximum - length else { throw Failure.invalidLength }
            length += entry.value.count
        }
        var result = Data([0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1])
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.bigEndian) { result.append(contentsOf: $0) }
        }
        append(UInt16(length))
        append(UInt32(length - 10))
        append(UInt32(entries.count))
        for entry in entries {
            append(UInt32(entry.name.count + 1))
            append(UInt32(entry.value.count))
        }
        for entry in entries {
            result.append(entry.name)
            result.append(0)
            result.append(entry.value)
        }
        return result
    }

    /// The version-one table has a size/count header, key/value lengths, then
    /// consecutive NUL-terminated keys and binary values. Keep names as bytes.
    func entries() throws -> [Entry]? {
        guard version == 1, flags == 0 else { return nil }
        let bytes = [UInt8](payload)
        guard bytes.count >= 8 else { throw Failure.invalidTable }
        func uint32(_ offset: Int) -> UInt32 {
            bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        let size = Int(uint32(0))
        let count = Int(uint32(4))
        guard size >= 8, size <= bytes.count,
              count <= (size - 8) / 8 else { throw Failure.invalidTable }
        var cursor = 8 + count * 8
        var result: [Entry] = []
        for index in 0..<count {
            let keyLength = Int(uint32(8 + index * 8))
            let valueLength = Int(uint32(12 + index * 8))
            guard keyLength > 0, keyLength <= size - cursor else { throw Failure.invalidTable }
            let keyEnd = cursor + keyLength
            guard bytes[keyEnd - 1] == 0,
                  !bytes[cursor..<keyEnd - 1].contains(0) else { throw Failure.invalidName }
            guard valueLength <= size - keyEnd else { throw Failure.invalidTable }
            let valueEnd = keyEnd + valueLength
            result.append(Entry(name: Data(bytes[cursor..<keyEnd - 1]),
                                value: Data(bytes[keyEnd..<valueEnd])))
            cursor = valueEnd
        }
        return result
    }

    static func decode(_ data: Data) throws -> Self? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes.prefix(4).elementsEqual([0x65, 0x78, 0x74, 0x31]) else {
            return nil
        }
        guard bytes.count >= 10 else { throw Failure.invalidLength }
        func uint16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }
        let length = Int(uint16(8))
        guard length >= 10, length <= bytes.count else { throw Failure.invalidLength }
        return Self(flags: uint16(4), version: uint16(6),
                    payload: Data(bytes[10..<length]), trailingBytes: Data(bytes.dropFirst(length)))
    }
}
