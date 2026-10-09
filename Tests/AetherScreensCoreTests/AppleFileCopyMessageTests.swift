import XCTest
@testable import AetherScreensCore

final class AppleFileCopyMessageTests: XCTestCase {
    // Literal synthetic bytes derived from static server field offsets, not
    // encoder output or a captured, accepted native transfer.
    private let frame = Data([
        0x22, 0, 0, 0, 0, 12, // payload length excludes six-byte prefix
        0, 2, 0, 5, 0x12, 0x34, 0x56, 0x78,
        0xaa, 0xbb, 0xcc, 0xdd
    ])

    func testEveryFragmentBoundaryWaitsForCompleteEnvelope() throws {
        for count in 0..<frame.count {
            XCTAssertNil(try AppleFileCopyMessage.decode(Data(frame.prefix(count))))
        }
        let result = try XCTUnwrap(AppleFileCopyMessage.decode(frame))
        XCTAssertEqual(result.message.version, 2)
        XCTAssertEqual(result.message.command, 5)
        XCTAssertEqual(result.message.sessionID, 0x12345678)
        XCTAssertEqual(result.message.body, Data([0xaa, 0xbb, 0xcc, 0xdd]))
        XCTAssertEqual(result.consumedBytes, 18)
    }

    func testEncodingMatchesIndependentLiteralAndHonorsPayloadBudget() throws {
        let message = AppleFileCopyMessage(version: 2, command: 5,
                                          sessionID: 0x12345678,
                                          body: Data([0xaa, 0xbb, 0xcc, 0xdd]))
        XCTAssertEqual(try message.encode(), frame)
        XCTAssertEqual(try message.encode(maximumPayloadBytes: 12), frame)
        for limit in [Int.min, -1, 0, 7, 8, 11] {
            XCTAssertThrowsError(try message.encode(maximumPayloadBytes: limit)) { error in
                XCTAssertEqual(error as? AppleFileCopyMessage.Failure, .exceedsLimit)
            }
        }
        let empty = AppleFileCopyMessage(version: 1, command: 3,
                                        sessionID: UInt32.max, body: Data())
        XCTAssertEqual(try empty.encode(maximumPayloadBytes: 8),
                       Data([0x22, 0, 0, 0, 0, 8, 0, 1, 0, 3, 0xff, 0xff, 0xff, 0xff]))
    }

    func testCoalescedAndNonzeroIndexInputPreservesNextMessage() throws {
        let padded = Data([0xff, 0xff]) + frame + Data([0, 0, 0, 0])
        let slice = padded.dropFirst(2)
        let result = try XCTUnwrap(AppleFileCopyMessage.decode(slice))
        XCTAssertEqual(result.consumedBytes, frame.count)
        XCTAssertEqual(slice.dropFirst(result.consumedBytes), Data([0, 0, 0, 0]))
    }

    func testRejectsInvalidAndOversizedLengthBeforeWaitingForBody() {
        for length in [UInt32(0), 7, 1_048_577, UInt32.max] {
            let header = Data([0x22, 0,
                               UInt8(truncatingIfNeeded: length >> 24),
                               UInt8(truncatingIfNeeded: length >> 16),
                               UInt8(truncatingIfNeeded: length >> 8),
                               UInt8(truncatingIfNeeded: length)])
            XCTAssertThrowsError(try AppleFileCopyMessage.decode(header)) { error in
                XCTAssertEqual(error as? AppleFileCopyMessage.Failure,
                               length < 8 ? .invalidLength : .exceedsLimit)
            }
        }
        XCTAssertThrowsError(try AppleFileCopyMessage.decode(frame, maximumPayloadBytes: -1))
        XCTAssertThrowsError(try AppleFileCopyMessage.decode(Data([0x1f])))
    }

    func testEmptyBodyAndUnknownVersionCommandRemainRepresentable() throws {
        let literal = Data([0x22, 0, 0, 0, 0, 8,
                            0xff, 0xfe, 0xab, 0xcd, 0, 0, 0, 1])
        let result = try XCTUnwrap(AppleFileCopyMessage.decode(literal))
        XCTAssertEqual(result.message.version, 0xfffe)
        XCTAssertEqual(result.message.command, 0xabcd)
        XCTAssertTrue(result.message.body.isEmpty)
        XCTAssertEqual(result.consumedBytes, 14)
    }
}
