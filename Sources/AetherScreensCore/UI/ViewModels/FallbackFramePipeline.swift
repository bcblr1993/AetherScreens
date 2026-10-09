import Foundation
import CoreGraphics

/// Serial image creation with a single replaceable pending frame and publication.
final class FallbackFramePipeline: @unchecked Sendable {
    private struct Request {
        let framebuffer: Framebuffer
        let generation: UUID
        let publish: @Sendable (CGImage, UUID) -> Void
    }
    private struct Result {
        let image: CGImage
        let request: Request
    }
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "aetherscreens.fallback-frame", qos: .userInitiated)
    private let makeImage: @Sendable (Framebuffer) -> CGImage?
    private var generation: UUID?
    private var pending: Request?
    private var running = false
    private var result: Result?
    private var publicationScheduled = false

    init(makeImage: @escaping @Sendable (Framebuffer) -> CGImage? = { $0.makeCGImage() }) {
        self.makeImage = makeImage
    }

    func begin(generation: UUID) {
        lock.lock(); defer { lock.unlock() }
        self.generation = generation
        pending = nil
        result = nil
    }

    func submit(framebuffer: Framebuffer, generation: UUID,
                publish: @escaping @Sendable (CGImage, UUID) -> Void) {
        lock.lock()
        if let current = self.generation, current != generation { lock.unlock(); return }
        self.generation = generation
        pending = Request(framebuffer: framebuffer, generation: generation, publish: publish)
        let start = !running
        running = true
        lock.unlock()
        if start { worker.async { [weak self] in self?.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let request = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            guard let image = makeImage(request.framebuffer) else { continue }
            lock.lock()
            guard generation == request.generation else { lock.unlock(); continue }
            result = Result(image: image, request: request)
            let schedule = !publicationScheduled
            publicationScheduled = true
            lock.unlock()
            if schedule {
                DispatchQueue.main.async { [weak self] in self?.publishLatest() }
            }
        }
    }

    private func publishLatest() {
        lock.lock()
        let latest = result
        result = nil
        publicationScheduled = false
        let valid = latest?.request.generation == generation
        lock.unlock()
        if let latest, valid { latest.request.publish(latest.image, latest.request.generation) }
    }
}
