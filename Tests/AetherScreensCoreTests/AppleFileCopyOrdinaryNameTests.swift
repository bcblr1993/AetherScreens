import XCTest
@testable import AetherScreensCore

final class AppleFileCopyOrdinaryNameTests: XCTestCase {
    private func item(_ name: String, link: Data? = nil) -> AppleFileCopyItem {
        .init(catalogHeader: Data(repeating: 0, count: 104), level: 0,
              wireName: name, symbolicLinkTarget: link, extensions: Data())
    }

    func testLegacySlashBecomesLiteralColonWithoutPathTraversal() throws {
        let path = try AppleFileCopyOrdinaryName.destinationComponent(for: item("报告/2026%2F.txt"))
        XCTAssertEqual(path.components, ["报告:2026%2F.txt"])
        let root = URL(fileURLWithPath: "/tmp/name-fixture")
        let destination = try path.lexicalDestination(in: root)
        XCTAssertEqual(destination.deletingLastPathComponent().path, root.path)
        XCTAssertEqual(destination.lastPathComponent, "报告:2026%2F.txt")
    }

    func testInvalidNamesAndSymbolicLinkBranchAreRejected() throws {
        for name in ["", ".", "..", "literal:colon", "nul\u{0}name", String(repeating: "界", count: 256)] {
            XCTAssertThrowsError(try AppleFileCopyOrdinaryName.destinationComponent(for: item(name)))
        }
        XCTAssertNoThrow(try AppleFileCopyOrdinaryName.destinationComponent(for: item(String(repeating: "界", count: 255))))
        XCTAssertThrowsError(try AppleFileCopyOrdinaryName.destinationComponent(for: item("link", link: Data([65]))))
    }
}
