import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopyCancellableTreeCopyTests: XCTestCase {
    func testCancellationDuringDataCopyLeavesSourceIntact() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("copy")
        let data = Data(repeating: 0xab, count: 8 * 1_048_576)
        try data.write(to: source)
        let flag = CopyProgressCancellation()
        XCTAssertThrowsError(try AppleFileCopyCancellableTreeCopy.copy(from: source, to: destination,
            isCancelled: { flag.cancelled }, onProgress: { if $0 > 0 { flag.cancel(afterCopied: $0) } })) { error in
                guard case AppleFileCopyCancellableTreeCopy.Failure.cancelled = error else {
                    return XCTFail("Must report explicit cancellation")
                }
            }
        XCTAssertGreaterThan(flag.copiedBytes, 0)
        XCTAssertLessThan(flag.copiedBytes, UInt64(data.count))
        if FileManager.default.fileExists(atPath: destination.path) {
            let partial = try Data(contentsOf: destination)
            XCTAssertLessThan(partial.count, data.count)
            XCTAssertEqual(partial, Data(data.prefix(partial.count)))
        }
        XCTAssertEqual(try Data(contentsOf: source), data)
    }

    func testCopiesNestedTreeResourceAndAttributesAndRejectsExistingDestination() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let file = source.appendingPathComponent("文件.bin")
        try Data([1,2,3]).write(to: file)
        let resource = Data([9,8,7])
        try resource.write(to: file.appendingPathComponent("..namedfork/rsrc"))
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return XCTFail("Cannot open fixture") }
        defer { close(descriptor) }
        let attribute = Data([5,4,3])
        XCTAssertEqual(attribute.withUnsafeBytes { fsetxattr(descriptor, "com.aethernative.qa", $0.baseAddress, $0.count, 0, 0) }, 0)
        try AppleFileCopyCancellableTreeCopy.copy(from: source, to: destination)
        let saved = destination.appendingPathComponent("文件.bin")
        XCTAssertEqual(try Data(contentsOf: saved), Data([1,2,3]))
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("..namedfork/rsrc")), resource)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("empty").path), [])
        let savedDescriptor = open(saved.path, O_RDONLY | O_NOFOLLOW)
        guard savedDescriptor >= 0 else { return XCTFail("Cannot open copied fixture") }
        defer { close(savedDescriptor) }
        var observed = Data(count: 3)
        XCTAssertEqual(observed.withUnsafeMutableBytes { fgetxattr(savedDescriptor, "com.aethernative.qa", $0.baseAddress, $0.count, 0, 0) }, 3)
        XCTAssertEqual(observed, attribute)
        XCTAssertThrowsError(try AppleFileCopyCancellableTreeCopy.copy(from: source, to: destination))
        XCTAssertEqual(try Data(contentsOf: saved), Data([1,2,3]))
    }

    func testPreCancelledCopyDoesNotCreateDestination() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("copy")
        try Data([1]).write(to: source)
        XCTAssertThrowsError(try AppleFileCopyCancellableTreeCopy.copy(from: source, to: destination, isCancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cancellable-copy-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}

private final class CopyProgressCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var count: UInt64 = 0
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    var copiedBytes: UInt64 { lock.lock(); defer { lock.unlock() }; return count }
    func cancel(afterCopied bytes: UInt64) { lock.lock(); count = bytes; value = true; lock.unlock() }
}
