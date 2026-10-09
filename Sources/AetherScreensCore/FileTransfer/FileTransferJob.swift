import Foundation

/// Transport-independent bookkeeping for native remote-desktop file transfers.
/// The job is not a transfer implementation; its token rejects obsolete callbacks.
struct FileTransferJob: Equatable, Sendable, Identifiable {
    enum Direction: Equatable, Sendable { case upload, download }
    enum State: Equatable, Sendable {
        case queued, awaitingOverwriteDecision, transferring, paused
        case completed, cancelled, failed(String)
    }
    let id: UUID
    let direction: Direction
    let filename: String
    private(set) var totalBytes: UInt64
    private(set) var isSizeKnown = true
    /// Actual result name from the successful transport, preserved as bytes
    /// until its negotiated encoding is known. Never use it as a filesystem path.
    private(set) var destinationNameBytes: Data?
    private(set) var transferredBytes: UInt64 = 0
    private(set) var state: State = .queued
    private(set) var attempt: UUID = UUID()

    init(id: UUID = UUID(), direction: Direction, filename: String, totalBytes: UInt64) {
        self.id = id
        self.direction = direction
        self.filename = filename
        self.totalBytes = totalBytes
    }

    /// A requested download has no truthful total until its received catalog
    /// and complete persisted data establish one. Never use a budget as a size.
    init(downloadID: UUID = UUID(), filename: String) {
        self.init(id: downloadID, direction: .download, filename: filename, totalBytes: 0)
        isSizeKnown = false
    }

    @discardableResult
    mutating func confirmDownloadSize(_ bytes: UInt64, attempt token: UUID) -> Bool {
        guard direction == .download, token == attempt, state == .transferring,
              bytes >= transferredBytes else { return false }
        if isSizeKnown { return bytes == totalBytes }
        totalBytes = bytes
        isSizeKnown = true
        return true
    }

    /// Display only: callers must supply the established result-name encoding.
    /// Unknown/invalid/empty results fall back to the requested name; bytes are
    /// never replacement-decoded or interpreted as a local/remote path.
    func displayFilename(destinationEncoding: String.Encoding? = nil) -> String {
        guard let destinationEncoding, let destinationNameBytes,
              let actual = String(data: destinationNameBytes, encoding: destinationEncoding),
              !actual.isEmpty else { return filename }
        return actual
    }

    var fractionCompleted: Double {
        guard isSizeKnown else { return 0 }
        guard totalBytes > 0 else { return state == .completed ? 1 : 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    /// Remote conflict detection happens before opening an overwrite operation.
    mutating func awaitOverwriteDecision() -> Bool {
        guard state == .queued else { return false }
        state = .awaitingOverwriteDecision
        return true
    }

    mutating func start(overwriteApproved: Bool = false) -> UUID? {
        guard state == .queued || (state == .awaitingOverwriteDecision && overwriteApproved) else { return nil }
        attempt = UUID()
        state = .transferring
        return attempt
    }

    /// Progress must describe acknowledged bytes, not queued network writes.
    @discardableResult
    mutating func recordProgress(_ bytes: UInt64, attempt token: UUID) -> Bool {
        guard token == attempt, state == .transferring,
              bytes >= transferredBytes, (!isSizeKnown || bytes <= totalBytes) else { return false }
        transferredBytes = bytes
        return true
    }

    /// Byte progress alone cannot complete a job: destination finalization must succeed.
    @discardableResult
    mutating func finish(attempt token: UUID, transferSucceeded: Bool, destinationFinalized: Bool,
                         destinationNameBytes: Data? = nil) -> Bool {
        guard token == attempt, state == .transferring, isSizeKnown, transferredBytes == totalBytes,
              transferSucceeded, destinationFinalized,
              destinationNameBytes.map({ $0.count <= 1023 && !$0.contains(0) }) ?? true else { return false }
        self.destinationNameBytes = destinationNameBytes
        state = .completed
        attempt = UUID()
        return true
    }

    @discardableResult
    mutating func pause(attempt token: UUID) -> Bool {
        guard token == attempt, state == .transferring else { return false }
        state = .paused
        attempt = UUID()
        return true
    }

    /// Resume only from an offset explicitly confirmed by the replacement transport.
    mutating func resume(confirmedOffset: UInt64) -> UUID? {
        guard state == .paused, confirmedOffset <= transferredBytes else { return nil }
        transferredBytes = confirmedOffset
        attempt = UUID()
        state = .transferring
        return attempt
    }

    @discardableResult
    mutating func cancel() -> Bool {
        switch state {
        case .completed, .cancelled, .failed: return false
        default:
            state = .cancelled
            attempt = UUID()
            return true
        }
    }

    @discardableResult
    mutating func fail(_ message: String, attempt token: UUID) -> Bool {
        guard token == attempt, state == .transferring else { return false }
        state = .failed(message)
        attempt = UUID()
        return true
    }
}
