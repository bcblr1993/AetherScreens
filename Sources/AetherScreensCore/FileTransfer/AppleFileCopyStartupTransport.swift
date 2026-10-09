import Foundation

/// Prefixes the paced sender's first packet with its explicitly prepared start
/// and totals. The worker's write deadline bounds this whole asynchronous chain.
/// The underlying transport must bind all calls to the same connection generation.
final class AppleFileCopyStartupTransport: @unchecked Sendable {
    typealias Transport = AppleFileCopySendWorker.Transport
    enum Failure: Error { case invalidPrefix }
    private let prefix: [AppleFileCopyMessage]
    private let transport: Transport
    private let lock = NSLock()
    private var started = false
    private var closed = false
    private var active: UUID?

    init(start: AppleFileCopyMessage, totals: AppleFileCopyMessage, transport: @escaping Transport) throws {
        guard start.version == 1, start.command == 2, totals.version == 1,
              totals.command == 100, totals.sessionID == start.sessionID else { throw Failure.invalidPrefix }
        prefix = [start, totals]
        self.transport = transport
    }

    func send(_ message: AppleFileCopyMessage, processed: @escaping @Sendable (Bool) -> Void) -> Bool {
        lock.lock()
        guard !closed, active == nil, message.sessionID == prefix[0].sessionID else { lock.unlock(); return false }
        let token = UUID()
        active = token
        let packets = (started ? [] : prefix) + [message]
        started = true
        lock.unlock()
        let accepted = dispatch(packets[...], token: token, processed: processed)
        if !accepted {
            lock.lock()
            if active == token { closed = true; active = nil }
            lock.unlock()
        }
        return accepted
    }

    func cancel() { lock.lock(); closed = true; active = nil; lock.unlock() }

    private func dispatch(_ packets: ArraySlice<AppleFileCopyMessage>, token: UUID,
                          processed: @escaping @Sendable (Bool) -> Void) -> Bool {
        lock.lock(); let current = !closed && active == token; lock.unlock()
        guard current, let message = packets.first else { return false }
        let once = StartupWriteOnce()
        let accepted = transport(message) { [weak self] success in
            guard once.take(), let self else { return }
            self.lock.lock(); let current = !self.closed && self.active == token; self.lock.unlock()
            guard current else { return }
            if !success { self.finish(token: token, success: false, processed: processed); return }
            let remainder = packets.dropFirst()
            if remainder.isEmpty { self.finish(token: token, success: true, processed: processed) }
            else if !self.dispatch(remainder, token: token, processed: processed) {
                self.finish(token: token, success: false, processed: processed)
            }
        }
        if !accepted {
            _ = once.take()
        }
        return accepted
    }

    private func finish(token: UUID, success: Bool, processed: @Sendable (Bool) -> Void) {
        lock.lock()
        guard !closed, active == token else { lock.unlock(); return }
        active = nil
        if !success { closed = true }
        lock.unlock()
        processed(success)
    }
}

private final class StartupWriteOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool { lock.lock(); defer { lock.unlock() }; guard !used else { return false }; used = true; return true }
}
