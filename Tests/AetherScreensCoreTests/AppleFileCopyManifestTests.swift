import XCTest
@testable import AetherScreensCore

final class AppleFileCopyManifestTests: XCTestCase {
    private func item(_ name: String, level: UInt16, directory: Bool = false, extra: Int = 0) -> AppleFileCopyItem {
        var header = Data(repeating: 0, count: 104)
        if directory { header[91] = 0x10 }
        return .init(catalogHeader: header, level: level, wireName: name,
                     symbolicLinkTarget: nil, extensions: Data(repeating: 7, count: extra))
    }

    func testNestedPathsPreserveLegacyNamesAndBranchAscent() throws {
        var manifest = try AppleFileCopyManifest(maximumItems: 5)
        try manifest.append(item("报告", level: 0, directory: true))
        try manifest.append(item("2026", level: 1, directory: true))
        let nested = try manifest.append(item("A/B%2F.txt", level: 2, extra: 3))
        XCTAssertEqual(nested.path.components, ["报告", "2026", "A:B%2F.txt"])
        XCTAssertEqual(nested.parentIndex, 1)
        XCTAssertEqual(nested.item.extensions, Data([7, 7, 7]))
        XCTAssertEqual(try manifest.append(item("sibling", level: 1)).path.path, "报告/sibling")
        XCTAssertThrowsError(try manifest.append(item("orphan", level: 2)))
        XCTAssertEqual(try manifest.append(item("new-root", level: 0)).path.path, "new-root")
        XCTAssertEqual(manifest.entries.count, 5)
    }

    func testFailedBudgetOrNameDoesNotConsumeStructuralSlot() throws {
        var manifest = try AppleFileCopyManifest(maximumItems: 2, maximumMetadataBytes: 230)
        XCTAssertThrowsError(try manifest.append(item("bad:colon", level: 0)))
        XCTAssertThrowsError(try manifest.append(item("large", level: 0, directory: true, extra: 231)))
        XCTAssertTrue(manifest.entries.isEmpty)
        try manifest.append(item("A", level: 0, directory: true))
        XCTAssertThrowsError(try manifest.append(item("orphan", level: 2)))
        XCTAssertEqual(try manifest.append(item("B", level: 1)).path.path, "A/B")
        XCTAssertEqual(manifest.entries.count, 2)
    }
}
