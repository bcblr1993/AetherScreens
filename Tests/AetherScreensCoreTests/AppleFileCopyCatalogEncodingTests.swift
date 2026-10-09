import XCTest
@testable import AetherScreensCore

final class AppleFileCopyCatalogEncodingTests: XCTestCase {
    private func metadata(directory: Bool = false, finder: Data = Data(repeating: 0, count: 32)) -> AppleFileCopyCatalogMetadata {
        let timestamp = AppleFileCopyCatalogMetadata.Timestamp(highSeconds: 1, lowSeconds: 0x02030405, fraction: 0x0607)
        return .init(rawItemKind: directory ? 2 : 1, userAccess: 0x12, wireFinderInfo: finder,
            created: timestamp, contentModified: timestamp, attributesModified: timestamp,
            accessed: timestamp, backedUp: timestamp, nodeFlags: directory ? 0x10 : 0,
            permissionMode: 0o100644, textEncodingHint: 0x08000100)
    }

    func testFieldsMatchIndependentNativeWirePositionsAndRoundTrip() throws {
        let finder = Data(0..<32)
        let source = metadata(finder: finder)
        let header = try source.encode(dataForkBytes: 0x0102030405060708, resourceForkBytes: 0x1112131415161718, level: 0x1234)
        XCTAssertEqual(header.count, 104)
        XCTAssertEqual(header.prefix(2), Data([1,0x12]))
        XCTAssertEqual(header.subdata(in: 2..<34), finder)
        XCTAssertEqual(header.subdata(in: 34..<50), Data([0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,1,2,3,4,5,6,7,8]))
        XCTAssertEqual(header.subdata(in: 50..<58), Data([0,1,2,3,4,5,6,7]))
        XCTAssertEqual(header.subdata(in: 90..<104), Data([0,0,0x12,0x34,0x81,0xa4,8,0,1,0,0,0,0,0]))
        XCTAssertEqual(try AppleFileCopyCatalogMetadata.decode(header), source)
        let item = AppleFileCopyItem(catalogHeader: header, level: 0x1234, wireName: "测试😀",
                                    symbolicLinkTarget: nil, extensions: Data())
        let decoded = try XCTUnwrap(AppleFileCopyItem.decode(item.message(sessionID: 42), expectedSessionID: 42))
        XCTAssertEqual(decoded.dataForkByteCount, 0x0102030405060708)
        XCTAssertEqual(decoded.resourceForkByteCount, 0x1112131415161718)
        XCTAssertEqual(decoded.level, 0x1234)
    }

    func testInvalidFinderLengthOrDirectoryForksAreRejected() throws {
        XCTAssertThrowsError(try metadata(finder: Data()).encode(dataForkBytes: 0, resourceForkBytes: 0, level: 0))
        XCTAssertThrowsError(try metadata(directory: true).encode(dataForkBytes: 1, resourceForkBytes: 0, level: 0))
        XCTAssertThrowsError(try metadata(directory: true).encode(dataForkBytes: 0, resourceForkBytes: 1, level: 0))
        let header = try metadata(directory: true).encode(dataForkBytes: 0, resourceForkBytes: 0, level: 1)
        XCTAssertEqual(header[0], 2)
        XCTAssertEqual(header[91], 0x10)
    }

    func testUTCDateEpochFractionAndUnrepresentableValues() throws {
        let timestamp = try AppleFileCopyCatalogMetadata.Timestamp(date: Date(timeIntervalSince1970: 0.5))
        XCTAssertEqual(timestamp.wholeSeconds, 2_082_844_800)
        XCTAssertEqual(timestamp.fraction, 32768)
        XCTAssertEqual(timestamp.date.timeIntervalSince1970, 0.5)
        XCTAssertThrowsError(try AppleFileCopyCatalogMetadata.Timestamp(date: Date(timeIntervalSince1970: -2_082_844_801)))
        XCTAssertThrowsError(try AppleFileCopyCatalogMetadata.Timestamp(date: Date(timeIntervalSince1970: .infinity)))
        XCTAssertThrowsError(try AppleFileCopyCatalogMetadata.Timestamp(date: Date(timeIntervalSince1970: 281_474_976_710_656)))
    }
}
