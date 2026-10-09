import XCTest
@testable import AetherScreensCore

final class FileTransferTaskStoreTests: XCTestCase {
    @MainActor
    func testSavedFileOnlyAppearsAfterDownloadCompletionAndIsDismissed() throws {
        let store = FileTransferTaskStore()
        let job = FileTransferJob(filename: "requested")
        let token = try XCTUnwrap(store.register(job) {})
        let root = URL(fileURLWithPath: "/tmp/owned-save")
        let saved = FileTransferTaskStore.SavedFile(url: root.appendingPathComponent("actual"), accessRoot: root)
        XCTAssertNil(store.savedFile(for: job.id))
        XCTAssertTrue(store.complete(token, destinationNameBytes: Data("actual".utf8),
            confirmedDownloadBytes: 3, savedFile: saved))
        XCTAssertEqual(store.savedFile(for: job.id), saved)
        store.dismiss(job.id)
        XCTAssertNil(store.savedFile(for: job.id))
        XCTAssertFalse(store.complete(token, confirmedDownloadBytes: 3, savedFile: saved))
    }

    @MainActor
    func testCancelledDownloadCannotAcquireLateSavedFile() throws {
        let store = FileTransferTaskStore()
        let job = FileTransferJob(filename: "requested")
        let token = try XCTUnwrap(store.register(job) {})
        XCTAssertTrue(store.cancel(job.id))
        let root = URL(fileURLWithPath: "/tmp/owned-save")
        XCTAssertFalse(store.complete(token, destinationNameBytes: Data("late".utf8),
            confirmedDownloadBytes: 3,
            savedFile: .init(url: root.appendingPathComponent("late"), accessRoot: root)))
        XCTAssertNil(store.savedFile(for: job.id))
        XCTAssertEqual(store.jobs.first?.state, .cancelled)
    }

    @MainActor
    func testCancellationInvalidatesReentrantAndLateCompletion() throws {
        let store = FileTransferTaskStore()
        let job = FileTransferJob(direction: .upload, filename: "A", totalBytes: 512)
        var attempt: FileTransferTaskStore.Attempt?
        var cancellations = 0
        attempt = store.register(job) {
            cancellations += 1
            XCTAssertFalse(store.complete(attempt!))
        }
        let token = try XCTUnwrap(attempt)
        XCTAssertTrue(store.cancel(job.id))
        XCTAssertFalse(store.cancel(job.id))
        store.cancelAll()
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(store.complete(token))
        XCTAssertEqual(store.jobs.first?.state, .cancelled)
    }

    @MainActor
    func testCompletionStoresRealNameAndNeverCancelsCompletedWorker() throws {
        let store = FileTransferTaskStore()
        let job = FileTransferJob(direction: .upload, filename: "A", totalBytes: 512)
        let token = try XCTUnwrap(store.register(job) { XCTFail("Completed worker cancelled") })
        XCTAssertFalse(store.complete(token, destinationNameBytes: Data([0])))
        XCTAssertEqual(store.jobs.first?.transferredBytes, 0)
        XCTAssertTrue(store.complete(token, destinationNameBytes: Data("A 2".utf8), destinationEncoding: .utf8))
        store.cancelAll()
        XCTAssertEqual(store.displayFilename(for: try XCTUnwrap(store.jobs.first)), "A 2")
        XCTAssertFalse(store.complete(token))
        store.dismiss(job.id)
        XCTAssertTrue(store.jobs.isEmpty)
    }

