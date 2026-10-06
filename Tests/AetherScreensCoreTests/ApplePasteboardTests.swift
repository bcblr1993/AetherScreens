import XCTest
import zlib
@testable import AetherScreensCore

final class ApplePasteboardTests: XCTestCase {
    func testViewerInfoDeclaresOnlyHandledServerMessagesInMSBOrder() {
        let packet = ApplePasteboard.viewerInfo()
        XCTAssertEqual(packet.count, 66)
        XCTAssertEqual(Array(packet.prefix(6)), [0x21, 0, 0, 62, 0, 1])
        let mask = Array(packet.suffix(32))
        let advertised = (0..<256).filter { mask[$0 / 8] & (0x80 >> ($0 % 8)) != 0 }
        XCTAssertEqual(advertised, [0, 2, 3, 20, 31])
    }

    func testEncodedArchivePreservesUnicodeLineEndingsAndEmptyText() throws {
        for text in ["", "中文🙂𠮷\r\nsecond\nline"] {
            let packet = try XCTUnwrap(ApplePasteboard.encodeText(text))
            XCTAssertEqual(Array(packet.prefix(8)), [0x1F, 0, 0, 0, 0, 0, 0, 0])
            let plainSize = number(packet.subdata(in: 8..<12))
            XCTAssertEqual(number(packet.subdata(in: 12..<16)), packet.count - 16)
            let plain = try XCTUnwrap(ZlibDecompressor().decompress(data: Data(packet.dropFirst(16)), maximumBytes: plainSize))
            XCTAssertEqual(plain, archive(type: "public.utf8-plain-text", bytes: Data(text.utf8)))
        }
        XCTAssertNil(ApplePasteboard.encodeText(String(repeating: "中", count: ApplePasteboard.maximumTextBytes / 3 + 1)))
    }

