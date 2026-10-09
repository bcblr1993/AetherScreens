import XCTest
@testable import AetherScreensCore

final class FileTransferRelativePathTests: XCTestCase {
    func testRejectsAbsoluteTraversalEmptyComponentsAndNul() {
        for path in ["", "/etc/passwd", "../outside", "folder/../outside", "./file",
                     "folder//file", "folder/", "folder/./file", "folder/\u{0}file"] {
            XCTAssertThrowsError(try FileTransferRelativePath(path), path)
        }
    }

    func testPreservesAppleFilenamesAndDoesNotDecodePercentEscapes() throws {
        let root = URL(fileURLWithPath: "/tmp/download-fixture", isDirectory: true)
        for filename in ["报告 你好.txt", "..%2Foutside", "literal%20space", "back\\slash.txt", "https:example"] {
            let entry = try FileTransferRelativePath("folder/" + filename)
            let destination = try entry.lexicalDestination(in: root)
            XCTAssertEqual(destination.deletingLastPathComponent().path, root.appendingPathComponent("folder").path)
            XCTAssertEqual(destination.lastPathComponent, filename)
            XCTAssertEqual(entry.components, ["folder", filename])
        }
    }

    func testManifestLimitsAndNonFileRoot() throws {
        XCTAssertThrowsError(try FileTransferRelativePath(String(repeating: "x", count: 65537)))
        XCTAssertThrowsError(try FileTransferRelativePath(Array(repeating: "d", count: 257).joined(separator: "/")))
        let entry = try FileTransferRelativePath("file")
        XCTAssertThrowsError(try entry.lexicalDestination(in: XCTUnwrap(URL(string: "https://example.com"))))
    }
}
