import Foundation

/// Session owner for a single requested remote file or directory tree. The
/// selected existing destination is never overwritten. Staging/commit stays on
/// the file worker, and UI completion follows actual filesystem finalization.
@MainActor
final class AppleFileCopyDownloadCoordinator {
    struct Backend {
        let transport: () -> AppleFileCopySendWorker.Transport?
        let install: (AppleFileCopyReceiveWorker) -> Bool
        let remove: (AppleFileCopyReceiveWorker) -> Void
    }
    private struct Active {
        let identity: UUID
        let attempt: FileTransferTaskStore.Attempt
        let worker: AppleFileCopyReceiveWorker
        let finalizer: DownloadFinalizer
        let transport: AppleFileCopySendWorker.Transport
        let sessionID: UInt32
        let onReleased: () -> Void
        let onStopped: @MainActor @Sendable () -> Void
        var requestWritten = false
    }
    private let store: FileTransferTaskStore
    private let backend: Backend
    private var active: Active?
    private var writeDeadline: Task<Void, Never>?
    private var pendingResult: DownloadFinalizer.Result?
    var isBusy: Bool { active != nil }

    init(store: FileTransferTaskStore, backend: Backend) { self.store = store; self.backend = backend }
    convenience init(store: FileTransferTaskStore, client: RFBClient) {
        self.init(store: store, backend: .init(transport: { [weak client] in
            guard let client, let generation = client.fileCopyTransportGeneration else { return nil }
            return { [weak client] message, done in
                client?.sendAppleFileCopy(message, expectedGeneration: generation, processed: done) ?? false
            }
        }, install: { [weak client] in client?.installAppleFileCopyReceiver($0) ?? false },
           remove: { [weak client] in client?.removeAppleFileCopyReceiver($0) }))
    }

    @discardableResult
    func start(filename: String, request: AppleFileCopyMessage, destination: URL,
               maximumBytes: UInt64 = 1_073_741_824, maximumItems: Int = 1024,
               writeTimeout: TimeInterval = 30, inactivityTimeout: TimeInterval = 60,
               onReleased: @escaping () -> Void = {},
               onStopped: @escaping @MainActor @Sendable () -> Void = {}) throws -> Bool {
        guard active == nil, let transport = backend.transport() else { return false }
        guard request.version == 1, request.command == 1,
              let start = try AppleFileCopyStart.decode(request, expectedSessionID: request.sessionID),
              start.flags & 1 != 0, writeTimeout.isFinite, writeTimeout > 0, writeTimeout <= 3600 else { return false }
        let identity = UUID()
        let finalizer = DownloadFinalizer(destination: destination)
        let worker = try AppleFileCopyReceiveWorker(sessionID: request.sessionID, parentDirectory: FileManager.default.temporaryDirectory,
            maximumBytes: maximumBytes, maximumItems: maximumItems, inactivityTimeout: inactivityTimeout,
            onEvent: { _ in }, onAcknowledgedBytes: { [weak self] bytes in
                if finalizer.record(bytes) {
                    Task { @MainActor [weak self] in self?.progress(identity, bytes: bytes) }
                }
            }, onFailure: { [weak self] in
                Task { @MainActor [weak self] in self?.failed(identity) }
            }, onPrepared: { [weak self] files in
                do {
                    guard let result = try finalizer.commit(files) else { return }
                    Task { @MainActor [weak self] in self?.completed(identity, result: result) }
                } catch AppleFileCopyDiskSpace.Failure.insufficientSpace {
                    Task { @MainActor [weak self] in
                        self?.failed(identity, message: AppLocalization.string("Not enough space in the save folder. Free space or choose another folder."))
                    }
                } catch {
                    Task { @MainActor [weak self] in self?.failed(identity) }
                }
            })
        guard backend.install(worker) else { finalizer.cancel(); worker.cancel(); return false }
        let job = FileTransferJob(filename: filename)
        guard let attempt = store.register(job, cancel: { [weak self] in self?.cancel(identity) }) else {
            finalizer.cancel(); backend.remove(worker); worker.cancel(); return false
        }
        active = .init(identity: identity, attempt: attempt, worker: worker, finalizer: finalizer,
                       transport: transport, sessionID: request.sessionID, onReleased: onReleased, onStopped: onStopped)
        let once = DownloadWriteOnce()
        writeDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(writeTimeout * 1_000_000_000)) }
            catch { return }
            self?.failed(identity)
        }
        let admitted = transport(request) { [weak self] success in
            guard once.take() else { return }
            Task { @MainActor [weak self] in
                guard let self, self.active?.identity == identity else { return }
                self.writeDeadline?.cancel(); self.writeDeadline = nil
                if !success { self.failed(identity); return }
                self.active?.requestWritten = true
                if let result = self.pendingResult { self.pendingResult = nil; self.completed(identity, result: result) }
            }
        }
        if !admitted { _ = once.take(); failed(identity) }
        return admitted
    }

    private func progress(_ identity: UUID, bytes: UInt64) {
        guard let current = active, current.identity == identity else { return }
        _ = store.recordProgress(bytes, for: current.attempt)
    }

    private func completed(_ identity: UUID, result: DownloadFinalizer.Result) {
        guard let current = active, current.identity == identity else { return }
        guard current.requestWritten else { pendingResult = result; return }
        guard store.complete(current.attempt, destinationNameBytes: Data(result.name.utf8),
            destinationEncoding: .utf8, confirmedDownloadBytes: result.bytes, savedFile: result.savedFile) else { failed(identity); return }
        release(current)
    }
    private func failed(_ identity: UUID, message: String? = nil) {
        guard let current = active, current.identity == identity else { return }
        _ = store.fail(current.attempt, message: message ?? AppLocalization.string("Download failed. Check the destination folder for saved files."))
        if active?.identity == identity { cancel(identity) }
    }
    private func cancel(_ identity: UUID) {
        guard let current = active, current.identity == identity else { return }
        release(current)
        _ = current.transport(AppleFileCopyControl.stop.message(sessionID: current.sessionID), { _ in })
    }
    private func release(_ current: Active) {
        guard active?.identity == current.identity else { return }
        active = nil
        pendingResult = nil
        writeDeadline?.cancel(); writeDeadline = nil
        current.finalizer.cancel()
        let onStopped = current.onStopped
        current.worker.cancel { Task { @MainActor in onStopped() } }
        backend.remove(current.worker)
        current.onReleased()
    }
}

