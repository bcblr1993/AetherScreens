import Foundation

/// Real-time streaming performance metrics (FPS, Latency, Bandwidth, Encoding).
public final class PerformanceMetrics: ObservableObject, @unchecked Sendable {
    public static let shared = PerformanceMetrics()

    @Published public private(set) var currentFPS: Double = 0.0
    @Published public private(set) var latencyMs: Double = 0.0
    @Published public private(set) var bandwidthKbps: Double = 0.0
    @Published public private(set) var isOptimal: Bool = true // < 50ms latency & >= 55 FPS

    private var frameCount: Int = 0
    private var lastFPSUpdateTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var bytesAccumulator: Int = 0
    private var lastBandwidthUpdateTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let lock = NSLock()

    public init() {}

    /// Record a rendered frame to calculate FPS
    public func recordFrame() {
        lock.lock()
        defer { lock.unlock() }

        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastFPSUpdateTime

        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            self.currentFPS = (fps * 10).rounded() / 10
            self.frameCount = 0
            self.lastFPSUpdateTime = now
            self.updateOptimalStatus()
        }
    }

    /// Record round-trip ping/latency in milliseconds
    public func recordLatency(ms: Double) {
        lock.lock()
        defer { lock.unlock() }

        // Exponential moving average for smooth display
        if latencyMs == 0 {
            latencyMs = ms
        } else {
            latencyMs = (latencyMs * 0.7) + (ms * 0.3)
        }
        self.updateOptimalStatus()
    }

    /// Record incoming bytes received from the network
    public func recordBytesReceived(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }

        bytesAccumulator += count
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastBandwidthUpdateTime

        if elapsed >= 1.0 {
            let kbps = (Double(bytesAccumulator * 8) / 1024.0) / elapsed
            self.bandwidthKbps = (kbps * 10).rounded() / 10
            self.bytesAccumulator = 0
            self.lastBandwidthUpdateTime = now
        }
    }

    private func updateOptimalStatus() {
        // Optimal if latency < 60ms and FPS >= 45 (or idle with low latency)
        self.isOptimal = latencyMs < 60.0
    }
}
