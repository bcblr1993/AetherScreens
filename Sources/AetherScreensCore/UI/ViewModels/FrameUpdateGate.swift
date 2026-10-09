import Foundation

/// Bounds pending UI work while the framebuffer itself retains the latest pixels.
final class FrameUpdateGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingGeneration: UUID?
    private var acceptedGeneration: UUID?
    private var count = 0

    func enqueue(generation: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let acceptedGeneration, acceptedGeneration != generation { return false }
        acceptedGeneration = generation
        if pendingGeneration == generation {
            if count < Int.max { count += 1 }
            return false
        }
        pendingGeneration = generation
        count = 1
        return true
    }

    func begin(generation: UUID) {
        lock.lock(); defer { lock.unlock() }
        acceptedGeneration = generation
        pendingGeneration = nil
        count = 0
    }

    func consume(generation: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard pendingGeneration == generation else { return 0 }
        let consumed = count
        pendingGeneration = nil
        count = 0
        return consumed
    }
}
