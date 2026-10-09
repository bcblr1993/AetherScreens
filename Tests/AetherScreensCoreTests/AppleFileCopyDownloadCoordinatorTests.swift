#if os(macOS)
import XCTest
@testable import AetherScreensCore

@MainActor
final class AppleFileCopyDownloadCoordinatorTests: XCTestCase {
    private func fixture() throws -> (URL, URL, AppleFileCopyItem) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("download-owner-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("file.bin")
        try Data([1,2,3]).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640,
            .creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            .modificationDate: Date(timeIntervalSince1970: 1_700_000_100)], ofItemAtPath: source.path)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return (root, destination, try AppleFileCopySourceCollector.collect(url: source, level: 0).item)
    }
    private func request() throws -> AppleFileCopyMessage {
        try AppleFileCopyStart(direction: .serverSends, flags: 1, reserved: Data(repeating: 0, count: 4),
            path: Data("/tmp/explicit-source".utf8), trailingBytes: Data()).message(sessionID: 7)
    }
    private func deliver(_ item: AppleFileCopyItem, to worker: AppleFileCopyReceiveWorker) throws {
        XCTAssertTrue(worker.enqueue(try item.message(sessionID: 7)))
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 102, sessionID: 7, body: Data([0,0,0,3,1,2,3]))))
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))))
    }

    func testPersistedDownloadBytesPublishBeforeFinalCommit() async throws {
        let (root, destination, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileTransferTaskStore()
        var installed: AppleFileCopyReceiveWorker?
        let owner = AppleFileCopyDownloadCoordinator(store: store, backend: .init(transport: {
            { _, done in done(true); return true }
        }, install: { installed = $0; return true }, remove: { _ in }))
        let stopped = expectation(description: "Receive worker stopped")
        let progressed = expectation(description: "Persisted bytes published")
        progressed.assertForOverFulfill = false
        let observation = store.$jobs.sink { jobs in
            if jobs.first?.transferredBytes == 3 { progressed.fulfill() }
        }
        defer { observation.cancel(); store.cancelAll() }
        XCTAssertTrue(try owner.start(filename: "requested", request: request(), destination: destination,
            onStopped: { stopped.fulfill() }))
        let worker = try XCTUnwrap(installed)
        XCTAssertTrue(worker.enqueue(try item.message(sessionID: 7)))
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 102, sessionID: 7, body: Data([0,0,0,3,1,2,3]))))
        await fulfillment(of: [progressed], timeout: 3)
        XCTAssertEqual(store.jobs[0].state, .transferring)
        XCTAssertFalse(store.jobs[0].isSizeKnown)
        XCTAssertNil(store.savedFile(for: store.jobs[0].id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
        XCTAssertTrue(store.cancel(store.jobs[0].id))
        await fulfillment(of: [stopped], timeout: 3)
        XCTAssertEqual(store.jobs[0].state, .cancelled)
    }

    func testCompletionRequiresActualCommitAndCountsTheFinalBlock() async throws {
        let (root, destination, item) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FileTransferTaskStore()
        var installed: AppleFileCopyReceiveWorker?
        var released = 0
        let removed = expectation(description: "Download owner released")
        let owner = AppleFileCopyDownloadCoordinator(store: store, backend: .init(transport: {
            { _, done in done(true); return true }
        }, install: { installed = $0; return true }, remove: { _ in removed.fulfill() }))
        XCTAssertTrue(try owner.start(filename: "requested", request: request(), destination: destination,
                                     onReleased: { released += 1 }))
        XCTAssertFalse(store.jobs[0].isSizeKnown)
        try deliver(item, to: try XCTUnwrap(installed))
        await fulfillment(of: [removed], timeout: 3)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("file.bin")), Data([1,2,3]))
        let savedAttributes = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("file.bin").path)
        XCTAssertEqual((savedAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        let savedDate = try XCTUnwrap(savedAttributes[.modificationDate] as? Date)
        XCTAssertEqual(savedDate.timeIntervalSince1970, 1_700_000_100, accuracy: 1.0 / 65_536)
        XCTAssertEqual(store.jobs[0].state, .completed)
        XCTAssertEqual(store.jobs[0].totalBytes, 3)
        XCTAssertEqual(store.jobs[0].transferredBytes, 3)
        XCTAssertEqual(store.displayFilename(for: store.jobs[0]), "file.bin")
        XCTAssertEqual(store.savedFile(for: store.jobs[0].id),
            .init(url: destination.appendingPathComponent("file.bin"), accessRoot: destination))
        store.cancelAll()
        XCTAssertEqual(released, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["file.bin"])
    }

    func testConflictPreservesExistingFileAndCleansStaging() async throws {
        let (root, destination, item) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let existing = destination.appendingPathComponent("file.bin")
        try Data([9]).write(to: existing)
        let store = FileTransferTaskStore()
        var installed: AppleFileCopyReceiveWorker?
        let removed = expectation(description: "Conflicting download released")
        let owner = AppleFileCopyDownloadCoordinator(store: store, backend: .init(transport: {
            { _, done in done(true); return true }
        }, install: { installed = $0; return true }, remove: { _ in removed.fulfill() }))
        XCTAssertTrue(try owner.start(filename: "requested", request: request(), destination: destination))
        try deliver(item, to: try XCTUnwrap(installed))
        await fulfillment(of: [removed], timeout: 3)
        guard case .failed = store.jobs[0].state else { return XCTFail("Commit conflict must fail") }
        XCTAssertNil(store.savedFile(for: store.jobs[0].id))
        XCTAssertEqual(try Data(contentsOf: existing), Data([9]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["file.bin"])
    }

    func testDirectoryCommitPreservesNestedFilesEmptyFoldersAndResourceFork() async throws {
        let (root, destination, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = root.appendingPathComponent("目录 📁")
        let nested = tree.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("empty"), withIntermediateDirectories: false)
        let file = nested.appendingPathComponent("文件.bin")
        let bytes = Data([1, 2, 3])
        let resource = Data([9, 8, 7, 6])
        try bytes.write(to: file)
        try resource.write(to: file.appendingPathComponent("..namedfork/rsrc"))
        let prepared = try AppleFileCopyUploadPreparation.collect(url: tree)
        let store = FileTransferTaskStore()
        var installed: AppleFileCopyReceiveWorker?
        let removed = expectation(description: "Directory download committed")
        let owner = AppleFileCopyDownloadCoordinator(store: store, backend: .init(transport: {
            { _, done in done(true); return true }
        }, install: { installed = $0; return true }, remove: { _ in removed.fulfill() }))
        XCTAssertTrue(try owner.start(filename: "requested", request: request(), destination: destination))
        let worker = try XCTUnwrap(installed)
        for source in prepared.sources {
            XCTAssertTrue(worker.enqueue(try source.item.message(sessionID: 7)))
            for fork in [source.dataURL, source.resourceURL].compactMap({ $0 }) {
                let payload = try Data(contentsOf: fork)
                if !payload.isEmpty {
                    var body = Data([UInt8(payload.count >> 24), UInt8((payload.count >> 16) & 255),
                                     UInt8((payload.count >> 8) & 255), UInt8(payload.count & 255)])
                    body.append(payload)
                    XCTAssertTrue(worker.enqueue(.init(version: 1, command: 102, sessionID: 7, body: body)))
                }
            }
        }
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))))
        await fulfillment(of: [removed], timeout: 3)
        let saved = destination.appendingPathComponent(tree.lastPathComponent)
        let savedFile = saved.appendingPathComponent("nested/文件.bin")
        XCTAssertEqual(store.jobs[0].state, .completed)
        XCTAssertEqual(store.jobs[0].totalBytes, 7)
        XCTAssertEqual(store.displayFilename(for: store.jobs[0]), tree.lastPathComponent)
        let location = try XCTUnwrap(store.savedFile(for: store.jobs[0].id))
        XCTAssertEqual(location.url.path, saved.path)
        XCTAssertEqual(location.accessRoot, destination)
        XCTAssertEqual(try location.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
        XCTAssertEqual(try Data(contentsOf: savedFile), bytes)
        XCTAssertEqual(try Data(contentsOf: savedFile.appendingPathComponent("..namedfork/rsrc")), resource)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: saved.appendingPathComponent("empty").path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [tree.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertFalse(owner.isBusy)
    }

    func testMissingStartWriteExpiresEvenIfServerDataWasSaved() async throws {
        let (root, destination, item) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = FileTransferTaskStore()
        var installed: AppleFileCopyReceiveWorker?
        let removed = expectation(description: "Start write deadline released owner")
        let owner = AppleFileCopyDownloadCoordinator(store: store, backend: .init(transport: {
            { _, _ in true } // Never confirm the start write.
        }, install: { installed = $0; return true }, remove: { _ in removed.fulfill() }))
        XCTAssertTrue(try owner.start(filename: "requested", request: request(), destination: destination, writeTimeout: 1))
        try deliver(item, to: try XCTUnwrap(installed))
        await fulfillment(of: [removed], timeout: 3)
        guard case .failed = store.jobs[0].state else { return XCTFail("Missing start confirmation must not complete") }
        XCTAssertFalse(store.jobs[0].isSizeKnown)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("file.bin")), Data([1,2,3]))
    }
}
#endif
