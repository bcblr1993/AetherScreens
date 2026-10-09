import Foundation

/// A negotiated owner starts this worker after start/totals negotiation.
/// Only one file packet is in flight; local writes never imply remote saving.
final class AppleFileCopySendWorker: @unchecked Sendable {
    typealias Transport = @Sendable (AppleFileCopyMessage, @escaping @Sendable (Bool) -> Void) -> Bool
    private let queue: DispatchQueue
    private let session: AppleFileCopySendSession
    private let transport: Transport
    private let onCompleted: @Sendable (Data?) -> Void
    private let onFailure: @Sendable () -> Void
    private let lock = NSLock()
    private var closed = false
    private var cancelled = false
    private var started = false
    private var pendingStatus = 0
    private var inFlight: UInt64?
    private var nextToken: UInt64 = 0
    private let writeTimeout: TimeInterval
    private let resultTimeout: TimeInterval
    private var deadlineTimer: DispatchSourceTimer?
    private var deadline: DispatchTime?
    let sessionID: UInt32

    init(sessionID: UInt32, sources: [AppleFileCopySendSession.Source], maximumBytes: UInt64,
         maximumItems: Int = 1024, blockSize: Int = 65_536,
         writeTimeout: TimeInterval = 30, resultTimeout: TimeInterval = 60,
         queue: DispatchQueue = DispatchQueue(label: "com.aethernative.aetherscreens.file-send", qos: .utility),
         transport: @escaping Transport,
         onCompleted: @escaping @Sendable (Data?) -> Void,
         onFailure: @escaping @Sendable () -> Void) throws {
        guard writeTimeout.isFinite, resultTimeout.isFinite,
              (0...3600).contains(writeTimeout), writeTimeout > 0,
              (0...3600).contains(resultTimeout), resultTimeout > 0 else {
            throw AppleFileCopySendSession.Failure.invalidSource
        }
        self.sessionID = sessionID
        self.queue = queue
        self.transport = transport
        self.onCompleted = onCompleted
        self.onFailure = onFailure
        self.writeTimeout = writeTimeout
        self.resultTimeout = resultTimeout
        session = try .init(sessionID: sessionID, sources: sources, maximumBytes: maximumBytes,
                            maximumItems: maximumItems, blockSize: blockSize)
    }

    @discardableResult
    func start() -> Bool {
        lock.lock()
        guard !closed, !started else { lock.unlock(); return false }
        started = true
        lock.unlock()
        queue.async { [self] in pump() }
        return true
    }

    /// Status admission is bounded independently of outgoing file size.
    @discardableResult
    func enqueue(_ message: AppleFileCopyMessage) -> Bool {
        guard message.sessionID == sessionID, message.command == 200 || message.command == 300 else { return false }
        lock.lock()
        guard !closed, started else { lock.unlock(); return false }
        guard pendingStatus < 32, message.body.count <= 65_536 else {
            closed = true
            lock.unlock()
            queue.async { [self] in
                stopDeadline()
                session.cancel()
                lock.lock(); let notify = !cancelled; lock.unlock()
                if notify { onFailure() }
            }
            return false
        }
        pendingStatus += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pendingStatus -= 1; lock.unlock() }
            guard isOpen else { return }
            do {
                _ = try session.receive(message)
                completeIfReady()
            } catch { fail() }
        }
        return true
    }

    private var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed
    }

    private func pump() {
        guard isOpen, inFlight == nil, session.state == .sending else { return }
        nextToken &+= 1
        let token = nextToken
        inFlight = token
        do {
            let accepted = try session.pump { [self] packet in
                guard isOpen else { return false }
                return transport(packet) { [weak self] success in
                    guard let self else { return }
                    // Even synchronous transport callbacks run after pump commits
                    // admission, and duplicate/late callbacks cannot advance it.
                    self.queue.async { [self] in processed(token: token, success: success) }
                }
            }
            if !accepted { inFlight = nil; fail() }
            else if isOpen { scheduleDeadline(after: writeTimeout) }
        } catch { inFlight = nil; fail() }
    }

    private func processed(token: UInt64, success: Bool) {
        guard isOpen, inFlight == token else { return }
        inFlight = nil
        deadline = nil
        deadlineTimer?.schedule(deadline: .distantFuture)
        guard success else { fail(); return }
        completeIfReady()
        if isOpen {
            if session.state == .awaitingResult { scheduleDeadline(after: resultTimeout) }
            else { pump() }
        }
    }

    private func scheduleDeadline(after interval: TimeInterval) {
        if deadlineTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in
                guard let self, self.isOpen, let deadline = self.deadline,
                      DispatchTime.now().uptimeNanoseconds >= deadline.uptimeNanoseconds else { return }
                self.fail()
            }
            deadlineTimer = timer
            timer.resume()
        }
        let next = DispatchTime.now() + interval
        deadline = next
        deadlineTimer?.schedule(deadline: next, leeway: .milliseconds(5))
    }

    private func stopDeadline() {
        deadline = nil
        deadlineTimer?.cancel()
        deadlineTimer = nil
    }

    private func completeIfReady() {
        guard session.state == .completed, inFlight == nil else { return }
        lock.lock()
        let notify = !closed
        closed = true
        lock.unlock()
        stopDeadline()
        if notify { onCompleted(session.destinationName) }
    }

    private func fail() {
        lock.lock()
        let notify = !closed
        closed = true
        lock.unlock()
        stopDeadline()
        session.cancel()
        if notify { onFailure() }
    }

    func cancel() {
        lock.lock(); closed = true; cancelled = true; lock.unlock()
        queue.async { [self] in stopDeadline(); session.cancel(); inFlight = nil }
    }

    deinit { deadlineTimer?.cancel() }
}
