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

    public init() {}

    /// Start browsing for local Macs with Screen Sharing enabled (_rfb._tcp)
    public func startDiscovery() {
        lock.lock()
        defer { lock.unlock() }

        guard browser == nil else { return }

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

        Task { @MainActor in
            self.isSearching = false
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        var devices: [DiscoveredMac] = []

        for result in results {
            switch result.endpoint {
            case .service(let name, _, let domain, _):
                let friendlyName = name
                let host = "\(name).\(domain)".replacingOccurrences(of: " ", with: "-")
                devices.append(
                    DiscoveredMac(
                        name: friendlyName,
                        host: host,
                        port: RFBConstants.defaultPort,
                        isScreenSharing: true
                    )
                )
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

        Task { @MainActor in
            self.discoveredMacs = devices
        }
    }
}
