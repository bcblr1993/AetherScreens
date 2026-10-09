import XCTest
@testable import AetherScreensCore

final class AppleFileCopyDiskSpaceTests: XCTestCase {
    func testSpaceBudgetIncludesPayloadMetadataAndReserveAndRejectsOverflow() throws {
        let expected: UInt64 = 1024 + 2 * 4096 + 1_048_576
        XCTAssertEqual(try AppleFileCopyDiskSpace.requiredBytes(payloadBytes: 1024, itemCount: 2), expected)
        XCTAssertNoThrow(try AppleFileCopyDiskSpace.require(availableBytes: expected, payloadBytes: 1024, itemCount: 2))
        XCTAssertThrowsError(try AppleFileCopyDiskSpace.require(availableBytes: expected - 1, payloadBytes: 1024, itemCount: 2))
        XCTAssertThrowsError(try AppleFileCopyDiskSpace.requiredBytes(payloadBytes: UInt64.max, itemCount: 1))
        XCTAssertThrowsError(try AppleFileCopyDiskSpace.requiredBytes(payloadBytes: 0, itemCount: 0))
    }
    func testVolumeInspectionDoesNotCreateFilesAndRejectsMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("space-budget-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try AppleFileCopyDiskSpace.check(directory: root, payloadBytes: 0, itemCount: 1))
        XCTAssertThrowsError(try AppleFileCopyDiskSpace.check(directory: root.appendingPathComponent("absent"), payloadBytes: 0, itemCount: 1))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
}
