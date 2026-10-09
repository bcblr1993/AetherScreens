import Foundation

/// Bounds waiting for container callbacks, which expose no cancellation handle.
/// A late SDK callback cannot replace timeout/cancellation or resume twice.
enum CloudKitAccountRequestRunner {
    enum Failure: Error, Equatable { case timedOut }

    static func run<Value: Sendable>(timeout: Duration = .seconds(20),
        start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        try Task.checkCancellation()
        guard timeout > .zero else { throw Failure.timedOut }
        let relay = Relay<Value>()
        let deadline = Task {
            do { try await Task.sleep(for: timeout) }
            catch { return }
            relay.finish(.failure(Failure.timedOut))
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                relay.install(continuation)
                guard !Task.isCancelled, relay.isPending else {
                    relay.finish(.failure(CancellationError()))
                    return
                }
                start { relay.finish($0) }
            }
        } onCancel: {
            relay.finish(.failure(CancellationError()))
        }
    }

    private final class Relay<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Error>?
        private var result: Result<Value, Error>?
        var isPending: Bool {
            lock.lock(); defer { lock.unlock() }
            return result == nil
        }
        func install(_ continuation: CheckedContinuation<Value, Error>) {
            lock.lock()
            let terminal = result
            if terminal == nil { self.continuation = continuation }
            lock.unlock()
            if let terminal { continuation.resume(with: terminal) }
        }
        func finish(_ terminal: Result<Value, Error>) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = terminal
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: terminal)
        }
    }
}
