import Foundation

/// Accumulators are synchronized; all observable updates happen on the main thread
/// after releasing the lock. SwiftUI may reenter drawing from a publisher callback.
public final class PerformanceMetrics: ObservableObject, @unchecked Sendable {
    public static let shared = PerformanceMetrics()
    @Published public private(set) var currentFPS: Double = 0
    @Published public private(set) var latencyMs: Double = 0
    @Published public private(set) var hasLatencyMeasurements = false
    @Published public private(set) var bandwidthKbps: Double = 0
    @Published public private(set) var isOptimal = true

    private var frameCount = 0
    private var lastFPSUpdateTime: TimeInterval
    private var bytesAccumulator = 0
    private var lastBandwidthUpdateTime: TimeInterval
    private var smoothedLatency: Double = 0
    private var hasLatencySample = false
    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    private var generation = UUID()
    private var presentations = 0
    private var frameRevision: UInt64 = 0
    private var bandwidthRevision: UInt64 = 0
    private var latencyRevision: UInt64 = 0
    // Main-thread publications are drained serially, including synchronous
    // subscriber callbacks. @Published sends before its setter stores the value.
    private var publishing = false
    private var pendingPublications: [@Sendable () -> Void] = []

    public convenience init() { self.init(clock: { ProcessInfo.processInfo.systemUptime }) }
    init(clock: @escaping @Sendable () -> TimeInterval) {
        self.clock = clock
        lastFPSUpdateTime = clock()
        lastBandwidthUpdateTime = lastFPSUpdateTime
    }

    var measurementGeneration: UUID { lock.lock(); defer { lock.unlock() }; return generation }
    var acceptedPresentationCount: Int { lock.lock(); defer { lock.unlock() }; return presentations }
    public var hasPresentationMeasurements: Bool {
        lock.lock(); defer { lock.unlock() }
        return presentations > 0
    }

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
        frameRevision &+= 1
        bandwidthRevision &+= 1
        latencyRevision &+= 1
        bytesAccumulator = 0
        smoothedLatency = 0
        hasLatencySample = false
        lastFPSUpdateTime = clock()
        lastBandwidthUpdateTime = lastFPSUpdateTime
        let resetGeneration = generation
        lock.unlock()
        publish(generation: resetGeneration) {
            self.currentFPS = 0
            self.latencyMs = 0
            self.hasLatencyMeasurements = false
            self.bandwidthKbps = 0
            self.isOptimal = true
        }
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
            frameRevision &+= 1
        } else { fps = nil }
        let revision = frameRevision
        lock.unlock()
        guard let fps else { return }
        publish(generation: currentGeneration) {
            guard self.ratesMatch(frame: revision) else { return }
            if self.currentFPS != fps { self.currentFPS = fps }
        }
    }

    public func recordLatency(ms: Double) {
        guard ms.isFinite, ms >= 0 else { return }
        lock.lock()
        smoothedLatency = hasLatencySample ? smoothedLatency * 0.7 + ms * 0.3 : ms
        hasLatencySample = true
        let latency = smoothedLatency
        let currentGeneration = generation
        latencyRevision &+= 1
        let revision = latencyRevision
        lock.unlock()
        publish(generation: currentGeneration) {
            guard self.ratesMatch(latency: revision) else { return }
            if self.latencyMs != latency { self.latencyMs = latency }
            // A subscriber may synchronously record a newer sample.
            guard self.ratesMatch(latency: revision) else { return }
            let optimal = latency < 60
            if self.isOptimal != optimal { self.isOptimal = optimal }
            guard self.ratesMatch(latency: revision) else { return }
            if !self.hasLatencyMeasurements { self.hasLatencyMeasurements = true }
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
            bandwidthRevision &+= 1
        } else { bandwidth = nil }
        let revision = bandwidthRevision
        lock.unlock()
        guard let bandwidth else { return }
        publish(generation: currentGeneration) {
            guard self.ratesMatch(bandwidth: revision) else { return }
            if self.bandwidthKbps != bandwidth { self.bandwidthKbps = bandwidth }
        }
    }

    /// Flush completed measurement windows even when no new frame or byte arrives.
    /// An unchanged desktop can legitimately have zero presentations/throughput.
    public func sampleRates() {
        lock.lock()
        let now = clock()
        let currentGeneration = generation
        let frameElapsed = now - lastFPSUpdateTime
        let byteElapsed = now - lastBandwidthUpdateTime
        var fps: Double?
        var bandwidth: Double?
        if frameElapsed >= 1 {
            fps = (Double(frameCount) / frameElapsed * 10).rounded() / 10
            frameCount = 0
            lastFPSUpdateTime = now
            frameRevision &+= 1
        }
        if byteElapsed >= 1 {
            bandwidth = (Double(bytesAccumulator) * 8 / 1024 / byteElapsed * 10).rounded() / 10
            bytesAccumulator = 0
            lastBandwidthUpdateTime = now
            bandwidthRevision &+= 1
        }
        let sampledFrameRevision = frameRevision
        let sampledBandwidthRevision = bandwidthRevision
        lock.unlock()
        guard fps != nil || bandwidth != nil else { return }
        let sampledFPS = fps
        let sampledBandwidth = bandwidth
        publish(generation: currentGeneration) {
            if let sampledFPS, self.ratesMatch(frame: sampledFrameRevision), self.currentFPS != sampledFPS { self.currentFPS = sampledFPS }
            if let sampledBandwidth, self.ratesMatch(bandwidth: sampledBandwidthRevision), self.bandwidthKbps != sampledBandwidth { self.bandwidthKbps = sampledBandwidth }
        }
    }

    private func ratesMatch(frame: UInt64? = nil, bandwidth: UInt64? = nil, latency: UInt64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (frame == nil || frame == frameRevision)
            && (bandwidth == nil || bandwidth == bandwidthRevision)
            && (latency == nil || latency == latencyRevision)
    }

    private func publish(generation expected: UUID, _ update: @escaping @Sendable () -> Void) {
        let guarded: @Sendable () -> Void = { [weak self] in
            guard let self, self.measurementGeneration == expected else { return }
            update()
        }
        let enqueue: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.pendingPublications.append(guarded)
            guard !self.publishing else { return }
            self.publishing = true
            while !self.pendingPublications.isEmpty {
                let next = self.pendingPublications.removeFirst()
                next()
            }
            self.publishing = false
        }
        if Thread.isMainThread { enqueue() }
        else { DispatchQueue.main.async(execute: enqueue) }
    }
}
