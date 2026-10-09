import XCTest
@testable import AetherScreensCore

final class AppleFileCopyForkProgressTests: XCTestCase {
    func testDataCompletesBeforeResourceAndTransferIsNotFinishedEarly() throws {
        var progress = AppleFileCopyForkProgress(dataBytes: 5, resourceBytes: 3)
        XCTAssertEqual(progress.activeFork, .data)
        try progress.acknowledgeWrittenBytes(2)
        XCTAssertEqual(progress.remainingInActiveFork, 3)
        try progress.acknowledgeWrittenBytes(3)
        XCTAssertEqual(progress.activeFork, .resource)
        XCTAssertFalse(progress.isComplete)
        try progress.acknowledgeWrittenBytes(3)
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.activeFork)
    }

    func testBlockCannotSpanForkBoundaryAndFailureDoesNotAdvanceProgress() throws {
        var progress = AppleFileCopyForkProgress(dataBytes: 2, resourceBytes: 8)
        let original = progress
        XCTAssertThrowsError(try progress.acknowledgeWrittenBytes(3))
        XCTAssertThrowsError(try progress.acknowledgeWrittenBytes(0))
        XCTAssertEqual(progress, original)
        try progress.acknowledgeWrittenBytes(2)
        try progress.acknowledgeWrittenBytes(8)
        XCTAssertThrowsError(try progress.acknowledgeWrittenBytes(1))
        XCTAssertTrue(progress.isComplete)
    }

    func testZeroLengthForksAndUnsignedSizesDoNotRequireCombinedSizeArithmetic() throws {
        var resourceOnly = AppleFileCopyForkProgress(dataBytes: 0, resourceBytes: 1)
        XCTAssertEqual(resourceOnly.activeFork, .resource)
        try resourceOnly.acknowledgeWrittenBytes(1)
        XCTAssertTrue(resourceOnly.isComplete)
        XCTAssertTrue(AppleFileCopyForkProgress(dataBytes: 0, resourceBytes: 0).isComplete)
        var large = AppleFileCopyForkProgress(dataBytes: UInt64.max, resourceBytes: UInt64.max)
        try large.acknowledgeWrittenBytes(UInt64.max)
        XCTAssertEqual(large.activeFork, .resource)
        XCTAssertEqual(large.remainingInActiveFork, UInt64.max)
        try large.acknowledgeWrittenBytes(UInt64.max)
        XCTAssertTrue(large.isComplete)
    }
}
