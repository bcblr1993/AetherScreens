import XCTest
@testable import AetherScreensCore

final class AppleFileCopyStartTests: XCTestCase {
    func testEncodingPreservesLiteralFramingAndBoundsBeforeAllocation() throws {
        let start = AppleFileCopyStart(direction: .serverReceives, flags: 0x01020304,
            reserved: Data([9, 8, 7, 6]), path: Data([47, 255, 65]), trailingBytes: Data([99]))
        let encoded = try start.message(sessionID: 42)
        XCTAssertEqual(encoded.command, 2)
        XCTAssertEqual(encoded.sessionID, 42)
        XCTAssertEqual(encoded.body, Data([1, 2, 3, 4, 9, 8, 7, 6, 0, 3, 47, 255, 65, 0, 99]))
        XCTAssertEqual(try AppleFileCopyStart.decode(encoded, expectedSessionID: 42), start)
        for path in [Data([65, 0]), Data(repeating: 65, count: 65536)] {
            XCTAssertThrowsError(try AppleFileCopyStart(direction: .serverSends, flags: 0,
                reserved: Data(repeating: 0, count: 4), path: path, trailingBytes: Data()).message(sessionID: 7))
        }
        XCTAssertThrowsError(try AppleFileCopyStart(direction: .serverSends, flags: 0,
            reserved: Data(), path: Data(), trailingBytes: Data()).message(sessionID: 7))
    }

    private func message(_ body: Data, command: UInt16 = 1, version: UInt16 = 1) -> AppleFileCopyMessage {
        AppleFileCopyMessage(version: version, command: command, sessionID: 7, body: body)
    }

    func testDirectionsAndOpaqueFieldsArePreserved() throws {
        let body = Data([0x80, 0, 0, 1, 0xaa, 0xbb, 0xcc, 0xdd, 0, 3,
                         0x2f, 0xff, 0x61, 0, 0xfe])
        let send = try XCTUnwrap(AppleFileCopyStart.decode(message(body), expectedSessionID: 7))
        XCTAssertEqual(send.direction, .serverSends)
        XCTAssertEqual(send.flags, 0x80000001)
        XCTAssertEqual(send.reserved, Data([0xaa, 0xbb, 0xcc, 0xdd]))
        XCTAssertEqual(send.path, Data([0x2f, 0xff, 0x61]))
        XCTAssertEqual(send.trailingBytes, Data([0xfe]))
        let receive = try XCTUnwrap(AppleFileCopyStart.decode(message(body, command: 2), expectedSessionID: 7))
        XCTAssertEqual(receive.direction, .serverReceives)
        XCTAssertEqual(receive.path, send.path)
    }

    func testLengthAndNullTerminationAreValidatedBeforeExposingPath() throws {
        let valid = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0x61, 0x62, 0x63, 0])
        for count in 0..<valid.count {
            XCTAssertThrowsError(try AppleFileCopyStart.decode(message(valid.prefix(count)), expectedSessionID: 7))
        }
        var malformed = valid
        malformed[11] = 0
        XCTAssertThrowsError(try AppleFileCopyStart.decode(message(malformed), expectedSessionID: 7))
        malformed = valid; malformed[13] = 1
        XCTAssertThrowsError(try AppleFileCopyStart.decode(message(malformed), expectedSessionID: 7))
        malformed = valid; malformed[8] = 0xff; malformed[9] = 0xff
        XCTAssertThrowsError(try AppleFileCopyStart.decode(message(malformed), expectedSessionID: 7))
    }

    func testEmptyPathAndUnrelatedMessagesDoNotInventDestinationSemantics() throws {
        let body = Data(repeating: 0, count: 11)
        XCTAssertEqual(try AppleFileCopyStart.decode(message(body), expectedSessionID: 7)?.path, Data())
        XCTAssertNil(try AppleFileCopyStart.decode(message(body), expectedSessionID: 8))
        XCTAssertNil(try AppleFileCopyStart.decode(message(body, version: 2), expectedSessionID: 7))
        XCTAssertNil(try AppleFileCopyStart.decode(message(body, command: 3), expectedSessionID: 7))
    }
}
