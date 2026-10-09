import Foundation

/// Single-worker receive coordination after explicit native session negotiation.
/// Sender completion leaves prepared staging owned here; it is not a final
/// destination commit, catalog-metadata validation or receiver acknowledgement.
final class AppleFileCopyReceiveSession {
    enum State: Equatable { case receiving, senderFinished, handedOff, cancelled, failed }
    enum Event: Equatable {
        case ignored, itemStarted, bytesWritten(UInt64), itemPrepared, senderFinished
    }
    enum Failure: Error { case unavailable, incompleteItem, exceedsBudget, missingResult, senderFailed(Data), unsupportedCommand, unsupportedItem }

    private(set) var state: State = .receiving
    private(set) var preparedFiles: [AppleFileCopyStagingFile] = []
    private(set) var acknowledgedBytes: UInt64 = 0
    private(set) var manifest: AppleFileCopyManifest
    private let sessionID: UInt32
    private let parentDirectory: URL
    private let maximumBytes: UInt64
    private let maximumItems: Int
    private let inflater = AppleFileCopyInflater()
    private var declaredBytes: UInt64 = 0
    private var active: AppleFileCopyStagingFile?

    init(sessionID: UInt32, parentDirectory: URL, maximumBytes: UInt64, maximumItems: Int) throws {
        guard parentDirectory.isFileURL, maximumItems > 0 else { throw Failure.exceedsBudget }
        self.sessionID = sessionID
        self.parentDirectory = parentDirectory
        self.maximumBytes = maximumBytes
        self.maximumItems = maximumItems
        manifest = try AppleFileCopyManifest(maximumItems: maximumItems)
    }

    func receive(_ message: AppleFileCopyMessage) throws -> Event {
        guard state == .receiving else { throw Failure.unavailable }
        guard message.sessionID == sessionID else { return .ignored }
        do {
            guard message.version == 1 else { throw Failure.unsupportedCommand }
            switch message.command {
            case 101:
                guard active == nil else { throw Failure.incompleteItem }
                guard preparedFiles.count < maximumItems else { throw Failure.exceedsBudget }
                guard let item = try AppleFileCopyItem.decode(message, expectedSessionID: sessionID) else { throw Failure.unsupportedCommand }
                guard (item.kind == .file && !item.isDirectory)
                    || (item.kind == .directory && item.isDirectory) else {
                    throw Failure.unsupportedItem
                }
                let itemBytes = item.dataForkByteCount.addingReportingOverflow(item.resourceForkByteCount)
                let total = declaredBytes.addingReportingOverflow(itemBytes.partialValue)
                guard !itemBytes.overflow, !total.overflow, total.partialValue <= maximumBytes else { throw Failure.exceedsBudget }
                try manifest.append(item)
                let staging = try AppleFileCopyStagingFile(item: item, sessionID: sessionID,
                    parentDirectory: parentDirectory, maximumFileBytes: maximumBytes)
                active = staging
                declaredBytes = total.partialValue
                if staging.progress.isComplete { return try prepareActive() }
                return .itemStarted
            case 102, 103:
                guard let active else { throw Failure.incompleteItem }
                let before = active.progress
                guard try active.append(message, inflater: inflater) else { throw Failure.unsupportedCommand }
                // Separate subtractions avoid combining potentially overflowing fork sizes.
                let count = before.dataRemaining - active.progress.dataRemaining
                    + before.resourceRemaining - active.progress.resourceRemaining
                acknowledgedBytes += count // Declared aggregate was already bounded above.
                if active.progress.isComplete { return try prepareActive() }
                return .bytesWritten(count)
            case 104:
                guard active == nil else { throw Failure.incompleteItem }
                switch try AppleFileCopyEndSession.decode(message, expectedSessionID: sessionID) {
                case .success:
                    state = .senderFinished
                    return .senderFinished
                case .failure(let raw): throw Failure.senderFailed(raw)
                default: throw Failure.missingResult
                }
            default:
                return .ignored // Totals/control grammar remains handled by the negotiated owner.
            }
        } catch {
            discardStaging()
            state = .failed
            throw error
        }
    }

    private func prepareActive() throws -> Event {
        guard let active else { throw Failure.incompleteItem }
        try active.finish()
        preparedFiles.append(active)
        self.active = nil
        return .itemPrepared
    }

    /// Ownership transfers only after explicit sender success. The next owner
    /// must validate catalog metadata and destination policy before commit.
    func takePreparedFiles() throws -> [AppleFileCopyStagingFile] {
        guard state == .senderFinished else { throw Failure.unavailable }
        let files = preparedFiles
        preparedFiles.removeAll()
        state = .handedOff
        return files
    }

    /// Assemble only within owned staging. Public destination commit and final
    /// directory catalog metadata remain the next owner's responsibility.
    func takePreparedTrees() throws -> [AppleFileCopyStagingFile] {
        guard state == .senderFinished else { throw Failure.unavailable }
        do {
            guard preparedFiles.count == manifest.entries.count else { throw Failure.incompleteItem }
            // Children precede their parents' move, so every parent URL still
            // points at its private payload while receiving nested entries.
            for index in preparedFiles.indices.reversed() {
                if let parent = manifest.entries[index].parentIndex {
                    guard parent < index, preparedFiles[parent].item.isDirectory else { throw Failure.incompleteItem }
                    try preparedFiles[index].commitPreparedChild(to: preparedFiles[parent])
                }
            }
            let roots = preparedFiles.indices.filter { manifest.entries[$0].parentIndex == nil }
                .map { preparedFiles[$0] }
            preparedFiles.removeAll()
            state = .handedOff
            return roots
        } catch {
            discardStaging()
            state = .failed
            throw error
        }
    }

    func cancel() {
        guard state == .receiving || state == .senderFinished || state == .handedOff else { return }
        discardStaging()
        state = .cancelled
    }

    private func discardStaging() {
        active?.cancel()
        active = nil
        preparedFiles.forEach { $0.cancel() }
        preparedFiles.removeAll()
        manifest.reset()
    }

    deinit { discardStaging() }
}
