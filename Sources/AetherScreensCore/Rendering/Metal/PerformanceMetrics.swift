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
    private var lastFPSUpdateTime = CFAbsoluteTimeGetCurrent()
    private var bytesAccumulator = 0
    private var lastBandwidthUpdateTime = CFAbsoluteTimeGetCurrent()
    private var smoothedLatency: Double = 0
    private let lock = NSLock()
    public init() {}

    public func recordFrame() {
        lock.lock()
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastFPSUpdateTime
        let fps: Double?
        if elapsed >= 1 {
            fps = (Double(frameCount) / elapsed * 10).rounded() / 10
            frameCount = 0
            lastFPSUpdateTime = now
        } else { fps = nil }
        lock.unlock()
        guard let fps else { return }
        publish { self.currentFPS = fps }
    }

    public func recordLatency(ms: Double) {
        guard ms.isFinite, ms >= 0 else { return }
        lock.lock()
        smoothedLatency = smoothedLatency == 0 ? ms : smoothedLatency * 0.7 + ms * 0.3
        let latency = smoothedLatency
        lock.unlock()
        publish {
            self.latencyMs = latency
            self.isOptimal = latency < 60
        }
    }

    public func recordBytesReceived(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        bytesAccumulator += count
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBandwidthUpdateTime
        let bandwidth: Double?
        if elapsed >= 1 {
            bandwidth = (Double(bytesAccumulator) * 8 / 1024 / elapsed * 10).rounded() / 10
            bytesAccumulator = 0
            lastBandwidthUpdateTime = now
        } else { bandwidth = nil }
        lock.unlock()
        guard let bandwidth else { return }
        publish { self.bandwidthKbps = bandwidth }
    }

    private func publish(_ update: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { update() }
        else { DispatchQueue.main.async(execute: update) }
    }
}
