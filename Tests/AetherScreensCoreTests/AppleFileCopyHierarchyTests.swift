import XCTest
@testable import AetherScreensCore

final class AppleFileCopyHierarchyTests: XCTestCase {
    func testNestedDirectoriesSiblingAscentAndMultipleRoots() throws {
        var hierarchy = try AppleFileCopyHierarchy(maximumItems: 8)
        XCTAssertEqual(try hierarchy.append(level: 0, isDirectory: true), .init(index: 0, parentIndex: nil))
        XCTAssertEqual(try hierarchy.append(level: 1, isDirectory: true), .init(index: 1, parentIndex: 0))
        XCTAssertEqual(try hierarchy.append(level: 2, isDirectory: false), .init(index: 2, parentIndex: 1))
        XCTAssertEqual(try hierarchy.append(level: 1, isDirectory: false), .init(index: 3, parentIndex: 0))
        XCTAssertThrowsError(try hierarchy.append(level: 2, isDirectory: false))
        XCTAssertEqual(try hierarchy.append(level: 1, isDirectory: true), .init(index: 4, parentIndex: 0))
        XCTAssertEqual(try hierarchy.append(level: 2, isDirectory: false), .init(index: 5, parentIndex: 4))
        XCTAssertEqual(try hierarchy.append(level: 0, isDirectory: false), .init(index: 6, parentIndex: nil))
        XCTAssertThrowsError(try hierarchy.append(level: 1, isDirectory: false))
        XCTAssertEqual(try hierarchy.append(level: 0, isDirectory: true), .init(index: 7, parentIndex: nil))
        XCTAssertThrowsError(try hierarchy.append(level: 1, isDirectory: false))
    }

    func testLimitsAndRejectedEntriesDoNotAdvanceState() throws {
        XCTAssertThrowsError(try AppleFileCopyHierarchy(maximumDepth: -1, maximumItems: 1))
        XCTAssertThrowsError(try AppleFileCopyHierarchy(maximumItems: 0))
        var hierarchy = try AppleFileCopyHierarchy(maximumDepth: 1, maximumItems: 3)
        XCTAssertThrowsError(try hierarchy.append(level: 1, isDirectory: true))
        XCTAssertEqual(try hierarchy.append(level: 0, isDirectory: true).index, 0)
        XCTAssertThrowsError(try hierarchy.append(level: 2, isDirectory: true))
        XCTAssertEqual(try hierarchy.append(level: 1, isDirectory: false).parentIndex, 0)
    }
}
