#if os(macOS)
import XCTest
@testable import AetherScreensCore

final class AppleFileCopyUploadSnapshotTests: XCTestCase {
    func testSnapshotPreservesTreeAndForksAndSurvivesSourceChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("file.bin")
        try Data([1,2,3]).write(to: file)
        try Data([4,5]).write(to: file.appendingPathComponent("..namedfork/rsrc"))
        try Data().write(to: directory.appendingPathComponent("empty"))
        let original = try AppleFileCopySourceCollector.collect(url: file, level: 1)
        let snapshot = try AppleFileCopyUploadSnapshot.prepare(url: directory)
        defer { snapshot.remove() }
        XCTAssertEqual(snapshot.prepared.logicalBytes, 5)
        XCTAssertEqual(snapshot.prepared.sources.count, 3)
        let source = try XCTUnwrap(snapshot.prepared.sources.first { $0.item.wireName == "file.bin" })
        let copied = try XCTUnwrap(source.dataURL)
        XCTAssertNotEqual(copied, file)
        XCTAssertEqual(source.item, original.item)
        XCTAssertEqual(try Data(contentsOf: copied), Data([1,2,3]))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(source.resourceURL)), Data([4,5]))
        try Data([9,9,9]).write(to: file)
        XCTAssertEqual(try Data(contentsOf: copied), Data([1,2,3]))
        snapshot.remove()
        snapshot.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: file), Data([9,9,9]))
    }

    func testBackgroundCleanupReturnsBeforeRemovalAndRetainsOwnedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-background-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data([1,2,3]).write(to: file)
        var snapshot: AppleFileCopyUploadSnapshot? = try .prepare(url: file)
        weak var retained = snapshot
        let copy = try XCTUnwrap(snapshot?.prepared.sources.first?.dataURL)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let queue = DispatchQueue(label: "snapshot-cleanup-test", qos: .utility)
        queue.async { gate.wait() }
        let removed = expectation(description: "Background cleanup executed")
        snapshot?.removeInBackground(queue: queue) { removed.fulfill() }
        snapshot = nil
        XCTAssertNotNil(retained)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        gate.signal()
        wait(for: [removed], timeout: 3)
        queue.sync {} // Drain the retaining closure before checking deallocation.
        XCTAssertNil(retained)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try Data(contentsOf: file), Data([1,2,3]))
    }

    func testCancellationDuringSnapshotCopyPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        let data = Data(repeating: 0xab, count: 8 * 1_048_576)
        try data.write(to: file)
        let flag = SnapshotCopyCancellation()
        let staging = SnapshotStagingObservation()
        XCTAssertThrowsError(try AppleFileCopyUploadSnapshot.prepare(url: file,
            isCancelled: { flag.isCancelled }, onCopyProgress: { flag.cancel(bytes: $0) },
            checkSpace: { directory, bytes, count in
                staging.record(directory)
                try AppleFileCopyDiskSpace.check(directory: directory, payloadBytes: bytes, itemCount: count)
            })) { error in
                guard case AppleFileCopyUploadPreparation.Failure.cancelled = error else {
                    return XCTFail("Expected snapshot cancellation")
                }
            }
        XCTAssertGreaterThan(flag.bytes, 0)
        XCTAssertLessThan(flag.bytes, UInt64(data.count))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(staging.url).path))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testInsufficientSnapshotSpaceStopsBeforeCopyAndPreservesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-space-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        let data = Data([1, 2, 3])
        try data.write(to: file)
        let staging = SnapshotStagingObservation()
        XCTAssertThrowsError(try AppleFileCopyUploadSnapshot.prepare(url: file,
            onCopyProgress: { _ in XCTFail("Space rejection must precede data copying") },
            checkSpace: { directory, bytes, count in
                staging.record(directory)
                XCTAssertTrue(directory.lastPathComponent.hasPrefix("aetherscreens-upload-snapshot-"))
                XCTAssertGreaterThanOrEqual(bytes, UInt64(data.count))
                XCTAssertEqual(count, 1)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
                throw AppleFileCopyDiskSpace.Failure.insufficientSpace
            })) { error in
                guard case AppleFileCopyDiskSpace.Failure.insufficientSpace = error else {
                    return XCTFail("Must retain specific space error")
                }
            }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(staging.url).path))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testCancellationAndLimitsDoNotReturnPartialSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-limit-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file")
        try Data([1,2,3]).write(to: file)
        XCTAssertThrowsError(try AppleFileCopyUploadSnapshot.prepare(url: file, maximumBytes: 2))
        XCTAssertThrowsError(try AppleFileCopyUploadSnapshot.prepare(url: file, isCancelled: { true }))
        XCTAssertEqual(try Data(contentsOf: file), Data([1,2,3]))
    }
}
private final class SnapshotCopyCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var copied: UInt64 = 0
    var bytes: UInt64 { lock.lock(); defer { lock.unlock() }; return copied }
    var isCancelled: Bool { bytes > 0 }
    func cancel(bytes: UInt64) { lock.lock(); copied = bytes; lock.unlock() }
}
private final class SnapshotStagingObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var observed: URL?
    var url: URL? { lock.lock(); defer { lock.unlock() }; return observed }
    func record(_ url: URL) { lock.lock(); observed = url; lock.unlock() }
}
#endif
