import XCTest
@testable import AetherScreensCore

final class AppleFileCopyDataBlockTests: XCTestCase {
    func testLiteralRawFrameContainsOnlyDeclaredForkBytes() throws {
        let frame = Data([0x22, 0, 0, 0, 0, 15, 0, 1, 0, 102,
                          0, 0, 0, 7, 0, 0, 0, 3, 0, 0xff, 0x42])
        let message = try XCTUnwrap(AppleFileCopyMessage.decode(frame)).message
        XCTAssertEqual(try AppleFileCopyDataBlock.decode(message, expectedSessionID: 7,
                                                        remainingForkBytes: 3),
                       .raw(Data([0, 0xff, 0x42])))
        XCTAssertThrowsError(try AppleFileCopyDataBlock.decode(message, expectedSessionID: 7,
                                                              remainingForkBytes: 2)) { error in
            XCTAssertEqual(error as? AppleFileCopyDataBlock.Failure, .exceedsFork)
        }
    }

    func testRawTruncationAndTrailingBytesAreRejected() {
        for body in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 1]), Data([0, 0, 0, 0, 1])] {
            XCTAssertThrowsError(try AppleFileCopyDataBlock.decode(
                AppleFileCopyMessage(version: 1, command: 102, sessionID: 7, body: body),
                expectedSessionID: 7, remainingForkBytes: 10))
        }
    }

    func testCompressedHeaderPreservesPayloadWithoutClaimingInflation() throws {
        let message = AppleFileCopyMessage(version: 2, command: 103, sessionID: 7,
                                          body: Data([0, 1, 0, 0, 0, 8, 0, 0, 0, 3, 0xaa, 0xbb, 0xcc]))
        XCTAssertEqual(try AppleFileCopyDataBlock.decode(message, expectedSessionID: 7,
                                                        remainingForkBytes: 8),
                       .compressed(algorithm: 1, expandedBytes: 8, payload: Data([0xaa, 0xbb, 0xcc])))
        XCTAssertThrowsError(try AppleFileCopyDataBlock.decode(message, expectedSessionID: 7,
                                                              remainingForkBytes: 7))
        XCTAssertThrowsError(try AppleFileCopyDataBlock.decode(message, expectedSessionID: 7,
                                                              remainingForkBytes: 8,
                                                              maximumExpandedBytes: 7))
    }

    func testMalformedCompressionAndUnrelatedSessionAreHandled() throws {
        let bodies = [Data([0, 1]), Data([0, 2, 0, 0, 0, 1, 0, 0, 0, 0]),
                      Data([0, 1, 0, 0, 0, 1, 0, 0, 0, 2, 0]),
                      Data([0, 1, 0xff, 0xff, 0xff, 0xff, 0, 0, 0, 0])]
        for body in bodies {
            XCTAssertThrowsError(try AppleFileCopyDataBlock.decode(
                AppleFileCopyMessage(version: 1, command: 103, sessionID: 7, body: body),
                expectedSessionID: 7, remainingForkBytes: UInt64.max))
        }
        XCTAssertNil(try AppleFileCopyDataBlock.decode(
            AppleFileCopyMessage(version: 1, command: 102, sessionID: 8, body: Data()),
            expectedSessionID: 7, remainingForkBytes: 0))
        XCTAssertNil(try AppleFileCopyDataBlock.decode(
            AppleFileCopyMessage(version: 3, command: 102, sessionID: 7, body: Data()),
            expectedSessionID: 7, remainingForkBytes: 0))
    }
}
