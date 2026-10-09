import Foundation

/// Bridges the connection's receive hook to bounded, ordered file work.
/// A negotiated owner installs this worker; unsolicited messages do not do so.
final class AppleFileCopyReceiveWorker: @unchecked Sendable {
    private let queue: DispatchQueue
    private let session: AppleFileCopyReceiveSession
    let sessionID: UInt32
    private let maximumPendingBytes: Int
    private let maximumPendingMessages: Int
    private let lock = NSLock()
    private var pendingBytes = 0
    private var pendingMessages = 0
    private var closed = false
    private var cancelled = false
    private var admissionOverflow = false
    var requiresTransportFailure: Bool {
        lock.lock(); defer { lock.unlock() }
        return admissionOverflow
    }
    private let inactivityTimeout: TimeInterval
    // Accessed only on the serial file queue.
    private var deadlineTimer: DispatchSourceTimer?
    private var deadline: DispatchTime?
    private let onEvent: @Sendable (AppleFileCopyReceiveSession.Event) -> Void
    private let onAcknowledgedBytes: @Sendable (UInt64) -> Void
    private let onFailure: @Sendable () -> Void
    // Runs on the file worker. The owner must finalize/retain/cancel these files
    // there rather than accessing them concurrently from the UI actor.
    private let onPrepared: @Sendable ([AppleFileCopyStagingFile]) -> Void

    init(sessionID: UInt32, parentDirectory: URL, maximumBytes: UInt64, maximumItems: Int,
         maximumPendingBytes: Int = 4 * 1_048_576,
         maximumPendingMessages: Int = 256,
         inactivityTimeout: TimeInterval = 60,
         queue: DispatchQueue = DispatchQueue(label: "com.aethernative.aetherscreens.file-receive", qos: .utility),
         onEvent: @escaping @Sendable (AppleFileCopyReceiveSession.Event) -> Void,
         onAcknowledgedBytes: @escaping @Sendable (UInt64) -> Void = { _ in },
         onFailure: @escaping @Sendable () -> Void,
         onPrepared: @escaping @Sendable ([AppleFileCopyStagingFile]) -> Void) throws {
        guard maximumPendingBytes >= 14, maximumPendingMessages > 0,
              inactivityTimeout.isFinite, inactivityTimeout > 0, inactivityTimeout <= 3600 else {
            throw AppleFileCopyReceiveSession.Failure.exceedsBudget
        }
        self.sessionID = sessionID
        self.maximumPendingBytes = maximumPendingBytes
        self.maximumPendingMessages = maximumPendingMessages
        self.queue = queue
        self.inactivityTimeout = inactivityTimeout
        self.onEvent = onEvent
        self.onAcknowledgedBytes = onAcknowledgedBytes
        self.onFailure = onFailure
        self.onPrepared = onPrepared
        session = try AppleFileCopyReceiveSession(sessionID: sessionID, parentDirectory: parentDirectory,
                                                  maximumBytes: maximumBytes, maximumItems: maximumItems)
        queue.async { [weak self] in self?.refreshDeadline() }
    }

    /// Quick admission only. True does not mean written, acknowledged or complete.
    @discardableResult
    func enqueue(_ message: AppleFileCopyMessage) -> Bool {
        guard message.sessionID == sessionID else { return false }
        lock.lock()
        guard !closed else { lock.unlock(); return false }
        // Wire byte limits alone allow hundreds of thousands of tiny queued closures.
        guard pendingMessages < maximumPendingMessages,
              message.body.count <= maximumPendingBytes - 14,
              pendingBytes <= maximumPendingBytes - 14 - message.body.count else {
            closed = true
            admissionOverflow = true
            lock.unlock()
            queue.async { [self] in
                stopDeadline()
                session.cancel()
                lock.lock(); let notify = !cancelled; lock.unlock()
                if notify { onFailure() }
            }
            return false
        }
        let cost = message.body.count + 14
        pendingBytes += cost
        pendingMessages += 1
        lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock()
                pendingBytes -= cost
                pendingMessages -= 1
                lock.unlock()
            }
            lock.lock()
            let active = !closed
            lock.unlock()
            guard active else { return }
            var finalizing = false
            do {
                let event = try session.receive(message)
                lock.lock()
                let stillActive = !closed
                if event == .senderFinished { closed = true }
                lock.unlock()
                guard stillActive else { session.cancel(); return }
                switch event {
                case .senderFinished: stopDeadline()
                case .itemStarted, .itemPrepared: refreshDeadline()
                case .bytesWritten(let count):
                    if count > 0 { refreshDeadline() }
                case .ignored: break
                }
                onAcknowledgedBytes(session.acknowledgedBytes)
                onEvent(event)
                if event == .senderFinished {
                    lock.lock(); let mayFinalize = !cancelled; lock.unlock()
                    guard mayFinalize else { session.cancel(); return }
                    finalizing = true
                    onPrepared(try session.takePreparedTrees())
                }
            } catch {
                lock.lock()
                let notify = !cancelled && (!closed || finalizing)
                closed = true
                lock.unlock()
                stopDeadline()
                session.cancel()
                if notify { onFailure() }
            }
        }
        return true
    }

    func cancel(onStopped: @escaping @Sendable () -> Void = {}) {
        lock.lock()
        closed = true
        cancelled = true
        lock.unlock()
        queue.async { [self] in stopDeadline(); session.cancel(); onStopped() }
    }

    private func refreshDeadline() {
        lock.lock(); let active = !closed; lock.unlock()
        guard active else { return }
        if deadlineTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in
                guard let self, let deadline = self.deadline,
                      DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds else { return }
                self.lock.lock()
                let notify = !self.closed
                self.closed = true
                self.lock.unlock()
                self.stopDeadline()
                self.session.cancel()
                if notify { self.onFailure() }
            }
            deadlineTimer = timer
            timer.resume()
        }
        let next = DispatchTime.now() + inactivityTimeout
        deadline = next
        deadlineTimer?.schedule(deadline: next, leeway: .milliseconds(5))
    }

    private func stopDeadline() {
        deadline = nil
        deadlineTimer?.cancel()
        deadlineTimer = nil
    }

    deinit { deadlineTimer?.cancel() }
}
