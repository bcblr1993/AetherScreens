import Foundation
import zlib

/// A pasteboard flavor and its wire aliases. Binary data is never coerced to text.
public struct RFBClipboardFlavor: Equatable, Sendable {
    public struct Alias: Equatable, Sendable {
        public let name: String
        public let data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data }
    }
    public let type: String
    public let data: Data
    public let aliases: [Alias]
    public init(type: String, data: Data, aliases: [Alias] = []) {
        self.type = type; self.data = data; self.aliases = aliases
    }
}

/// Apple pasteboard archives use typed data, distinct from legacy RFB text.
enum ApplePasteboard {
    static let maximumTextBytes = 1_048_000
    static let maximumArchiveBytes = 16_777_216

    /// Register only server message types this client can consume. Apple gates
    /// unsolicited status messages on the MSB-first ViewerInfo command bitmap.
    static func viewerInfo() -> Data {
        var body = Data([0, 1])
        // Viewer category 2, application 1.0.0, compatible macOS protocol baseline 15.0.0.
        for field in [UInt32(2), 1, 0, 0, 15, 0, 0] {
            withUnsafeBytes(of: field.bigEndian) { body.append(contentsOf: $0) }
        }
        var commands = [UInt8](repeating: 0, count: 32)
        for command in [0, 2, 3, 20, 31] {
            commands[command / 8] |= 0x80 >> (command % 8)
        }
        body.append(contentsOf: commands)
        var packet = Data([0x21, 0])
        withUnsafeBytes(of: UInt16(body.count).bigEndian) { packet.append(contentsOf: $0) }
        packet.append(body)
        return packet
    }

    static func decodeItems(_ compressed: Data, uncompressedBytes: Int) -> [RFBClipboardFlavor]? {
        guard (0...maximumArchiveBytes).contains(uncompressedBytes),
              compressed.count <= maximumArchiveBytes,
              let plain = ZlibDecompressor().decompress(data: compressed, maximumBytes: max(1, uncompressedBytes)),
              plain.count == uncompressedBytes else { return nil }
        if plain.isEmpty { return [] }
        var position = 0
        func word() -> Int? {
            guard plain.count - position >= 4 else { return nil }
            let value = plain[position..<(position + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            position += 4
            return Int(value)
        }
        func bytes() -> Data? {
            guard let length = word(), length <= plain.count - position else { return nil }
            defer { position += length }
            return plain.subdata(in: position..<(position + length))
        }
        guard let count = word(), count <= 256 else { return nil }
        var items: [RFBClipboardFlavor] = []
        for _ in 0..<count {
            guard let typeBytes = bytes(), typeBytes.count <= 1024,
                  let type = String(data: typeBytes, encoding: .utf8),
                  word() != nil, let aliases = word(), aliases <= 64 else { return nil }
            var metadata: [RFBClipboardFlavor.Alias] = []
            for _ in 0..<aliases {
                guard let nameBytes = bytes(), nameBytes.count <= 1024,
                      let name = String(data: nameBytes, encoding: .utf8),
                      let value = bytes() else { return nil }
                metadata.append(.init(name: name, data: value))
            }
            guard let content = bytes() else { return nil }
            items.append(.init(type: type, data: content, aliases: metadata))
        }
        guard position == plain.count else { return nil }
        return items
    }

    static func decodeText(_ compressed: Data, uncompressedBytes: Int) -> String? {
        guard let items = decodeItems(compressed, uncompressedBytes: uncompressedBytes) else { return nil }
        return text(in: items)
    }

    static func text(in items: [RFBClipboardFlavor]) -> String? {
        for item in items where item.type == "public.utf8-plain-text" {
            return String(data: item.data, encoding: .utf8)
        }
        for item in items {
            let bytes = item.data
            switch item.type {
            case "public.utf16-external-plain-text":
                return String(data: bytes, encoding: bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) ? .utf16 : .utf16BigEndian)
            case "public.utf16-plain-text":
                return String(data: bytes, encoding: bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) ? .utf16 : .utf16LittleEndian)
            case "com.apple.traditional-mac-plain-text": return String(data: bytes, encoding: .macOSRoman)
            default: continue
            }
        }
        return items.isEmpty ? "" : nil
    }

    static func encodeText(_ text: String) -> Data? {
        let bytes = Data(text.utf8)
        guard bytes.count <= maximumTextBytes else { return nil }
        return encodeItems([.init(type: "public.utf8-plain-text", data: bytes)])
    }

    static func encodeItems(_ items: [RFBClipboardFlavor]) -> Data? {
        guard items.count <= 256 else { return nil }
        // Account for every length field before allocating the archive.
        var size = 4
        for item in items {
            guard item.type.utf8.count <= 1024, item.aliases.count <= 64 else { return nil }
            size += 16 + item.type.utf8.count + item.data.count
            for alias in item.aliases {
                guard alias.name.utf8.count <= 1024 else { return nil }
                size += 8 + alias.name.utf8.count + alias.data.count
            }
            guard size <= maximumArchiveBytes else { return nil }
        }
        var archive = Data()
        archive.reserveCapacity(size)
        func word(_ value: Int) {
            var big = UInt32(value).bigEndian
            withUnsafeBytes(of: &big) { archive.append(contentsOf: $0) }
        }
        func field(_ bytes: Data) { word(bytes.count); archive.append(bytes) }
        word(items.count)
        for item in items {
            field(Data(item.type.utf8))
            word(0)
            word(item.aliases.count)
            for alias in item.aliases {
                field(Data(alias.name.utf8)); field(alias.data)
            }
            field(item.data)
        }

        var stream = z_stream()
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION,
                           Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        var compressed = Data(count: Int(compressBound(uLong(archive.count))) + 32)
        let capacity = compressed.count
        let success = archive.withUnsafeBytes { input in
            compressed.withUnsafeMutableBytes { output -> Bool in
                stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(archive.count)
                stream.next_out = output.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(capacity)
                return deflate(&stream, Z_SYNC_FLUSH) == Z_OK && stream.avail_in == 0 && stream.avail_out > 0
            }
        }
        guard success, capacity - Int(stream.avail_out) <= maximumArchiveBytes else { return nil }
        compressed.removeSubrange((capacity - Int(stream.avail_out))..<capacity)
        var packet = Data([0x1F, 0, 0, 0, 0, 0, 0, 0])
        for length in [archive.count, compressed.count] {
            var big = UInt32(length).bigEndian
            withUnsafeBytes(of: &big) { packet.append(contentsOf: $0) }
        }
        packet.append(compressed)
        return packet
    }
}
