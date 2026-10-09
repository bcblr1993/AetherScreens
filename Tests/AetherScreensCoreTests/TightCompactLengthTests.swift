import XCTest
@testable import AetherScreensCore

final class TightCompactLengthTests: XCTestCase {
    func testProtocolExamplesAndByteBoundaries() throws {
        let cases: [([UInt8], Int)] = [
            ([0], 0), ([0x7f], 127), ([0x80, 1], 128),
            ([0x90, 0x4e], 10_000), ([0xff, 0x7f], 16_383),
            ([0x80, 0x80, 1], 16_384),
            ([0x80, 0x80, 0x80], 2_097_152),
            ([0xff, 0xff, 0xff], 4_194_303)
        ]
        for (bytes, expected) in cases {
            let result = try XCTUnwrap(TightCompactLength.parse(Data(bytes)))
            XCTAssertEqual(result.value, expected)
            XCTAssertEqual(result.bytesConsumed, bytes.count)
        }
    }

    func testIncompletePrefixesDoNotConsumePayload() throws {
        for bytes: [UInt8] in [[], [0x80], [0xff], [0x80, 0x80], [0xff, 0xff]] {
            XCTAssertNil(TightCompactLength.parse(Data(bytes)))
        }
        let result = try XCTUnwrap(TightCompactLength.parse(Data([0x90, 0x4e, 0xff, 0xff])))
        XCTAssertEqual(result.value, 10_000)
        XCTAssertEqual(result.bytesConsumed, 2)
        // Sliced buffers may have a nonzero startIndex.
        let slice = Data([42, 0xff, 0xff, 0xff, 42]).dropFirst()
        XCTAssertEqual(TightCompactLength.parse(slice)?.value, TightCompactLength.maximum)
        XCTAssertEqual(TightCompactLength.parse(slice)?.bytesConsumed, 3)
    }
}
