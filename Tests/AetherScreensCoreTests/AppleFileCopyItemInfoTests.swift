import XCTest
@testable import AetherScreensCore

final class AppleFileCopyItemInfoTests: XCTestCase {
    func testEncodingMatchesIndependentNativeLayout() throws {
        let info = AppleFileCopyItemInfo(rawHeaderValue: 0x01020304,
            reserved: Data([9, 8, 7, 6]), logicalBytes: 0x0102030405060708,
            physicalBytes: UInt64.max, fileCount: 3, forkCount: 4,
            folderCount: 5, allocationSize: 4096, trailing: Data([99]))
        let message = try info.message(sessionID: 7)
        var expected = Data([0x22, 0, 0, 0, 0, 61, 0, 1, 0, 100, 0, 0, 0, 7,
            1, 2, 3, 4, 9, 8, 7, 6, 1, 2, 3, 4, 5, 6, 7, 8])
        expected.append(contentsOf: Array(repeating: UInt8(255), count: 8))
        expected.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 3,
            0, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 5,
            0, 0, 16, 0, 99])
        XCTAssertEqual(try message.encode(), expected)
    }

    func testEncodingRejectsInvalidReservedBytesAndHonorsEnvelopeLimit() throws {
        func info(reserved: Data, trailing: Data = Data()) -> AppleFileCopyItemInfo {
            .init(rawHeaderValue: 0, reserved: reserved, logicalBytes: 0,
                physicalBytes: 0, fileCount: 0, forkCount: 0, folderCount: 0,
                allocationSize: 0, trailing: trailing)
        }
        for count in [0, 3, 5] {
            XCTAssertThrowsError(try info(reserved: Data(repeating: 0, count: count)).message(sessionID: 1))
        }
        let valid = info(reserved: Data(repeating: 0, count: 4), trailing: Data([42]))
        XCTAssertThrowsError(try valid.message(sessionID: 1, maximumPayloadBytes: 60))
        XCTAssertThrowsError(try valid.message(sessionID: 1, maximumPayloadBytes: -1))
        XCTAssertEqual(try valid.message(sessionID: 1, maximumPayloadBytes: 61).body.count, 53)
    }

    func testLiteralBigEndianTotalsPreserveOpaqueBytes() throws {
        var body = Data([1, 2, 3, 4, 9, 8, 7, 6])
        for value: UInt8 in [11, 22, 33, 44, 55] {
            body.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, value])
        }
        body.append(contentsOf: [0, 0, 16, 0, 99])
        let info = try XCTUnwrap(AppleFileCopyItemInfo.decode(
            .init(version: 1, command: 100, sessionID: 7, body: body), expectedSessionID: 7))
        XCTAssertEqual(info.rawHeaderValue, 0x01020304)
        XCTAssertEqual(info.reserved, Data([9, 8, 7, 6]))
        XCTAssertEqual([info.logicalBytes, info.physicalBytes, info.fileCount, info.forkCount, info.folderCount], [11, 22, 33, 44, 55])
        XCTAssertEqual(info.allocationSize, 4096)
        XCTAssertEqual(info.trailing, Data([99]))
    }

    func testTruncationAndSessionFiltering() throws {
        for count in 0..<52 {
            let message = AppleFileCopyMessage(version: 1, command: 100, sessionID: 7, body: Data(repeating: 0, count: count))
            XCTAssertThrowsError(try AppleFileCopyItemInfo.decode(message, expectedSessionID: 7))
            XCTAssertNil(try AppleFileCopyItemInfo.decode(message, expectedSessionID: 8))
        }
    }
}
