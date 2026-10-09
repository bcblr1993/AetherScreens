import XCTest
@testable import AetherScreensCore

final class AppleFileCopyServerStatusTests: XCTestCase {
    func testLiteralServerProgressDoesNotBecomeCompletion() throws {
        // Server's packed constant yields version 1 and command 300; body is
        // the big-endian bits of ratio 0.5, not percentage 50.
        let frame = Data([0x22, 0, 0, 0, 0, 16, 0, 1, 1, 0x2c,
                          0x12, 0x34, 0x56, 0x78,
                          0x3f, 0xe0, 0, 0, 0, 0, 0, 0])
        let envelope = try XCTUnwrap(AppleFileCopyMessage.decode(frame)).message
        XCTAssertEqual(try AppleFileCopyServerStatus.decode(envelope, expectedSessionID: 0x12345678),
                       .progress(fraction: 0.5))
        let full = AppleFileCopyMessage(version: 1, command: 300, sessionID: 1,
                                       body: Data([0x3f, 0xf0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(try AppleFileCopyServerStatus.decode(full, expectedSessionID: 1),
                       .progress(fraction: 1))
    }

    func testLiteralFinalStatusPreservesSignedErrorAndNameBytes() throws {
        let frame = Data([0x22, 0, 0, 0, 0, 16, 0, 1, 0, 200,
                          0, 0, 0, 1, 0xff, 0x9c, 0, 3, 0x61, 0xff, 0x62, 0])
        let envelope = try XCTUnwrap(AppleFileCopyMessage.decode(frame)).message
        XCTAssertEqual(try AppleFileCopyServerStatus.decode(envelope, expectedSessionID: 1),
                       .finished(errorCode: -100, destinationName: Data([0x61, 0xff, 0x62])))
        let emptyName = AppleFileCopyMessage(version: 1, command: 200, sessionID: 1,
                                            body: Data([0, 0, 0, 0, 0]))
        XCTAssertEqual(try AppleFileCopyServerStatus.decode(emptyName, expectedSessionID: 1),
                       .finished(errorCode: 0, destinationName: Data()))
    }

    func testUnrelatedSessionVersionAndCommandAreIgnored() throws {
        for message in [AppleFileCopyMessage(version: 1, command: 200, sessionID: 2, body: Data()),
                        AppleFileCopyMessage(version: 2, command: 200, sessionID: 1, body: Data()),
                        AppleFileCopyMessage(version: 1, command: 999, sessionID: 1, body: Data())] {
            XCTAssertNil(try AppleFileCopyServerStatus.decode(message, expectedSessionID: 1))
        }
    }

    func testMalformedProgressAndFinalBodiesAreRejected() {
        for body in [Data(), Data([0x7f, 0xf8, 0, 0, 0, 0, 0, 0]),
                     Data([0x7f, 0xf0, 0, 0, 0, 0, 0, 0]),
                     Data([0xbf, 0xf0, 0, 0, 0, 0, 0, 0]),
                     Data([0x40, 0, 0, 0, 0, 0, 0, 0])] {
            XCTAssertThrowsError(try AppleFileCopyServerStatus.decode(
                AppleFileCopyMessage(version: 1, command: 300, sessionID: 1, body: body),
                expectedSessionID: 1))
        }
        for body in [Data(), Data([0, 0, 0, 1, 0]), Data([0, 0, 0, 0, 1]),
                     Data([0, 0, 0, 1, 0, 0]), Data([0, 0, 0, 0, 0, 0])] {
            XCTAssertThrowsError(try AppleFileCopyServerStatus.decode(
                AppleFileCopyMessage(version: 1, command: 200, sessionID: 1, body: body),
                expectedSessionID: 1))
        }
    }
}
