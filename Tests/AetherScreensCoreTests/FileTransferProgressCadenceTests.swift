import XCTest
@testable import AetherScreensCore

final class FileTransferProgressCadenceTests: XCTestCase {
    func testThousandBlocksWithinOneSecondHaveBoundedPresentationUpdates() {
        var cadence = FileTransferProgressCadence()
        var publications = 0
        for block in 1...1000 {
            if cadence.shouldPublish(bytes: UInt64(block * 65536), now: Double(block - 1) / 1000) {
                publications += 1
            }
        }
        XCTAssertGreaterThanOrEqual(publications, 9)
        XCTAssertLessThanOrEqual(publications, 10)
        XCTAssertTrue(cadence.shouldPublish(bytes: 65_536_001, now: 2))
    }

    func testUnchangedRegressingAndInvalidSamplesDoNotPublish() {
        var cadence = FileTransferProgressCadence()
        XCTAssertFalse(cadence.shouldPublish(bytes: 0, now: 0))
        XCTAssertFalse(cadence.shouldPublish(bytes: 1, now: .nan))
        XCTAssertFalse(cadence.shouldPublish(bytes: 1, now: .infinity))
        XCTAssertTrue(cadence.shouldPublish(bytes: 1, now: 0))
        for time in 1...100 { XCTAssertFalse(cadence.shouldPublish(bytes: 1, now: Double(time))) }
        XCTAssertTrue(cadence.shouldPublish(bytes: 2, now: 101))
        XCTAssertFalse(cadence.shouldPublish(bytes: 1, now: 102))
        XCTAssertFalse(cadence.shouldPublish(bytes: 3, now: 100))
        XCTAssertTrue(cadence.shouldPublish(bytes: 3, now: 103))
    }
}
