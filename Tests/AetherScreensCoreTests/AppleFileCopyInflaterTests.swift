import XCTest
@testable import AetherScreensCore

final class AppleFileCopyInflaterTests: XCTestCase {
    func testPersistentDictionaryAcrossBlocksAndInterleavedRawData() throws {
        let deflater = try ZRLETestDeflater()
        let first = Data((0..<65536).map { UInt8(truncatingIfNeeded: $0 * 37) })
        let second = first.suffix(32768)
        let packets = try [first, Data(second)].map { try deflater.compress($0) }
        let inflater = AppleFileCopyInflater()
        XCTAssertEqual(try inflater.expand(.compressed(algorithm: 1, expandedBytes: UInt32(first.count), payload: packets[0])), first)
        XCTAssertEqual(try inflater.expand(.raw(Data([0, 255, 1]))), Data([0, 255, 1]))
        XCTAssertEqual(try inflater.expand(.compressed(algorithm: 1, expandedBytes: UInt32(second.count), payload: packets[1])), Data(second))
        // A continuation packet cannot be independently inflated.
        XCTAssertThrowsError(try AppleFileCopyInflater().expand(
            .compressed(algorithm: 1, expandedBytes: UInt32(second.count), payload: packets[1])))
    }

    func testDishonestExpansionInvalidatesContextWithoutPartialOutput() throws {
        let packet = try ZRLETestDeflater().compress(Data(repeating: 0xaa, count: 100_000))
        for declared in [UInt32(1), 99_999, 100_001] {
            let inflater = AppleFileCopyInflater()
            XCTAssertThrowsError(try inflater.expand(.compressed(algorithm: 1, expandedBytes: declared, payload: packet)))
            XCTAssertThrowsError(try inflater.expand(.raw(Data([1])))) { error in
                XCTAssertEqual(error as? AppleFileCopyInflater.Failure, .unavailable)
            }
        }
    }

    func testTruncatedCorruptAndTrailingCompressedBytesAreRejected() throws {
        let packet = try ZRLETestDeflater().compress(Data([1, 2, 3, 4]))
        for invalid in [Data(packet.dropLast()), packet + Data([0]), Data([0, 0, 255, 255])] {
            XCTAssertThrowsError(try AppleFileCopyInflater().expand(
                .compressed(algorithm: 1, expandedBytes: 4, payload: invalid)))
        }
    }

    func testExpansionBudgetIsCheckedBeforeAllocation() {
        for block in [AppleFileCopyDataBlock.raw(Data([1, 2])),
                      .compressed(algorithm: 1, expandedBytes: UInt32.max, payload: Data([1]))] {
            XCTAssertThrowsError(try AppleFileCopyInflater(maximumBytes: 1).expand(block)) { error in
                XCTAssertEqual(error as? AppleFileCopyInflater.Failure, .exceedsLimit)
            }
        }
    }
}
