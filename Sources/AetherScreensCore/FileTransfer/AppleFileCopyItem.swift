import Foundation

/// Command101 item framing observed in the native sender/receiver. Catalog and
/// extension bytes stay opaque until their complete metadata grammar is known.
struct AppleFileCopyItem: Equatable, Sendable {
    enum Kind: UInt8, Sendable { case file = 1, directory = 2, symbolicLink = 3 }
    var kind: Kind? { catalogHeader.first.flatMap(Kind.init(rawValue:)) }
    enum Failure: Error, Equatable { case invalidBody, invalidName }
    let catalogHeader: Data
    let level: UInt16
    let wireName: String
    let symbolicLinkTarget: Data?
    let extensions: Data

    /// Build command 101 from catalog bytes and explicit item fields. This is
    /// wire framing only; the negotiated owner decides which items may be sent.
    func message(sessionID: UInt32) throws -> AppleFileCopyMessage {
        guard catalogHeader.count == 104 else { throw Failure.invalidBody }
        let name = Data(wireName.utf8)
        guard !name.isEmpty, name.count <= 1023, !name.contains(0) else { throw Failure.invalidName }
        if let link = symbolicLinkTarget {
            guard !link.isEmpty, link.count <= Int(UInt16.max), !link.contains(0) else { throw Failure.invalidBody }
        }
        let linkCount = symbolicLinkTarget.map { $0.count + 1 } ?? 0
        let prefixCount = 105 + name.count + linkCount
        guard extensions.count <= 1_048_576 - 8 - prefixCount else { throw Failure.invalidBody }
        var body = catalogHeader
        func setUInt16(_ value: UInt16, at offset: Int) {
            body[body.index(body.startIndex, offsetBy: offset)] = UInt8(value >> 8)
            body[body.index(body.startIndex, offsetBy: offset + 1)] = UInt8(truncatingIfNeeded: value)
        }
        setUInt16(level, at: 92)
        setUInt16(UInt16(name.count), at: 100)
        setUInt16(UInt16(symbolicLinkTarget?.count ?? 0), at: 102)
        body.append(name)
        body.append(0)
        if let link = symbolicLinkTarget { body.append(link); body.append(0) }
        body.append(extensions)
        return AppleFileCopyMessage(version: 1, command: 101, sessionID: sessionID, body: body)
    }

    /// Logical fork sizes, not allocation sizes. The native sender serializes
    /// the resource fork before the data fork in command 101.
    var resourceForkByteCount: UInt64 { catalogUInt64(at: 34) }
    var dataForkByteCount: UInt64 { catalogUInt64(at: 42) }
    var nodeFlags: UInt16 {
        let bytes = [UInt8](catalogHeader)
        return UInt16(bytes[90]) << 8 | UInt16(bytes[91])
    }
    var isDirectory: Bool { nodeFlags & 0x0010 != 0 }

    private func catalogUInt64(at offset: Int) -> UInt64 {
        catalogHeader.dropFirst(offset).prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
    }

    static func decode(_ message: AppleFileCopyMessage, expectedSessionID: UInt32)
        throws -> Self? {
        guard message.sessionID == expectedSessionID, message.version == 1,
              message.command == 101 else { return nil }
        let bytes = [UInt8](message.body)
        guard bytes.count >= 105 else { throw Failure.invalidBody }
        func uint16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        }
        let nameLength = Int(uint16(100))
        let linkLength = Int(uint16(102))
        let nameEnd = 104 + nameLength
        guard nameLength > 0, nameLength <= 1023,
              nameEnd < bytes.count, bytes[nameEnd] == 0 else { throw Failure.invalidBody }
        let nameBytes = bytes[104..<nameEnd]
        guard !nameBytes.contains(0), let name = String(bytes: nameBytes, encoding: .utf8) else {
            throw Failure.invalidName
        }
        var next = nameEnd + 1
        var link: Data?
        if linkLength > 0 {
            let end = next + linkLength
            guard end < bytes.count, bytes[end] == 0,
                  !bytes[next..<end].contains(0) else { throw Failure.invalidBody }
            link = Data(bytes[next..<end])
            next = end + 1
        }
        return Self(catalogHeader: Data(bytes.prefix(104)), level: uint16(92),
                    wireName: name, symbolicLinkTarget: link,
                    extensions: Data(bytes.dropFirst(next)))
    }
}