    func testIndependentArchiveWithAliasesAndUTF8Preference() throws {
        let text = "双向 🙂𠮷"
        var plain = word(2)
        plain += item(type: "public.utf16-plain-text", bytes: Data("fallback".utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }))
        plain += item(type: "public.utf8-plain-text", bytes: Data(text.utf8), alias: true)
        XCTAssertEqual(ApplePasteboard.decodeText(try compress(plain), uncompressedBytes: plain.count), text)
    }

    func testMalformedLengthsTruncationAndInvalidUTF8AreRejected() throws {
        let valid = archive(type: "public.utf8-plain-text", bytes: Data("正常🙂".utf8))
        for length in 0..<valid.count {
            let truncated = Data(valid.prefix(length))
            if length == 0 { continue }
            XCTAssertNil(ApplePasteboard.decodeText(try compress(truncated), uncompressedBytes: length), "truncated at \(length)")
        }
        for plain in [valid + Data([0]), word(257), word(1) + word(UInt32.max), archive(type: "public.utf8-plain-text", bytes: Data([0xFF]))] {
            XCTAssertNil(ApplePasteboard.decodeText(try compress(plain), uncompressedBytes: plain.count))
        }
        let compressed = try compress(valid)
        XCTAssertNil(ApplePasteboard.decodeText(compressed, uncompressedBytes: valid.count - 1))
        XCTAssertNil(ApplePasteboard.decodeText(compressed, uncompressedBytes: valid.count + 1))
        XCTAssertNil(ApplePasteboard.decodeText(compressed, uncompressedBytes: -1))
        XCTAssertNil(ApplePasteboard.decodeText(compressed, uncompressedBytes: ApplePasteboard.maximumArchiveBytes + 1))
        XCTAssertNil(ApplePasteboard.decodeText(Data([1, 2, 3]), uncompressedBytes: valid.count))
    }

    func testCompressedExpansionCannotExceedDeclaredSize() throws {
        let plain = archive(type: "public.utf8-plain-text", bytes: Data(repeating: 65, count: 2_000_000))
        XCTAssertNil(ApplePasteboard.decodeText(try compress(plain), uncompressedBytes: 32))
    }

    func testUTF16ByteOrderAndTraditionalMacTextFallback() throws {
        let samples: [(String, Data, String)] = [
            ("public.utf16-external-plain-text", Data([0xFE, 0xFF, 0, 65, 0x4E, 0x2D]), "A中"),
            ("public.utf16-external-plain-text", Data([0xFF, 0xFE, 65, 0, 0x2D, 0x4E]), "A中"),
            ("public.utf16-external-plain-text", Data([0, 65, 0x4E, 0x2D]), "A中"),
            ("public.utf16-plain-text", Data([65, 0, 0x2D, 0x4E]), "A中"),
            ("com.apple.traditional-mac-plain-text", Data([99, 97, 102, 0x8E]), "café")
        ]
        for (type, bytes, expected) in samples {
            let plain = archive(type: type, bytes: bytes)
            XCTAssertEqual(ApplePasteboard.decodeText(try compress(plain), uncompressedBytes: plain.count), expected)
        }
        let unknown = archive(type: "public.png", bytes: Data([1, 2, 3]))
        XCTAssertNil(ApplePasteboard.decodeText(try compress(unknown), uncompressedBytes: unknown.count))
    }

    func testBinaryImageURLAndRichTextFlavorsPreserveIndependentWireData() throws {
        let image = Data([0x89, 0x50, 0x4E, 0x47, 0, 0xFF, 0x80])
        let url = Data("https://example.com/中文?q=1".utf8)
        let rich = Data("{\\rtf1 rich text}".utf8)
        var plain = word(3)
        plain += item(type: "public.png", bytes: image, alias: true)
        plain += item(type: "public.url", bytes: url)
        plain += item(type: "public.rtf", bytes: rich)
        let decoded = try XCTUnwrap(ApplePasteboard.decodeItems(try compress(plain), uncompressedBytes: plain.count))
        XCTAssertEqual(decoded, [
            .init(type: "public.png", data: image, aliases: [.init(name: "QA alias", data: Data([1, 2]))]),
            .init(type: "public.url", data: url),
            .init(type: "public.rtf", data: rich)
        ])
        XCTAssertNil(ApplePasteboard.text(in: decoded))
        let packet = try XCTUnwrap(ApplePasteboard.encodeItems(decoded))
        let encodedPlain = try XCTUnwrap(ZlibDecompressor().decompress(data: Data(packet.dropFirst(16)), maximumBytes: plain.count))
        XCTAssertEqual(encodedPlain, plain)
        XCTAssertEqual(number(packet.subdata(in: 8..<12)), plain.count)
        XCTAssertEqual(number(packet.subdata(in: 12..<16)), packet.count - 16)
    }

    func testTypedArchiveLimitsAndEmptyArchive() throws {
        let item = RFBClipboardFlavor(type: "public.png", data: Data([0, 255]))
        XCTAssertNil(ApplePasteboard.encodeItems(Array(repeating: item, count: 257)))
        XCTAssertNil(ApplePasteboard.encodeItems([.init(type: String(repeating: "a", count: 1025), data: Data())]))
        XCTAssertNil(ApplePasteboard.encodeItems([.init(type: "public.png", data: Data(repeating: 0, count: ApplePasteboard.maximumArchiveBytes))]))
        XCTAssertNil(ApplePasteboard.encodeItems([.init(type: "public.png", data: Data(), aliases: Array(repeating: .init(name: "a", data: Data()), count: 65))]))
        let empty = try XCTUnwrap(ApplePasteboard.encodeItems([]))
        XCTAssertEqual(ApplePasteboard.decodeItems(Data(empty.dropFirst(16)), uncompressedBytes: 4), [])
        var malformed = word(1) + field(Data("public.png".utf8)) + word(0) + word(1)
        malformed += field(Data([255])) + field(Data([1])) + field(Data([2]))
        XCTAssertNil(ApplePasteboard.decodeItems(try compress(malformed), uncompressedBytes: malformed.count))
    }

    private func word(_ number: UInt32) -> Data {
        withUnsafeBytes(of: number.bigEndian) { Data($0) }
    }
    private func number(_ bytes: Data) -> Int { Int(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) }
    private func field(_ bytes: Data) -> Data { word(UInt32(bytes.count)) + bytes }
    private func item(type: String, bytes: Data, alias: Bool = false) -> Data {
        field(Data(type.utf8)) + word(0) + word(alias ? 1 : 0)
            + (alias ? field(Data("QA alias".utf8)) + field(Data([1, 2])) : Data()) + field(bytes)
    }
    private func archive(type: String, bytes: Data) -> Data { word(1) + item(type: type, bytes: bytes) }
    private func compress(_ plain: Data) throws -> Data {
        var size = compressBound(uLong(plain.count))
        var compressed = [UInt8](repeating: 0, count: Int(size))
        let status = plain.withUnsafeBytes {
            compress2(&compressed, &size, $0.bindMemory(to: UInt8.self).baseAddress!, uLong(plain.count), Z_DEFAULT_COMPRESSION)
        }
        XCTAssertEqual(status, Z_OK)
        return Data(compressed.prefix(Int(size)))
    }
}
