import Foundation
import Network
import Combine

/// Discovered Mac on the local Wi-Fi / LAN running macOS Screen Sharing or VNC.
public struct DiscoveredMac: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { "\(name)_\(host)_\(port)" }
    public let name: String
    public let host: String
    public let port: UInt16
    public let isScreenSharing: Bool

    public init(name: String, host: String, port: UInt16 = RFBConstants.defaultPort, isScreenSharing: Bool = true) {
        self.name = name
        self.host = host
        self.port = port
        self.isScreenSharing = isScreenSharing
    }

    /// Converts to RemoteDevice for quick connection and saving
    public func toRemoteDevice() -> RemoteDevice {
        RemoteDevice(
            name: name,
            host: host,
            port: port,
            deviceType: .mac,
            authMethod: .vncPassword,
            isOnline: true,
            isTailscaleNode: false
        )
    }
}

/// Discovers nearby Macs with Screen Sharing enabled over Bonjour (mDNS / _rfb._tcp) using Network.framework.
public final class BonjourDiscoveryService: ObservableObject, @unchecked Sendable {
    public static let shared = BonjourDiscoveryService()

    @Published public private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published public private(set) var isSearching: Bool = false

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.aethernative.aetherscreens.bonjour", qos: .utility)
    private let lock = NSLock()
    private var discoveryGeneration = UUID()
    // Resolution and publication run on the main run loop used by NetService.
    private var resolvers: [String: BonjourServiceResolver] = [:]
    private var resolvedDevices: [String: DiscoveredMac] = [:]
    private var activeServiceKeys: Set<String> = []
    private var directDevices: [DiscoveredMac] = []

    public init() {}

    /// Start browsing for local Macs with Screen Sharing enabled (_rfb._tcp)
    public func startDiscovery() {
        lock.lock()
        defer { lock.unlock() }

        guard browser == nil else { return }
        discoveryGeneration = UUID()

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_rfb._tcp", domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let b = NWBrowser(for: descriptor, using: parameters)
        self.browser = b

        b.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results)
        }

        b.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                switch state {
                case .ready:
                    self.isSearching = true
                case .failed, .cancelled:
                    self.isSearching = false
                default:
                    break
                }
            }
        }

        b.start(queue: queue)
    }

    /// Stop Bonjour discovery to conserve battery
    public func stopDiscovery() {
        lock.lock()
        defer { lock.unlock() }

        browser?.cancel()
        browser = nil
        discoveryGeneration = UUID()

        Task { @MainActor in
            self.isSearching = false
            self.resolvers.values.forEach { $0.stop() }
            self.resolvers.removeAll()
            self.resolvedDevices.removeAll()
            self.activeServiceKeys.removeAll()
            self.discoveredMacs = []
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        lock.lock()
        let generation = discoveryGeneration
        lock.unlock()
        Task { @MainActor in
            guard self.isCurrentDiscovery(generation) else { return }
            var services: [String: (String, String, String)] = [:]
            var devices: [DiscoveredMac] = []
            for result in results {
                switch result.endpoint {
                case .service(let name, let type, let domain, _):
                    services["\(name)|\(type)|\(domain)"] = (name, type, domain)
                case .hostPort(let host, let port):
                    devices.append(
                        DiscoveredMac(
                            name: "Mac (\(host))",
                            host: "\(host)",
                            port: port.rawValue,
                            isScreenSharing: true
                        )
                    )
                default:
                    break
                }
            }
            self.activeServiceKeys = Set(services.keys)
            self.directDevices = devices
            for key in Array(self.resolvers.keys) where services[key] == nil {
                self.resolvers.removeValue(forKey: key)?.stop()
                self.resolvedDevices.removeValue(forKey: key)
            }
            for (key, (name, type, domain)) in services where self.resolvers[key] == nil {
                let resolver = BonjourServiceResolver(name: name, type: type, domain: domain) { [weak discovery = self] device in
                    guard let discovery, discovery.activeServiceKeys.contains(key), discovery.isCurrentDiscovery(generation) else { return }
                    discovery.resolvedDevices[key] = device
                    discovery.publishResolvedDevices()
                }
                self.resolvers[key] = resolver
                resolver.start()
            }
            self.publishResolvedDevices()
        }
    }

    private func publishResolvedDevices() {
        discoveredMacs = (directDevices + Array(resolvedDevices.values)).sorted { $0.id < $1.id }
    }

    private func isCurrentDiscovery(_ generation: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return browser != nil && discoveryGeneration == generation
    }
}

/// Bonjour instance names are display labels, not DNS host names. Resolve the
/// service's SRV record rather than guessing an address from its label.
private final class BonjourServiceResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private let completion: (DiscoveredMac) -> Void

    init(name: String, type: String, domain: String, completion: @escaping (DiscoveredMac) -> Void) {
        service = NetService(domain: domain, type: type, name: name)
        self.completion = completion
        super.init()
        service.delegate = self
    }

    func start() { service.resolve(withTimeout: 5) }
    func stop() { service.stop() }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let device = Self.resolvedDevice(name: sender.name, host: sender.hostName, port: sender.port) else { return }
        completion(device)
    }

    static func resolvedDevice(name: String, host: String?, port: Int) -> DiscoveredMac? {
        guard let host, !host.isEmpty, let port = UInt16(exactly: port), port > 0 else { return nil }
        return DiscoveredMac(name: name, host: host, port: port)
    }
}
