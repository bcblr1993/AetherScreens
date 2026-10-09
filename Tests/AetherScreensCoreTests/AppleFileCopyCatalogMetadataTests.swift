import XCTest
@testable import AetherScreensCore

final class AppleFileCopyCatalogMetadataTests: XCTestCase {
    func testPermissionRestorationDropsPrivilegeAndTypeBitsWithoutAddingAccess() throws {
        for (wire, expected): (UInt16, UInt16) in [
            (0o104755, 0o755), (0o102640, 0o640), (0o047775, 0o1775),
            (0o100444, 0o444), (0o100000, 0), (0o041700, 0o1700)
        ] {
            var header = Data(repeating: 0, count: 104)
            header[94] = UInt8(wire >> 8)
            header[95] = UInt8(truncatingIfNeeded: wire)
            let metadata = try AppleFileCopyCatalogMetadata.decode(header)
            XCTAssertEqual(metadata.permissionMode, wire)
            XCTAssertEqual(metadata.restoredPermissions, expected)
        }
    }

    func testFinderAttributeConversionMatchesNativeFileAndFolderFixtures() throws {
        let attribute = Data([65, 66, 67, 68, 69, 70, 71, 72, 0x12, 0x34, 0x56, 0x78,
            0, 0, 0, 0, 0x11, 0x22, 0, 0, 0, 0, 0, 0, 0, 0, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88])
        var header = Data(repeating: 0, count: 104)
        header.replaceSubrange(2..<34, with: attribute)
        XCTAssertEqual(try AppleFileCopyCatalogMetadata.decode(header).finderInfoAttribute, attribute)
        header[91] = 0x10
        header.replaceSubrange(2..<10, with: Data([67, 68, 65, 66, 71, 72, 69, 70]))
        XCTAssertEqual(try AppleFileCopyCatalogMetadata.decode(header).finderInfoAttribute, attribute)
    }

    func testDateConversionMatchesNativeEpochAndFractionFixtures() {
        typealias Timestamp = AppleFileCopyCatalogMetadata.Timestamp
        XCTAssertEqual(Timestamp(highSeconds: 0, lowSeconds: 0, fraction: 0).date.timeIntervalSince1970, -2_082_844_800)
        XCTAssertEqual(Timestamp(highSeconds: 0, lowSeconds: 2_082_844_800, fraction: 0).date.timeIntervalSince1970, 0)
        XCTAssertEqual(Timestamp(highSeconds: 0, lowSeconds: 2_082_844_800, fraction: 32_768).date.timeIntervalSince1970, 0.5)
        XCTAssertEqual(Timestamp(highSeconds: 1, lowSeconds: 0, fraction: 0).date.timeIntervalSince1970, 2_212_122_496)
    }

    func testTimestampComponentsAndCatalogFieldsUseIndependentEndianWidths() throws {
        var header = Data(repeating: 0, count: 104)
        header[0] = 7; header[1] = 5
        header.replaceSubrange(2..<34, with: Data((0..<32).map(UInt8.init)))
        for (index, offset) in [50, 58, 66, 74, 82].enumerated() {
            header.replaceSubrange(offset..<offset + 8, with: Data([0, UInt8(index + 1), 2, 3, 4, 5, 6, 7]))
        }
        header[91] = 0x10
        header[94] = 1; header[95] = 0xed
        header.replaceSubrange(96..<100, with: Data([8, 0, 1, 0]))
        let catalog = try AppleFileCopyCatalogMetadata.decode(header)
        for (index, timestamp) in [catalog.created, catalog.contentModified, catalog.attributesModified, catalog.accessed, catalog.backedUp].enumerated() {
            XCTAssertEqual(timestamp.highSeconds, UInt16(index + 1))
            XCTAssertEqual(timestamp.lowSeconds, 0x02030405)
            XCTAssertEqual(timestamp.fraction, 0x0607)
            XCTAssertEqual(timestamp.wholeSeconds, UInt64(index + 1) << 32 | 0x02030405)
        }
        XCTAssertEqual(catalog.rawItemKind, 7)
        XCTAssertEqual(catalog.userAccess, 5)
        XCTAssertEqual(catalog.nodeFlags, 0x10)
        XCTAssertEqual(catalog.permissionMode, 0o755)
        XCTAssertEqual(catalog.textEncodingHint, 0x08000100)
        XCTAssertEqual(catalog.wireFinderInfo, Data((0..<32).map(UInt8.init)))
    }

    func testHeaderLengthMustBeExactBeforeReadingFields() {
        for count in [0, 1, 50, 90, 103, 105] {
            XCTAssertThrowsError(try AppleFileCopyCatalogMetadata.decode(Data(repeating: 0, count: count)))
        }
    }
}
