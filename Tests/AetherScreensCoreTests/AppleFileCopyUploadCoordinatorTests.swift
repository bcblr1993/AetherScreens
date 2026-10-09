import XCTest
@testable import AetherScreensCore

@MainActor
final class AppleFileCopyUploadCoordinatorTests: XCTestCase {
    private func fixture() throws -> (URL, AppleFileCopySendSession.Source) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("upload-owner-\(UUID())")
        try Data([0, 1, 2, 3, 4]).write(to: url)
        var header = Data(repeating: 0, count: 104)
        header[0] = 1; header[49] = 5
        return (url, .init(item: .init(catalogHeader: header, level: 0, wireName: "QA",
            symbolicLinkTarget: nil, extensions: Data()), dataURL: url, resourceURL: nil))
    }
    private func start() -> AppleFileCopyMessage {
        .init(version: 1, command: 2, sessionID: 7, body: Data())
    }
    private func totals() throws -> AppleFileCopyMessage {
        try AppleFileCopyItemInfo(rawHeaderValue: 0, reserved: Data(repeating: 0, count: 4),
            logicalBytes: 5, physicalBytes: 4096, fileCount: 1, forkCount: 1, folderCount: 0,
            allocationSize: 4096, trailing: Data()).message(sessionID: 7)
    }

    func testAuthoritativeResultCompletesStoreAndReleasesOwner() async throws {
        let (url, source) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileTransferTaskStore(), harness = UploadOwnerHarness()
        var releases = 0
        var installed: AppleFileCopySendWorker?
        let ended = expectation(description: "All local packets written")
        let removed = expectation(description: "Owner removed after terminal result")
        let coordinator = AppleFileCopyUploadCoordinator(store: store, backend: .init(transport: {
            { packet, done in harness.record(packet.command); done(true); if packet.command == 104 { ended.fulfill() }; return true }
        }, install: { installed = $0; return true }, remove: { worker in
            XCTAssertTrue(installed === worker); installed = nil; removed.fulfill()
        }))
        let job = FileTransferJob(direction: .upload, filename: "QA", totalBytes: 5)
        XCTAssertTrue(try coordinator.start(job: job, sources: [source], start: start(), totals: totals(), onReleased: { releases += 1 }))
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(store.jobs.first?.state, .transferring)
        XCTAssertEqual(store.jobs.first?.transferredBytes, 0)
        XCTAssertEqual(harness.commands, [2, 100, 101, 102, 104])
        XCTAssertTrue(installed!.enqueue(.init(version: 1, command: 200, sessionID: 7, body: Data([0,0,0,0,0]))))
        await fulfillment(of: [removed], timeout: 2)
        XCTAssertEqual(store.jobs.first?.state, .completed)
        XCTAssertEqual(store.jobs.first?.transferredBytes, 5)
        store.cancelAll()
        XCTAssertEqual(releases, 1)
    }

    func testStoreCancellationStopsPrefixAndSendsStop() async throws {
        let (url, source) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileTransferTaskStore(), harness = UploadOwnerHarness()
        let admitted = expectation(description: "Start pending")
        var removals = 0, releases = 0
        let coordinator = AppleFileCopyUploadCoordinator(store: store, backend: .init(transport: {
            { packet, done in harness.record(packet.command); harness.save(done); if packet.command == 2 { admitted.fulfill() }; return true }
        }, install: { _ in true }, remove: { _ in removals += 1 }))
        let job = FileTransferJob(direction: .upload, filename: "QA", totalBytes: 5)
        XCTAssertTrue(try coordinator.start(job: job, sources: [source], start: start(), totals: totals(), onReleased: { releases += 1 }))
        await fulfillment(of: [admitted], timeout: 2)
        XCTAssertTrue(store.cancel(job.id))
        harness.finishStart()
        XCTAssertEqual(harness.commands, [2, 5])
        XCTAssertEqual(removals, 1)
        XCTAssertEqual(store.jobs.first?.state, .cancelled)
        XCTAssertFalse(store.cancel(job.id))
        XCTAssertEqual(releases, 1)
    }

    func testIncorrectPreparedByteCountIsRejectedBeforeInstallation() throws {
        let (url, source) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let store = FileTransferTaskStore()
        let coordinator = AppleFileCopyUploadCoordinator(store: store, backend: .init(transport: {
            { _, _ in XCTFail("No packets expected"); return false }
        }, install: { _ in XCTFail("No owner expected"); return false }, remove: { _ in }))
        XCTAssertThrowsError(try coordinator.start(job: .init(direction: .upload, filename: "QA", totalBytes: 6),
            sources: [source], start: start(), totals: totals()))
        XCTAssertTrue(store.jobs.isEmpty)
    }
}
private final class UploadOwnerHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [UInt16] = []
    private var callbacks: [@Sendable (Bool) -> Void] = []
    var commands: [UInt16] { lock.lock(); defer { lock.unlock() }; return packets }
    func record(_ command: UInt16) { lock.lock(); packets.append(command); lock.unlock() }
    func save(_ done: @escaping @Sendable (Bool) -> Void) { lock.lock(); callbacks.append(done); lock.unlock() }
    func finishStart() { lock.lock(); let callback = callbacks[0]; lock.unlock(); callback(true) }
}