private final class DownloadFinalizer: @unchecked Sendable {
    struct Result: Sendable { let bytes: UInt64; let name: String; let savedFile: FileTransferTaskStore.SavedFile }
    private let destination: URL
    private let coordinator = NSFileCoordinator()
    private let lock = NSLock()
    private var cancelled = false
    private var bytes: UInt64 = 0
    private var progressCadence = FileTransferProgressCadence()
    init(destination: URL) { self.destination = destination }
    func record(_ count: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        bytes = count // Commit always sees the latest exact byte total.
        guard !cancelled, count > 0 else { return false }
        return progressCadence.shouldPublish(bytes: count, now: ProcessInfo.processInfo.systemUptime)
    }
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        coordinator.cancel()
    }
    func commit(_ files: [AppleFileCopyStagingFile]) throws -> Result? {
        defer { files.forEach { $0.cancel() } }
        lock.lock(); let allowed = !cancelled; let count = bytes; lock.unlock()
        guard allowed else { return nil }
        guard files.count == 1 else { throw AppleFileCopyReceiveSession.Failure.incompleteItem }
        // Never hold the UI cancellation lock across filesystem work. A commit
        // already in progress can finish after cancel; the UI warns to check the
        // destination and late results cannot mark a cancelled task complete.
        var coordinationError: NSError?
        var outcome: Swift.Result<Result?, Error>?
        coordinator.coordinate(writingItemAt: destination, options: .forMerging, error: &coordinationError) { writable in
            outcome = Swift.Result {
                // A cancellation while waiting for the provider must not start
                // a new filesystem commit once access is granted.
                lock.lock(); let stillAllowed = !cancelled; lock.unlock()
                guard stillAllowed else { return nil }
                let export = try files[0].copyPreparedTree(to: writable, isCancelled: { [self] in
                    lock.lock(); defer { lock.unlock() }; return cancelled
                })
                defer { export.cancel() }
                lock.lock(); let mayCommit = !cancelled; lock.unlock()
                guard mayCommit else { return nil }
                try export.restoreCatalogMetadata()
                try export.restorePermissions()
                let saved = try export.commitPreparedFile(to: writable)
                return .init(bytes: count, name: saved.lastPathComponent, savedFile: .init(url: saved, accessRoot: destination))
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else {
            lock.lock(); let stopped = cancelled; lock.unlock()
            if stopped { return nil }
            throw AppleFileCopyStagingFile.Failure.invalidDestination
        }
        return try outcome.get()
    }
}
private final class DownloadWriteOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; guard !used else { return false }; used = true; return true }
}
