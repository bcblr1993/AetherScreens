import XCTest
@testable import AetherScreensCore

final class AppleFileCopyEndSessionTests: XCTestCase {
    func testLiteralEndResultPreservesFailureBytes() throws {
        let wire = Data([0x22, 0, 0, 0, 0, 12, 0, 1, 0, 104, 0, 0, 0, 7,
                         0x9c, 0xff, 0xff, 0xff])
        let message = try XCTUnwrap(AppleFileCopyMessage.decode(wire)).message
        XCTAssertEqual(try AppleFileCopyEndSession.decode(message, expectedSessionID: 7),
                       .failure(rawError: Data([0x9c, 0xff, 0xff, 0xff])))
        let success = AppleFileCopyMessage(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))
        XCTAssertEqual(try AppleFileCopyEndSession.decode(success, expectedSessionID: 7), .success)
    }

    func testMissingResultAndMalformedBodiesCannotBecomeSuccess() throws {
        for count in 0...5 {
            let message = AppleFileCopyMessage(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: count))
            if count == 0 {
                XCTAssertEqual(try AppleFileCopyEndSession.decode(message, expectedSessionID: 7), .resultAbsent)
            } else if count != 4 {
                XCTAssertThrowsError(try AppleFileCopyEndSession.decode(message, expectedSessionID: 7))
            }
        }
        for bytes: [UInt8] in [[1, 0, 0, 0], [0, 0, 0, 1], [0, 0x80, 0, 0]] {
            let message = AppleFileCopyMessage(version: 1, command: 104, sessionID: 7, body: Data(bytes))
            XCTAssertEqual(try AppleFileCopyEndSession.decode(message, expectedSessionID: 7), .failure(rawError: Data(bytes)))
            XCTAssertNil(try AppleFileCopyEndSession.decode(message, expectedSessionID: 8))
        }
        for (version, command): (UInt16, UInt16) in [(2, 104), (1, 200)] {
            let message = AppleFileCopyMessage(version: version, command: command, sessionID: 7, body: Data())
            XCTAssertNil(try AppleFileCopyEndSession.decode(message, expectedSessionID: 7))
        }
    }
}
