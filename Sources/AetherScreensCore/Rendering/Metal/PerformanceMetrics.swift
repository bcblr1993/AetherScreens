import Foundation

/// Accumulators are synchronized; all observable updates happen on the main thread
/// after releasing the lock. SwiftUI may reenter drawing from a publisher callback.
public final class PerformanceMetrics: ObservableObject, @unchecked Sendable {
    public static let shared = PerformanceMetrics()
    @Published public private(set) var currentFPS: Double = 0
    @Published public private(set) var latencyMs: Double = 0
    @Published public private(set) var bandwidthKbps: Double = 0
    @Published public private(set) var isOptimal = true

    private var frameCount = 0
    private var lastFPSUpdateTime: TimeInterval
    private var bytesAccumulator = 0
    private var lastBandwidthUpdateTime: TimeInterval
    private var smoothedLatency: Double = 0
    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    private var generation = UUID()
    private var presentations = 0

    public convenience init() { self.init(clock: { ProcessInfo.processInfo.systemUptime }) }
    init(clock: @escaping @Sendable () -> TimeInterval) {
        self.clock = clock
        lastFPSUpdateTime = clock()
        lastBandwidthUpdateTime = lastFPSUpdateTime
    }

    var measurementGeneration: UUID { lock.lock(); defer { lock.unlock() }; return generation }
    var acceptedPresentationCount: Int { lock.lock(); defer { lock.unlock() }; return presentations }

    /// A zero presentation time identifies an undisplayed/dropped drawable.
    func recordPresentedFrame(at time: TimeInterval, generation expected: UUID) {
        guard time.isFinite, time > 0 else { return }
        recordFrame(generation: expected, presented: true)
    }

    @MainActor
    public func reset() {
        lock.lock()
        generation = UUID()
        frameCount = 0
        presentations = 0
        bytesAccumulator = 0
        smoothedLatency = 0
        lastFPSUpdateTime = clock()
        lastBandwidthUpdateTime = lastFPSUpdateTime
        lock.unlock()
        currentFPS = 0
        latencyMs = 0
        bandwidthKbps = 0
        isOptimal = true
    }

    public func recordFrame() { recordFrame(generation: nil, presented: false) }

    private func recordFrame(generation expected: UUID?, presented: Bool) {
        lock.lock()
        if let expected, expected != generation { lock.unlock(); return }
        let currentGeneration = generation
        if presented { presentations += 1 }
        frameCount += 1
        let now = clock()
        let elapsed = now - lastFPSUpdateTime
        let fps: Double?
        if elapsed >= 1 {
            fps = (Double(frameCount) / elapsed * 10).rounded() / 10
            frameCount = 0
            lastFPSUpdateTime = now
        } else { fps = nil }
        lock.unlock()
        guard let fps else { return }
        publish(generation: currentGeneration) { self.currentFPS = fps }
    }

    public func recordLatency(ms: Double) {
        guard ms.isFinite, ms >= 0 else { return }
        lock.lock()
        smoothedLatency = smoothedLatency == 0 ? ms : smoothedLatency * 0.7 + ms * 0.3
        let latency = smoothedLatency
        let currentGeneration = generation
        lock.unlock()
        publish(generation: currentGeneration) {
            self.latencyMs = latency
            self.isOptimal = latency < 60
        }
    }

    public func recordBytesReceived(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        bytesAccumulator += count
        let now = clock()
        let currentGeneration = generation
        let elapsed = now - lastBandwidthUpdateTime
        let bandwidth: Double?
        if elapsed >= 1 {
            bandwidth = (Double(bytesAccumulator) * 8 / 1024 / elapsed * 10).rounded() / 10
            bytesAccumulator = 0
            lastBandwidthUpdateTime = now
        } else { bandwidth = nil }
        lock.unlock()
        guard let bandwidth else { return }
        publish(generation: currentGeneration) { self.bandwidthKbps = bandwidth }
    }

    private func publish(generation expected: UUID, _ update: @escaping @Sendable () -> Void) {
        let guarded: @Sendable () -> Void = { [weak self] in
            guard let self, self.measurementGeneration == expected else { return }
            update()
        }
        if Thread.isMainThread { guarded() }
        else { DispatchQueue.main.async(execute: guarded) }
    }
}
