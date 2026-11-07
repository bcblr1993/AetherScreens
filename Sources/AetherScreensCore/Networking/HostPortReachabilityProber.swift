import Foundation
import Network

/// Lightweight TCP reachability prober for saved computers (VNC, RDP, or SSH jump host).
public struct HostPortReachabilityProber: Sendable {
    public struct ProbeResult: Equatable, Sendable {
        public let isReachable: Bool
        public let latencyMs: Int?

        public init(isReachable: Bool, latencyMs: Int?) {
            self.isReachable = isReachable
            self.latencyMs = latencyMs
        }
    }

    private let probeClosure: @Sendable (String, UInt16) async -> ProbeResult

    public init(
        timeoutSeconds: TimeInterval = 1.5,
        probeClosure: (@Sendable (String, UInt16) async -> ProbeResult)? = nil
    ) {
        if let probeClosure {
            self.probeClosure = probeClosure
        } else {
            self.probeClosure = { host, port in
                await Self.tcpProbe(host: host, port: port, timeoutSeconds: timeoutSeconds)
            }
        }
    }

    /// Returns the actual network endpoint to probe for a device (the SSH jump host if an SSH tunnel is configured, otherwise the direct VNC/RDP endpoint).
    public static func probeEndpoint(for device: RemoteDevice) -> (host: String, port: UInt16) {
        if let ssh = device.ssh, !ssh.server.host.isEmpty {
            return (ssh.server.host, ssh.server.port)
        }
        return (device.host, device.port)
    }

    public func probe(device: RemoteDevice) async -> ProbeResult {
        let endpoint = Self.probeEndpoint(for: device)
        return await probeClosure(endpoint.host, endpoint.port)
    }

    public func probeAll(_ devices: [RemoteDevice]) async -> [UUID: ProbeResult] {
        await withTaskGroup(of: (UUID, ProbeResult).self) { group in
            for device in devices {
                group.addTask {
                    let res = await self.probe(device: device)
                    return (device.id, res)
                }
            }
            var results: [UUID: ProbeResult] = [:]
            for await (id, res) in group {
                results[id] = res
            }
            return results
        }
    }

    private static func tcpProbe(host: String, port: UInt16, timeoutSeconds: TimeInterval) async -> ProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return ProbeResult(isReachable: false, latencyMs: nil)
        }
        let start = ContinuousClock.now
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.aetherscreens.reachability.probe")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let stateBox = ProbeOnceBox(connection: connection, continuation: continuation, start: start)

            let timeoutItem = DispatchWorkItem {
                stateBox.finish(isReachable: false)
            }
            stateBox.setTimeout(timeoutItem)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    stateBox.finish(isReachable: true)
                case .failed, .cancelled:
                    stateBox.finish(isReachable: false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)
        }
    }
}

private final class ProbeOnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var timeoutItem: DispatchWorkItem?
    private let connection: NWConnection
    private let continuation: CheckedContinuation<HostPortReachabilityProber.ProbeResult, Never>
    private let start: ContinuousClock.Instant

    init(
        connection: NWConnection,
        continuation: CheckedContinuation<HostPortReachabilityProber.ProbeResult, Never>,
        start: ContinuousClock.Instant
    ) {
        self.connection = connection
        self.continuation = continuation
        self.start = start
    }

    func setTimeout(_ item: DispatchWorkItem) {
        lock.lock()
        defer { lock.unlock() }
        if completed {
            item.cancel()
        } else {
            timeoutItem = item
        }
    }

    func finish(isReachable: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let timeout = timeoutItem
        timeoutItem = nil
        lock.unlock()

        timeout?.cancel()
        let elapsed = ContinuousClock.now - start
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(
            returning: HostPortReachabilityProber.ProbeResult(
                isReachable: isReachable,
                latencyMs: isReachable ? max(1, ms) : nil
            )
        )
    }
}
