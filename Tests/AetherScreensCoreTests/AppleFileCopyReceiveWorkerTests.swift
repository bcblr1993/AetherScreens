import XCTest
@testable import AetherScreensCore

final class AppleFileCopyReceiveWorkerTests: XCTestCase {
    func testCancellationCleanupCallbackWaitsForWorkerQueueToStop() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-stop-access-qa")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        queue.async { gate.wait() }
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, queue: queue,
            onEvent: { _ in XCTFail("Cancelled queue must not receive") },
            onFailure: { XCTFail("Explicit cancellation is quiet") }, onPrepared: { _ in XCTFail("Not complete") })
        let stopped = expectation(description: "Owned queue cleanup finished")
        XCTAssertTrue(worker.enqueue(emptyItem))
        let cleanupFinished = DispatchSemaphore(value: 0)
        worker.cancel { cleanupFinished.signal(); stopped.fulfill() }
        XCTAssertFalse(worker.enqueue(end))
        // Queue is still blocked; returning from cancel must not imply cleanup.
        XCTAssertEqual(cleanupFinished.wait(timeout: .now() + 0.02), .timedOut)
        gate.signal()
        wait(for: [stopped], timeout: 3)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testIgnoredControlTrafficDoesNotRenewReceiveDeadline() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-ignored-idle-qa")
        let failed = expectation(description: "No receive progress still expires")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.15, queue: queue,
            onEvent: { XCTAssertEqual($0, .ignored) }, onFailure: { failed.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("Control traffic is not completion") })
        let ignored = AppleFileCopyMessage(version: 1, command: 300, sessionID: 7, body: Data())
        queue.asyncAfter(deadline: .now() + 0.1) { XCTAssertTrue(worker.enqueue(ignored)) }
        wait(for: [failed], timeout: 0.22)
        XCTAssertFalse(worker.enqueue(ignored))
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testValidProgressRenewsIdleDeadlineUntilSenderFinishes() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-idle-progress-qa")
        let done = expectation(description: "Progress kept transfer alive")
        let failed = expectation(description: "Active transfer must not expire")
        failed.isInverted = true
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.3, queue: queue,
            onEvent: { _ in }, onFailure: { failed.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; done.fulfill() })
        let item = emptyItem
        let finish = end
        queue.asyncAfter(deadline: .now() + 0.2) { XCTAssertTrue(worker.enqueue(item)) }
        // Past the original deadline, but inside the renewed deadline.
        queue.asyncAfter(deadline: .now() + 0.4) { XCTAssertTrue(worker.enqueue(finish)) }
        wait(for: [done], timeout: 3)
        wait(for: [failed], timeout: 0.35)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testInactivityBeforeFirstMessageAndAfterItemCleansStaging() throws {
        for receiveItem in [false, true] {
            let root = try root()
            defer { try? FileManager.default.removeItem(at: root) }
            let failed = expectation(description: "Idle receiver fails once")
            failed.assertForOverFulfill = true
            let queue = DispatchQueue(label: "file-worker-inactivity-qa")
            let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
                maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.05, queue: queue,
                onEvent: { _ in }, onFailure: { failed.fulfill() },
                onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("Idle transfer cannot complete") })
            if receiveItem { XCTAssertTrue(worker.enqueue(emptyItem)) }
            wait(for: [failed], timeout: 3)
            queue.sync {}
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
            XCTAssertFalse(worker.enqueue(end))
            XCTAssertFalse(worker.requiresTransportFailure)
            worker.cancel()
            queue.sync {}
        }
    }

    #if os(macOS)
    func testTreeAssemblyConflictReportsFailureAndCleansOwnedTree() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-tree-conflict-qa")
        let failed = expectation(description: "Assembly conflict reported")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 3, queue: queue, onEvent: { _ in },
            onFailure: { failed.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("Conflicting tree must not hand off") })
        var folder = emptyItem.body
        folder[0] = 2
        folder[91] = 0x10
        var child = emptyItem.body
        child[93] = 1
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 101, sessionID: 7, body: folder)))
        for _ in 0..<2 {
            XCTAssertTrue(worker.enqueue(.init(version: 1, command: 101, sessionID: 7, body: child)))
        }
        XCTAssertTrue(worker.enqueue(end))
        wait(for: [failed], timeout: 3)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertFalse(worker.enqueue(emptyItem))
    }
    #endif

    private final class WorkerReference: @unchecked Sendable {
        weak var worker: AppleFileCopyReceiveWorker?
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("receive-worker-qa-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
    private var emptyItem: AppleFileCopyMessage {
        var body = Data(repeating: 0, count: 104)
        body[0] = 1
        body[101] = 1
        body.append(contentsOf: [65, 0])
        return .init(version: 1, command: 101, sessionID: 7, body: body)
    }
    private var end: AppleFileCopyMessage {
        .init(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))
    }

    func testWorkerProcessesInOrderAndTransfersOwnedPreparedFile() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let done = expectation(description: "Worker prepared file")
        let failed = expectation(description: "Valid worker must not fail")
        failed.isInverted = true
        let queue = DispatchQueue(label: "file-worker-order-qa")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.05, queue: queue,
            onEvent: { _ in }, onFailure: { failed.fulfill() }, onPrepared: { files in
                XCTAssertEqual(files.count, 1)
                XCTAssertEqual(try? Data(contentsOf: files[0].dataForkURL), Data())
                files.forEach { $0.cancel() }
                done.fulfill()
            })
        XCTAssertTrue(worker.enqueue(emptyItem))
        XCTAssertTrue(worker.enqueue(end))
        wait(for: [done], timeout: 3)
        XCTAssertFalse(worker.enqueue(emptyItem))
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        wait(for: [failed], timeout: 0.1)
    }

    func testCancelDiscardsQueuedMessagesBeforeDiskWork() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let unwanted = expectation(description: "Cancelled worker must not publish")
        unwanted.isInverted = true
        let queue = DispatchQueue(label: "file-worker-cancel-qa")
        queue.suspend()
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.05, queue: queue,
            onEvent: { _ in unwanted.fulfill() }, onFailure: { unwanted.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; unwanted.fulfill() })
        XCTAssertTrue(worker.enqueue(emptyItem))
        worker.cancel()
        XCTAssertFalse(worker.enqueue(end))
        queue.resume()
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        wait(for: [unwanted], timeout: 0.1)
    }

    func testReentrantCancellationAtSenderEndPreventsOwnershipHandoff() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let ended = expectation(description: "Sender ended")
        let unwanted = expectation(description: "Cancelled end must not hand off files")
        unwanted.isInverted = true
        let queue = DispatchQueue(label: "file-worker-reentrant-cancel-qa")
        queue.suspend()
        let reference = WorkerReference()
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, queue: queue,
            onEvent: { event in
                if event == .senderFinished { reference.worker?.cancel(); ended.fulfill() }
            }, onFailure: { unwanted.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; unwanted.fulfill() })
        reference.worker = worker // Established before any queue work begins.
        XCTAssertTrue(worker.enqueue(emptyItem))
        XCTAssertTrue(worker.enqueue(end))
        queue.resume()
        wait(for: [ended], timeout: 3)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        wait(for: [unwanted], timeout: 0.1)
    }

    func testPendingBudgetClosesAdmissionAndPreservesUnrelatedFile() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([99]).write(to: root.appendingPathComponent("unrelated"))
        let failed = expectation(description: "Pending budget rejected")
        let queue = DispatchQueue(label: "file-worker-budget-qa")
        queue.suspend()
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 2, maximumPendingBytes: 200, queue: queue,
            onEvent: { _ in XCTFail("Closed backlog must not process") }, onFailure: { failed.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("No successful output") })
        XCTAssertTrue(worker.enqueue(emptyItem))
        XCTAssertFalse(worker.enqueue(emptyItem))
        XCTAssertFalse(worker.enqueue(end))
        XCTAssertTrue(worker.requiresTransportFailure)
        queue.resume()
        wait(for: [failed], timeout: 3)
        queue.sync {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["unrelated"])
    }

    func testMessageCountBudgetRejectsTinyBacklogBelowByteBudget() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-count-budget-qa")
        queue.suspend()
        let failed = expectation(description: "Message count budget rejected")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, maximumPendingMessages: 2, queue: queue,
            onEvent: { _ in XCTFail("Rejected backlog must not publish") },
            onFailure: { failed.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("No output") })
        XCTAssertTrue(worker.enqueue(emptyItem))
        XCTAssertTrue(worker.enqueue(end))
        XCTAssertFalse(worker.enqueue(end))
        XCTAssertFalse(worker.enqueue(emptyItem))
        queue.resume()
        wait(for: [failed], timeout: 3)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testMessageCountSlotIsReleasedAfterProcessing() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = DispatchQueue(label: "file-worker-count-reuse-qa")
        let prepared = expectation(description: "Completed with a single queue slot")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, maximumPendingMessages: 1, queue: queue,
            onEvent: { _ in }, onFailure: { XCTFail("Processed messages must release admission slots") },
            onPrepared: { files in
                XCTAssertEqual(files.count, 1)
                files.forEach { $0.cancel() }
                prepared.fulfill()
            })
        XCTAssertTrue(worker.enqueue(emptyItem))
        queue.sync {}
        XCTAssertTrue(worker.enqueue(end))
        wait(for: [prepared], timeout: 3)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
