import XCTest
@testable import AetherScreensCore

final class AppleClipboardArchiveTests: XCTestCase {
    // Independently generated with Python struct + zlib Z_SYNC_FLUSH.
    private let fixture = Data(hex: "1f000000000000000000007000000065789c62606060646060102b284dcac94cd62b2d49b3d02dc849ccccd32d49ad28618000900a01a88adcccdc54dd92ca8254a09804488d3e58b97572466251716a892dd0045d0b90894f76ac7d36adfdc3fc994d5cc5a9c9f979290a399979a900000000ffff")

    func testEncodedTextMatchesIndependentRawArchiveFixture() throws {
        let packet = try AppleClipboardArchive.encode(text: "中文🙂\nsecond line")
        XCTAssertEqual(packet.prefix(8), Data([31, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(packet[8..<12], word(64))
        let expected = Data(hex: "00000001000000167075626c69632e757466382d706c61696e2d74657874000000000000000000000016e4b8ade69687f09f99820a7365636f6e64206c696e65")
        let raw = try XCTUnwrap(ZlibDecompressor().decompress(data: Data(packet.dropFirst(16)), expectedBytes: 64))
        XCTAssertEqual(raw, expected)
        XCTAssertEqual(packet.suffix(4), Data([0, 0, 255, 255]))
    }

    func testEncodeEmptyTextAndRejectOversizeBeforeCompression() throws {
        let packet = try AppleClipboardArchive.encode(text: "")
        XCTAssertEqual(try AppleClipboardArchive.decode(message: packet), .text(""))
        XCTAssertThrowsError(try AppleClipboardArchive.encode(text: String(repeating: "x", count: AppleClipboardArchive.maximumBytes)))
    }

    func testIndependentSyncFlushUnicodeArchive() throws {
        XCTAssertEqual(try AppleClipboardArchive.decode(message: fixture), .text("中文🙂\nsecond line"))
    }

    func testPromiseOnlyResponseCannotDeliverTextOrClearClipboard() throws {
        var metadata = fixture
        metadata[2] = 1
        XCTAssertEqual(try AppleClipboardArchive.decode(message: metadata), .promise)
        var empty = Data(hex: "1f000000000000000000000000000007789c000000ffff")
        empty[2] = 1
        XCTAssertEqual(try AppleClipboardArchive.decode(message: empty), .promise)
        metadata[2] = 2
        XCTAssertThrowsError(try AppleClipboardArchive.decode(message: metadata))
    }

    func testRecordFragmentationAtEveryBoundaryAndOneByteAtATime() throws {
        for split in 1..<fixture.count {
            let assembler = AppleClipboardAssembler()
            XCTAssertNil(try assembler.append(fixture.prefix(split)))
            XCTAssertEqual(try assembler.append(fixture.dropFirst(split)), .text("中文🙂\nsecond line"))
        }
        let assembler = AppleClipboardAssembler()
        for byte in fixture.dropLast() { XCTAssertNil(try assembler.append(Data([byte]))) }
        XCTAssertEqual(try assembler.append(Data([fixture.last!])), .text("中文🙂\nsecond line"))
        // A completed archive releases state for the next independent clipboard.
        XCTAssertEqual(try assembler.append(fixture), .text("中文🙂\nsecond line"))
    }

    func testAssemblyFailureAndSessionResetDiscardPartialArchive() throws {
        let assembler = AppleClipboardAssembler()
        XCTAssertNil(try assembler.append(fixture.prefix(20)))
        assembler.reset()
        XCTAssertEqual(try assembler.append(fixture), .text("中文🙂\nsecond line"))
        var oversizedHeader = Data(fixture.prefix(16))
        oversizedHeader.replaceSubrange(12..<16, with: word(Int(UInt32.max)))
        XCTAssertThrowsError(try assembler.append(oversizedHeader))
        XCTAssertEqual(try assembler.append(fixture), .text("中文🙂\nsecond line"))
        XCTAssertThrowsError(try assembler.append(fixture + Data([0])))
        XCTAssertEqual(try assembler.append(fixture), .text("中文🙂\nsecond line"))
    }

    func testEveryTruncationAndTrailingDataRejected() {
        for size in 0..<fixture.count {
            XCTAssertThrowsError(try AppleClipboardArchive.decode(message: fixture.prefix(size)))
        }
        XCTAssertThrowsError(try AppleClipboardArchive.decode(message: fixture + Data([0])))
        // Correct outer size cannot make an incomplete deflate payload valid.
        var truncated = Data(fixture.dropLast())
        truncated.replaceSubrange(12..<16, with: word(truncated.count - 16))
        XCTAssertThrowsError(try AppleClipboardArchive.decode(message: truncated))
    }

    func testDeclaredSizeMismatchAndLimitsRejected() {
        for size in [0, 111, 113, AppleClipboardArchive.maximumBytes + 1, Int(UInt32.max)] {
            var bad = fixture
            bad.replaceSubrange(8..<12, with: word(size))
            XCTAssertThrowsError(try AppleClipboardArchive.decode(message: bad))
        }
        var bad = fixture
        bad.replaceSubrange(12..<16, with: word(Int(UInt32.max)))
        XCTAssertThrowsError(try AppleClipboardArchive.decode(message: bad))
    }

    func testEmptyArchiveAndUnsupportedFlavorRemainDistinct() throws {
        XCTAssertEqual(try AppleClipboardArchive.parse(Data()), .empty)
        XCTAssertEqual(try AppleClipboardArchive.parse(word(0)), .empty)
        XCTAssertEqual(try AppleClipboardArchive.parse(archive([("public.png", Data([1, 2]))])), .unsupported)
        XCTAssertEqual(try AppleClipboardArchive.parse(archive([("public.utf8-plain-text", Data())])), .text(""))
        let emptyMessage = Data(hex: "1f000000000000000000000000000007789c000000ffff")
        XCTAssertEqual(try AppleClipboardArchive.decode(message: emptyMessage), .empty)
    }

    func testUTF8PreferredOverUTF16WithFallback() throws {
        let unicode = "中文🙂"
        let utf16 = Data(unicode.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] })
        XCTAssertEqual(try AppleClipboardArchive.parse(archive([("public.utf16-plain-text", utf16)])), .text(unicode))
        XCTAssertEqual(try AppleClipboardArchive.parse(archive([
            ("public.utf16-plain-text", utf16), ("public.utf8-plain-text", Data("preferred".utf8))
        ])), .text("preferred"))
    }

    func testMalformedUnicodeAndArchiveStructureRejected() {
        for (uti, bytes) in [("public.utf8-plain-text", Data([255])),
                             ("public.utf16-plain-text", Data([0])),
                             ("public.utf16-plain-text", Data([0xd8, 0]))] {
            XCTAssertThrowsError(try AppleClipboardArchive.parse(archive([(uti, bytes)])))
        }
        XCTAssertThrowsError(try AppleClipboardArchive.parse(word(65)))
        XCTAssertThrowsError(try AppleClipboardArchive.parse(word(0) + Data([0])))
        let raw = archive([("public.utf8-plain-text", Data("hello".utf8))])
        for size in 1..<raw.count { XCTAssertThrowsError(try AppleClipboardArchive.parse(raw.prefix(size))) }
        let tooManyAliases = word(1) + blob(Data("public.utf8-plain-text".utf8)) + word(0) + word(33)
        XCTAssertThrowsError(try AppleClipboardArchive.parse(tooManyAliases))
    }

    private func word(_ value: Int) -> Data {
        var be = UInt32(value).bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }
    private func blob(_ value: Data) -> Data { word(value.count) + value }
    private func archive(_ items: [(String, Data)]) -> Data {
        var result = word(items.count)
        for (uti, bytes) in items {
            result.append(blob(Data(uti.utf8)) + word(0) + word(0) + blob(bytes))
        }
        return result
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<end], radix: 16)!)
            index = end
        }
    }
}
