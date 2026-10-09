import XCTest
@testable import AetherScreensCore

final class AppleFileCopyItemTests: XCTestCase {
    func testKnownKindBytesAreTypedAndUnknownKindsRemainOpaque() throws {
        for (raw, expected): (UInt8, AppleFileCopyItem.Kind?) in [
            (1, .file), (2, .directory), (3, .symbolicLink), (0, nil), (0x80, nil)
        ] {
            let fixture = message(name: Data([65]))
            var body = fixture.body; body[0] = raw
            let parsed = try XCTUnwrap(AppleFileCopyItem.decode(.init(version: 1, command: 101,
                sessionID: 7, body: body), expectedSessionID: 7))
            XCTAssertEqual(parsed.kind, expected)
            XCTAssertEqual(parsed.catalogHeader[0], raw)
        }
    }

    func testOutgoingItemKeepsCatalogAndMetadataWhileDerivingFramingFields() throws {
        let fixture = message(name: Data("文件😀".utf8), link: Data("../target".utf8),
                              extensionBytes: Data([0xaa, 0, 0xff]))
        let decoded = try XCTUnwrap(AppleFileCopyItem.decode(fixture, expectedSessionID: 7))
        XCTAssertEqual(try decoded.message(sessionID: 7), fixture)
        var header = decoded.catalogHeader
        header[92] = 0xff; header[93] = 0xff
        header[100] = 0xff; header[101] = 0xff
        header[102] = 0xff; header[103] = 0xff
        let item = AppleFileCopyItem(catalogHeader: header, level: 2, wireName: "A",
                                    symbolicLinkTarget: nil, extensions: Data([0, 0xff]))
        let outgoing = try item.message(sessionID: 42)
        var expected = header
        expected[92] = 0; expected[93] = 2
        expected[100] = 0; expected[101] = 1
        expected[102] = 0; expected[103] = 0
        expected.append(contentsOf: [65, 0, 0, 0xff])
        XCTAssertEqual(outgoing.body, expected)
        XCTAssertEqual(outgoing.command, 101)
        XCTAssertEqual(outgoing.sessionID, 42)
        XCTAssertEqual(try AppleFileCopyItem.decode(outgoing, expectedSessionID: 42)?.level, 2)
    }

    func testOutgoingItemRejectsMalformedOrOversizedFieldsBeforeAssembly() throws {
        let header = Data(repeating: 0, count: 104)
        func item(name: String = "A", link: Data? = nil, extra: Data = Data(), catalog: Data? = nil) -> AppleFileCopyItem {
            .init(catalogHeader: catalog ?? header, level: 0, wireName: name,
                  symbolicLinkTarget: link, extensions: extra)
        }
        for name in ["", "a\0b", String(repeating: "😀", count: 256)] {
            XCTAssertThrowsError(try item(name: name).message(sessionID: 1))
        }
        for link in [Data(), Data([0]), Data(repeating: 65, count: 65_536)] {
            XCTAssertThrowsError(try item(link: link).message(sessionID: 1))
        }
        XCTAssertThrowsError(try item(catalog: header.dropLast()).message(sessionID: 1))
        let maximumExtra = Data(repeating: 0xaa, count: 1_048_576 - 8 - 106)
        XCTAssertEqual(try item(extra: maximumExtra).message(sessionID: 1).encode().count, 1_048_582)
        XCTAssertThrowsError(try item(extra: maximumExtra + Data([0])).message(sessionID: 1))
    }

    private func message(name: Data, link: Data = Data(), extensionBytes: Data = Data()) -> AppleFileCopyMessage {
        var header = Data(repeating: 0, count: 104)
        header[0] = 0x80 // Preserve unknown catalog bits.
        header[92] = 0; header[93] = 3
        header[100] = UInt8(name.count >> 8); header[101] = UInt8(name.count & 255)
        header[102] = UInt8(link.count >> 8); header[103] = UInt8(link.count & 255)
        var body = header + name + Data([0])
        if !link.isEmpty { body.append(link); body.append(0) }
        body.append(extensionBytes)
        return AppleFileCopyMessage(version: 1, command: 101, sessionID: 7, body: body)
    }

    func testUnicodeWireNameLevelAndOpaqueCatalogArePreserved() throws {
        let input = message(name: Data("报告:2026😀.txt".utf8))
        let item = try XCTUnwrap(AppleFileCopyItem.decode(input, expectedSessionID: 7))
        XCTAssertEqual(item.wireName, "报告:2026😀.txt")
        XCTAssertEqual(item.level, 3)
        XCTAssertEqual(item.catalogHeader, input.body.prefix(104))
        XCTAssertNil(item.symbolicLinkTarget)
        XCTAssertTrue(item.extensions.isEmpty)
    }

    func testSymbolicLinkAndExtensionsStayDistinctFromName() throws {
        let input = message(name: Data("link".utf8), link: Data("../target".utf8),
                            extensionBytes: Data([0xaa, 0, 0xff]))
        let item = try XCTUnwrap(AppleFileCopyItem.decode(input, expectedSessionID: 7))
        XCTAssertEqual(item.symbolicLinkTarget, Data("../target".utf8))
        XCTAssertEqual(item.extensions, Data([0xaa, 0, 0xff]))
        // A parsed symlink is metadata, never permission to create/follow it.
        XCTAssertEqual(item.wireName, "link")
    }

    func testLogicalForkSizesUseNativeWireOrderAndFullUnsignedRange() throws {
        let original = message(name: Data("file".utf8))
        var body = original.body
        body.replaceSubrange(34..<42, with: [0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        body.replaceSubrange(42..<50, with: [UInt8](repeating: 0xff, count: 8))
        body[90] = 0x80; body[91] = 0x11 // Directory, locked and an unknown flag.
        let item = try XCTUnwrap(AppleFileCopyItem.decode(
            AppleFileCopyMessage(version: 1, command: 101, sessionID: 7, body: body),
            expectedSessionID: 7))
        XCTAssertEqual(item.resourceForkByteCount, 0x0123456789abcdef)
        XCTAssertEqual(item.dataForkByteCount, UInt64.max)
        XCTAssertEqual(item.nodeFlags, 0x8011)
        XCTAssertTrue(item.isDirectory)
        let file = try XCTUnwrap(AppleFileCopyItem.decode(original, expectedSessionID: 7))
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.dataForkByteCount, 0)
        XCTAssertEqual(file.resourceForkByteCount, 0)
    }

    func testMalformedNamesLinksAndOtherSessionsAreHandled() throws {
        for name in [Data(), Data([0xff]), Data([0x61, 0, 0x62]), Data(repeating: 0x61, count: 1024)] {
            XCTAssertThrowsError(try AppleFileCopyItem.decode(message(name: name), expectedSessionID: 7))
        }
        let input = message(name: Data("item".utf8), link: Data("target".utf8))
        for removed in 1...7 {
            let truncated = AppleFileCopyMessage(version: 1, command: 101, sessionID: 7,
                                                body: Data(input.body.dropLast(removed)))
            XCTAssertThrowsError(try AppleFileCopyItem.decode(truncated, expectedSessionID: 7))
        }
        XCTAssertNil(try AppleFileCopyItem.decode(input, expectedSessionID: 8))
    }
}