    @MainActor
    func testAcknowledgedProgressDoesNotRepublishDuplicatesOrRegress() throws {
        let store = FileTransferTaskStore()
        let token = try XCTUnwrap(store.register(.init(direction: .download, filename: "A", totalBytes: 100), cancel: {}))
        var publications = 0
        let subscription = store.$jobs.dropFirst().sink { _ in publications += 1 }
        XCTAssertTrue(store.recordProgress(40, for: token))
        for _ in 0..<100 { XCTAssertTrue(store.recordProgress(40, for: token)) }
        XCTAssertFalse(store.recordProgress(39, for: token))
        XCTAssertFalse(store.recordProgress(101, for: token))
        XCTAssertEqual(publications, 1)
        store.cancelAll()
        XCTAssertFalse(store.recordProgress(100, for: token))
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testFailureIsIsolatedAndRejectsReentrantSuccess() throws {
        let store = FileTransferTaskStore()
        let failed = FileTransferJob(direction: .upload, filename: "A", totalBytes: 1)
        let other = FileTransferJob(direction: .download, filename: "B", totalBytes: 0)
        var failedAttempt: FileTransferTaskStore.Attempt?
        var released = 0
        failedAttempt = store.register(failed) {
            released += 1
            XCTAssertFalse(store.complete(failedAttempt!))
            XCTAssertFalse(store.fail(failedAttempt!, message: "late error"))
        }
        let token = try XCTUnwrap(failedAttempt)
        let otherToken = try XCTUnwrap(store.register(other) { XCTFail("Other worker released") })
        XCTAssertTrue(store.fail(token, message: "Transfer failed"))
        XCTAssertEqual(released, 1)
        XCTAssertEqual(store.jobs.first?.state, .failed("Transfer failed"))
        XCTAssertFalse(store.fail(token, message: "Replacement error"))
        XCTAssertFalse(store.cancel(failed.id))
        XCTAssertTrue(store.complete(otherToken))
        store.dismiss(failed.id)
        XCTAssertEqual(store.jobs.map(\.id), [other.id])
    }

    @MainActor
    func testSessionTeardownCancelsOwnedTaskBeforeLateCompletion() throws {
        let session = SessionViewModel(device: RemoteDevice(name: "File QA", host: "qa.invalid"),
                                       password: nil, isTemporary: true)
        var cancelled = 0
        let job = FileTransferJob(direction: .upload, filename: "A", totalBytes: 1)
        let token = try XCTUnwrap(session.fileTransfers.register(job) { cancelled += 1 })
        session.endSession()
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(session.fileTransfers.complete(token))
        XCTAssertEqual(session.fileTransfers.jobs.first?.state, .cancelled)
        session.endSession()
        XCTAssertEqual(cancelled, 1)
    }

    @MainActor
    func testObserveOnlyAndForegroundSwitchCancelPreparationAndOwnedTransfers() async throws {
        for observeOnly in [true, false] {
            let session = SessionViewModel(device: RemoteDevice(name: "File QA", host: "qa.invalid"),
                                           password: nil, isTemporary: true)
            var cancelled = 0
            let job = FileTransferJob(direction: .upload, filename: "A", totalBytes: 1)
            let attempt = try XCTUnwrap(session.fileTransfers.register(job) { cancelled += 1 })
            let identity = session.fileUploadPreparationID
            let preparation = Task { try? await Task.sleep(nanoseconds: 60_000_000_000) }
            session.fileUploadPreparationTask = Task { await preparation.value }
            let ownedPreparation = try XCTUnwrap(session.fileUploadPreparationTask)
            session.isPreparingFileUpload = true
            if observeOnly { session.isObserveOnly = true }
            else { session.setForegroundSession(false) }
            XCTAssertTrue(ownedPreparation.isCancelled)
            XCTAssertNil(session.fileUploadPreparationTask)
            XCTAssertFalse(session.isPreparingFileUpload)
            XCTAssertNotEqual(session.fileUploadPreparationID, identity)
            XCTAssertEqual(cancelled, 1)
            XCTAssertFalse(session.fileTransfers.complete(attempt))
            XCTAssertEqual(session.fileTransfers.jobs.first?.state, .cancelled)
            session.endSession()
            XCTAssertEqual(cancelled, 1)
            preparation.cancel()
            await preparation.value
            await ownedPreparation.value
        }
    }

    @MainActor
    func testUnknownDownloadUsesPersistedSizeAndRejectsImpossibleOrLateCompletion() throws {
        let store = FileTransferTaskStore()
        let job = FileTransferJob(filename: "remote.bin")
        let attempt = try XCTUnwrap(store.register(job, cancel: {}))
        XCTAssertFalse(store.jobs[0].isSizeKnown)
        XCTAssertTrue(store.recordProgress(2, for: attempt))
        XCTAssertEqual(store.jobs[0].fractionCompleted, 0)
        XCTAssertFalse(store.complete(attempt))
        XCTAssertFalse(store.complete(attempt, confirmedDownloadBytes: 1))
        XCTAssertFalse(store.jobs[0].isSizeKnown)
        XCTAssertEqual(store.jobs[0].transferredBytes, 2)
        XCTAssertTrue(store.complete(attempt, confirmedDownloadBytes: 3))
        XCTAssertTrue(store.jobs[0].isSizeKnown)
        XCTAssertEqual(store.jobs[0].totalBytes, 3)
        XCTAssertEqual(store.jobs[0].transferredBytes, 3)
        XCTAssertEqual(store.jobs[0].state, .completed)
        XCTAssertFalse(store.complete(attempt, confirmedDownloadBytes: 4))
        XCTAssertEqual(store.jobs[0].totalBytes, 3)
    }

    @MainActor
    func testKnownDownloadSizeCannotChangeAndEmptyDownloadRequiresConfirmation() throws {
        let store = FileTransferTaskStore()
        let known = FileTransferJob(direction: .download, filename: "known", totalBytes: 5)
        let attempt = try XCTUnwrap(store.register(known, cancel: {}))
        XCTAssertFalse(store.complete(attempt, confirmedDownloadBytes: 6))
        XCTAssertEqual(store.jobs[0].totalBytes, 5)
        XCTAssertTrue(store.complete(attempt, confirmedDownloadBytes: 5))
        let empty = FileTransferJob(filename: "empty")
        let emptyAttempt = try XCTUnwrap(store.register(empty, cancel: {}))
        XCTAssertFalse(store.complete(emptyAttempt))
        XCTAssertTrue(store.complete(emptyAttempt, confirmedDownloadBytes: 0))
        XCTAssertEqual(store.jobs[1].fractionCompleted, 1)
    }

    @MainActor
    func testFinishedHistoryMakesRoomWithoutDeletingSavedFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("saved")
        try Data([7]).write(to: file)
        let store = FileTransferTaskStore()
        let oldest = FileTransferJob(filename: "saved")
        let first = try XCTUnwrap(store.register(oldest) { XCTFail("Completed task cancelled") })
        XCTAssertTrue(store.complete(first, confirmedDownloadBytes: 1, savedFile: .init(url: file, accessRoot: root)))
        for _ in 0..<31 {
            let token = try XCTUnwrap(store.register(.init(direction: .upload, filename: "done", totalBytes: 0)) {
                XCTFail("Completed task cancelled")
            })
            XCTAssertTrue(store.complete(token))
        }
        XCTAssertNil(store.register(oldest, cancel: {}))
        XCTAssertNotNil(store.savedFile(for: oldest.id))
        let next = FileTransferJob(direction: .upload, filename: "next", totalBytes: 1)
        XCTAssertNotNil(store.register(next, cancel: {}))
        XCTAssertEqual(store.jobs.count, 32)
        XCTAssertFalse(store.jobs.contains { $0.id == oldest.id })
        XCTAssertNil(store.savedFile(for: oldest.id))
        XCTAssertFalse(store.complete(first, confirmedDownloadBytes: 1))
        XCTAssertEqual(try Data(contentsOf: file), Data([7]))
        store.cancelAll()
    }

    @MainActor
    func testAdmissionIsBoundedAndDismissCannotDiscardActiveWorker() throws {
        let store = FileTransferTaskStore()
        for _ in 0..<32 {
            let job = FileTransferJob(direction: .download, filename: "A", totalBytes: 0)
            XCTAssertNotNil(store.register(job, cancel: {}))
            XCTAssertNil(store.register(job, cancel: { XCTFail("Duplicate admitted") }))
            store.dismiss(job.id)
        }
        XCTAssertEqual(store.jobs.count, 32)
        XCTAssertNil(store.register(.init(direction: .download, filename: "B", totalBytes: 0), cancel: {}))
        store.cancelAll()
        let id = try XCTUnwrap(store.jobs.first?.id)
        store.dismiss(id)
        XCTAssertNotNil(store.register(.init(direction: .download, filename: "B", totalBytes: 0), cancel: {}))
    }
}
