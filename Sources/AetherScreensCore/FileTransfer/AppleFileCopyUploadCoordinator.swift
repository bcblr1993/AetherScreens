import Foundation

/// Owns one explicitly prepared upload in a desktop session. It does not choose
/// remote paths, infer name encodings, or promise deletion of remote partial files.
@MainActor
final class AppleFileCopyUploadCoordinator {
    enum Failure: Error { case invalidPreparedUpload }
    struct Backend {
        let transport: () -> AppleFileCopySendWorker.Transport?
        let install: (AppleFileCopySendWorker) -> Bool
        let remove: (AppleFileCopySendWorker) -> Void
    }
    private struct Active {
        let identity: UUID
        let attempt: FileTransferTaskStore.Attempt
        let worker: AppleFileCopySendWorker
        let startup: AppleFileCopyStartupTransport
        let transport: AppleFileCopySendWorker.Transport
        let sessionID: UInt32
        let onReleased: () -> Void
    }
    private let store: FileTransferTaskStore
    private let backend: Backend
    private var active: Active?
    var isBusy: Bool { active != nil }

    init(store: FileTransferTaskStore, backend: Backend) {
        self.store = store
        self.backend = backend
    }

    convenience init(store: FileTransferTaskStore, client: RFBClient) {
        self.init(store: store, backend: .init(transport: { [weak client] in
            guard let client, let generation = client.fileCopyTransportGeneration else { return nil }
            return { [weak client] message, done in
                client?.sendAppleFileCopy(message, expectedGeneration: generation, processed: done) ?? false
            }
        }, install: { [weak client] in client?.installAppleFileCopySender($0) ?? false },
           remove: { [weak client] in client?.removeAppleFileCopySender($0) }))
    }

    @discardableResult
    func start(job: FileTransferJob, sources: [AppleFileCopySendSession.Source],
               start: AppleFileCopyMessage, totals: AppleFileCopyMessage,
               destinationEncoding: String.Encoding? = nil,
               writeTimeout: TimeInterval = 30, resultTimeout: TimeInterval = 60,
               onReleased: @escaping () -> Void = {}) throws -> Bool {
        guard active == nil, job.direction == .upload, let transport = backend.transport() else { return false }
        var byteCount: UInt64 = 0
        for source in sources {
            for length in [source.item.dataForkByteCount, source.item.resourceForkByteCount] {
                let next = byteCount.addingReportingOverflow(length)
                guard !next.overflow else { throw Failure.invalidPreparedUpload }
                byteCount = next.partialValue
            }
        }
        guard byteCount == job.totalBytes,
              let info = try AppleFileCopyItemInfo.decode(totals, expectedSessionID: start.sessionID),
              info.logicalBytes == byteCount else { throw Failure.invalidPreparedUpload }
        let identity = UUID()
        let startup = try AppleFileCopyStartupTransport(start: start, totals: totals, transport: transport)
        let worker = try AppleFileCopySendWorker(sessionID: start.sessionID, sources: sources,
            maximumBytes: job.totalBytes, writeTimeout: writeTimeout, resultTimeout: resultTimeout,
            transport: { message, done in startup.send(message, processed: done) },
            onCompleted: { [weak self] name in
                Task { @MainActor [weak self] in
                    self?.completed(identity, name: name, encoding: destinationEncoding)
                }
            }, onFailure: { [weak self] in
                Task { @MainActor [weak self] in self?.failed(identity) }
            })
        guard backend.install(worker) else { startup.cancel(); worker.cancel(); return false }
        guard let attempt = store.register(job, cancel: { [weak self] in self?.cancel(identity) }) else {
            startup.cancel(); backend.remove(worker); worker.cancel(); return false
        }
        active = .init(identity: identity, attempt: attempt, worker: worker,
                       startup: startup, transport: transport, sessionID: start.sessionID, onReleased: onReleased)
        guard worker.start() else { failed(identity); return false }
        return true
    }

    private func completed(_ identity: UUID, name: Data?, encoding: String.Encoding?) {
        guard let current = active, current.identity == identity else { return }
        // Only the worker's validated terminal server result reaches this path.
        if !store.complete(current.attempt, destinationNameBytes: name, destinationEncoding: encoding) {
            failed(identity)
            return
        }
        release(current)
    }

    private func failed(_ identity: UUID) {
        guard let current = active, current.identity == identity else { return }
        // Store invalidates the result token before its cancellation callback.
        _ = store.fail(current.attempt, message: NSLocalizedString("File transfer failed", comment: ""))
        if active?.identity == identity { cancel(identity) }
    }

    private func cancel(_ identity: UUID) {
        guard let current = active, current.identity == identity else { return }
        release(current)
        // Stop is bound to the original connection; it cannot adopt a reconnect.
        // Native stop can leave partial files, so no remote cleanup is claimed.
        _ = current.transport(AppleFileCopyControl.stop.message(sessionID: current.sessionID), { _ in })
    }

    private func release(_ current: Active) {
        guard active?.identity == current.identity else { return }
        active = nil
        current.startup.cancel()
        current.worker.cancel()
        backend.remove(current.worker)
        current.onReleased()
    }
}
