import Foundation

/// Keeps periodic desktop snapshots from accumulating behind slow image conversion.
/// A running snapshot finishes; only the latest waiting snapshot is retained.
final class ThumbnailSnapshotScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private var pending: (@Sendable () -> Void)?
    private var running = false

    init(queue: DispatchQueue = DispatchQueue(
        label: "com.aethernative.aetherscreens.thumbnail-snapshots", qos: .utility
    )) {
        self.queue = queue
    }

    func schedule(_ snapshot: @escaping @Sendable () -> Void) {
        lock.lock()
        pending = snapshot
        let start = !running
        running = true
        lock.unlock()
        if start {
            queue.async { [self] in drain() }
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let snapshot = pending else {
                running = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            snapshot()
        }
    }
}

/// Session-local cadence; call from the main actor that consumes frame updates.
struct ThumbnailSnapshotCadence {
    private var lastCapture: TimeInterval?
    private let interval: TimeInterval = 5

    mutating func shouldCapture(at now: TimeInterval) -> Bool {
        guard now.isFinite, now >= 0 else { return false }
        if let lastCapture, now - lastCapture < interval { return false }
        lastCapture = now
        return true
    }
}
