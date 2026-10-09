import Foundation
import Combine

/// Session-owned UI state. Transport owners retain their own workers and report
/// acknowledged results; this store neither negotiates nor starts file copying.
@MainActor
final class FileTransferTaskStore: ObservableObject {
    struct SavedFile: Equatable, Sendable { let url: URL; let accessRoot: URL }
    struct Attempt: Equatable, Sendable { let jobID: UUID; let token: UUID }
    @Published private(set) var jobs: [FileTransferJob] = []
    private var savedFiles: [UUID: SavedFile] = [:]
    private var resultEncodings: [UUID: String.Encoding] = [:]
    private var cancellations: [UUID: () -> Void] = [:]

    func register(_ job: FileTransferJob, cancel: @escaping () -> Void) -> Attempt? {
        guard !jobs.contains(where: { $0.id == job.id }) else { return nil }
        var started = job
        guard let token = started.start() else { return nil }
        if jobs.count >= 32 {
            guard let oldestFinished = jobs.first(where: {
                switch $0.state {
                case .completed, .cancelled, .failed: return true
                default: return false
                }
            }) else { return nil }
            dismiss(oldestFinished.id)
        }
        cancellations[job.id] = cancel
        jobs.append(started)
        return .init(jobID: job.id, token: token)
    }

    /// Only acknowledged/persisted progress, never bytes queued for sending.
    @discardableResult
    func recordProgress(_ bytes: UInt64, for attempt: Attempt) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == attempt.jobID }) else { return false }
        var updated = jobs[index]
        guard updated.recordProgress(bytes, attempt: attempt.token) else { return false }
        if updated != jobs[index] { jobs[index] = updated }
        return true
    }

    @discardableResult
    func complete(_ attempt: Attempt, destinationNameBytes: Data? = nil,
                  destinationEncoding: String.Encoding? = nil,
                  confirmedDownloadBytes: UInt64? = nil, savedFile: SavedFile? = nil) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == attempt.jobID }) else { return false }
        var updated = jobs[index]
        if let savedFile {
            guard updated.direction == .download, savedFile.url.isFileURL, savedFile.accessRoot.isFileURL else { return false }
        }
        if let confirmedDownloadBytes,
           !updated.confirmDownloadSize(confirmedDownloadBytes, attempt: attempt.token) { return false }
        guard updated.recordProgress(updated.totalBytes, attempt: attempt.token),
              updated.finish(attempt: attempt.token, transferSucceeded: true,
                             destinationFinalized: true, destinationNameBytes: destinationNameBytes) else { return false }
        cancellations.removeValue(forKey: attempt.jobID)
        resultEncodings[attempt.jobID] = destinationEncoding
        savedFiles[attempt.jobID] = savedFile
        jobs[index] = updated
        return true
    }

    @discardableResult
    func fail(_ attempt: Attempt, message: String) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == attempt.jobID }) else { return false }
        var updated = jobs[index]
        guard updated.fail(message, attempt: attempt.token) else { return false }
        let callback = cancellations.removeValue(forKey: attempt.jobID)
        jobs[index] = updated
        callback?() // Release this worker only, after invalidating its result token.
        return true
    }

    @discardableResult
    func cancel(_ jobID: UUID) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return false }
        var updated = jobs[index]
        guard updated.cancel() else { return false }
        let callback = cancellations.removeValue(forKey: jobID)
        jobs[index] = updated // Invalidate token before possibly reentrant callback.
        callback?()
        return true
    }

    func cancelAll() {
        let ids = jobs.map(\.id)
        for id in ids { _ = cancel(id) }
    }

    func displayFilename(for job: FileTransferJob) -> String {
        job.displayFilename(destinationEncoding: resultEncodings[job.id])
    }

    func savedFile(for jobID: UUID) -> SavedFile? {
        guard jobs.contains(where: { $0.id == jobID && $0.direction == .download && $0.state == .completed }) else { return nil }
        return savedFiles[jobID]
    }

    func dismiss(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        switch job.state {
        case .completed, .cancelled, .failed:
            resultEncodings.removeValue(forKey: jobID)
            savedFiles.removeValue(forKey: jobID)
            jobs.removeAll { $0.id == jobID }
        default: break
        }
    }
}
