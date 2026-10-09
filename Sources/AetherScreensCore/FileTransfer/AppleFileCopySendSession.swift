import Foundation

/// Single-worker sender after native session negotiation. Each pump admits at
/// most one packet; the owner supplies queue pacing and receives server status.
final class AppleFileCopySendSession {
    struct Source: Sendable {
        let item: AppleFileCopyItem
        let dataURL: URL?
        let resourceURL: URL?
    }
    enum State: Equatable { case sending, awaitingResult, completed, cancelled, failed }
    enum Failure: Error { case invalidSource, exceedsBudget, unavailable, prematureResult, serverFailed(Int16) }
    private(set) var state: State = .sending
    private(set) var queuedBytes: UInt64 = 0
    private(set) var serverProgress: Double = 0
    private(set) var destinationName: Data?
    let totalBytes: UInt64
    private let sources: [Source]
    private let sessionID: UInt32
    private let blockSize: Int
    private var index = 0
    private var itemStarted = false
    private var reader: AppleFileCopyForkReader?
    private var pending: AppleFileCopyMessage?
    private var pumping = false

    init(sessionID: UInt32, sources: [Source], maximumBytes: UInt64,
         maximumItems: Int = 1024, blockSize: Int = 65_536) throws {
        guard maximumItems > 0, !sources.isEmpty, sources.count <= maximumItems else { throw Failure.exceedsBudget }
        guard (1...1_048_564).contains(blockSize) else { throw Failure.invalidSource }
        var manifest = try AppleFileCopyManifest(maximumItems: maximumItems)
        var total: UInt64 = 0
        for source in sources {
            guard source.item.catalogHeader.count == 104 else { throw Failure.invalidSource }
            guard source.item.kind == (source.item.isDirectory ? .directory : .file) else { throw Failure.invalidSource }
            try manifest.append(source.item)
            _ = try source.item.message(sessionID: sessionID)
            if source.item.isDirectory {
                guard source.item.dataForkByteCount == 0, source.item.resourceForkByteCount == 0 else { throw Failure.invalidSource }
            } else {
                guard source.dataURL != nil,
                      source.item.resourceForkByteCount == 0 || source.resourceURL != nil else { throw Failure.invalidSource }
            }
            let forks = source.item.dataForkByteCount.addingReportingOverflow(source.item.resourceForkByteCount)
            let next = total.addingReportingOverflow(forks.partialValue)
            guard !forks.overflow, !next.overflow, next.partialValue <= maximumBytes else { throw Failure.exceedsBudget }
            total = next.partialValue
        }
        self.sessionID = sessionID
        self.sources = sources
        self.blockSize = blockSize
        totalBytes = total
    }

    /// False leaves the same packet pending. True means queue admission only;
    /// it must never be presented as remote saved-byte acknowledgement.
    @discardableResult
    func pump(send: (AppleFileCopyMessage) -> Bool) throws -> Bool {
        guard state == .sending, !pumping else { throw Failure.unavailable }
        pumping = true
        defer { pumping = false }
        do {
            if pending == nil { pending = try nextPacket() }
            guard let packet = pending else { throw Failure.unavailable }
            let accepted = send(packet)
            // A synchronous callback may cancel/fail this attempt.
            guard state == .sending else { return false }
            guard accepted else { return false }
            if packet.command == 102 { queuedBytes += UInt64(packet.body.count - 4) }
            pending = nil
            if packet.command == 104 { state = .awaitingResult }
            return true
        } catch {
            if state == .sending { fail() }
            throw error
        }
    }

    private func nextPacket() throws -> AppleFileCopyMessage {
        while index < sources.count {
            let source = sources[index]
            if !itemStarted {
                if !source.item.isDirectory {
                    guard let url = source.dataURL else { throw Failure.invalidSource }
                    reader = try AppleFileCopyForkReader(item: source.item, sessionID: sessionID,
                        dataURL: url, resourceURL: source.resourceURL, blockSize: blockSize)
                }
                itemStarted = true
                return try source.item.message(sessionID: sessionID)
            }
            if let packet = try reader?.nextMessage() { return packet }
            reader?.cancel()
            reader = nil
            index += 1
            itemStarted = false
        }
        return .init(version: 1, command: 104, sessionID: sessionID, body: Data([0, 0, 0, 0]))
    }

    @discardableResult
    func receive(_ message: AppleFileCopyMessage) throws -> Bool {
        guard state == .sending || state == .awaitingResult else { return false }
        do {
            guard let status = try AppleFileCopyServerStatus.decode(message, expectedSessionID: sessionID) else { return false }
            switch status {
            case .progress(let fraction): serverProgress = max(serverProgress, fraction)
            case .finished(let error, let name):
                guard error == 0 else { throw Failure.serverFailed(error) }
                guard state == .awaitingResult, queuedBytes == totalBytes else { throw Failure.prematureResult }
                destinationName = name
                serverProgress = 1
                state = .completed
            }
            return true
        } catch {
            fail()
            throw error
        }
    }

    private func fail() {
        reader?.cancel(); reader = nil; pending = nil
        state = .failed
    }

    func cancel() {
        guard state == .sending || state == .awaitingResult else { return }
        reader?.cancel(); reader = nil; pending = nil
        state = .cancelled
    }

    deinit { cancel() }
}
