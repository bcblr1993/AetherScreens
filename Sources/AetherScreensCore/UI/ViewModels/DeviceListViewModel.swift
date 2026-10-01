import Foundation
import SwiftUI
import Combine

/// ViewModel managing the device library, Bonjour nearby discovery, Tailnet discovery, and active sessions.
@MainActor
public final class DeviceListViewModel: ObservableObject {
    @Published public var devices: [RemoteDevice] = []
    @Published public var discoveredNearbyMacs: [DiscoveredMac] = []
    @Published public var isSearchingBonjour: Bool = false
    @Published public var searchText: String = ""
    @Published public var isSyncingTailscale: Bool = false
    @Published public var tailscaleApiKey: String = ""
    @Published public var tailnetName: String = ""
    @Published public var activeSessionDevice: RemoteDevice?
    @Published public var errorMessage: String?
    @Published public var statusNotice: String?

    private let store: DeviceStore
    private let bonjourService: BonjourDiscoveryService
    private var cancellables = Set<AnyCancellable>()

    public init(store: DeviceStore = .shared, bonjourService: BonjourDiscoveryService = .shared) {
        self.store = store
        self.bonjourService = bonjourService
        self.devices = store.devices

        setupBonjourBindings()
    }

    private func setupBonjourBindings() {
        bonjourService.$discoveredMacs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovered in
                guard let self else { return }
                self.discoveredNearbyMacs = discovered
                if self.store.repairLegacyBonjourHosts(using: discovered) { self.reload() }
            }
            .store(in: &cancellables)

        bonjourService.$isSearching
            .receive(on: DispatchQueue.main)
            .assign(to: \.isSearchingBonjour, on: self)
            .store(in: &cancellables)

        // Start local network discovery
        bonjourService.startDiscovery()
    }

    public var filteredDevices: [RemoteDevice] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return devices
        }
        return devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Reload devices from store
    public func reload() {
        store.loadDevices()
        self.devices = store.devices
    }

    /// Add a new device manually
    public func addDevice(
        name: String,
        host: String,
        port: UInt16,
        type: RemoteDevice.DeviceType,
        password: String?,
        macAddress: String? = nil,
        username: String? = nil
    ) {
        let dev = RemoteDevice(
            name: name,
            host: host,
            port: port,
            deviceType: type,
            authMethod: username == nil ? (password == nil ? .none : .vncPassword) : .macAccount,
            username: username,
            isOnline: true,
            macAddress: macAddress
        )
        store.addDevice(dev, password: password)
        reload()
    }

    /// Connect directly to a discovered Bonjour Mac
    public func addDiscoveredMac(_ mac: DiscoveredMac, password: String? = nil) {
        let dev = mac.toRemoteDevice()
        store.addDevice(dev, password: password)
        reload()
        connect(to: dev)
    }

    /// Delete a device
    public func deleteDevice(_ device: RemoteDevice) {
        store.deleteDevice(device)
        reload()
    }

    /// Wake a sleeping Mac via Wake-on-LAN Magic Packet
    public func wakeDevice(_ device: RemoteDevice) {
        guard let mac = device.macAddress, !mac.isEmpty else {
            errorMessage = "No MAC address configured for this Mac."
            return
        }

        WakeOnLANService.wakeDevice(macAddress: mac) { [weak self] success in
            Task { @MainActor in
                if success {
                    self?.statusNotice = "Wake-on-LAN Magic Packet sent to \(device.name)"
                } else {
                    self?.errorMessage = "Failed to send Wake-on-LAN packet. Check MAC format."
                }
            }
        }
    }

    /// Sync online devices from Tailscale API
    public func syncTailscale() async {
        guard !tailscaleApiKey.isEmpty else {
            errorMessage = "Please enter your Tailscale API Key in Settings"
            return
        }

        isSyncingTailscale = true
        errorMessage = nil

        let client = TailscaleClient(apiKey: tailscaleApiKey, tailnet: tailnetName)
        do {
            let nodes = try await client.fetchDevices()
            store.mergeTailscaleDevices(nodes)
            reload()
            statusNotice = "Synced \(nodes.count) nodes from Tailscale"
        } catch {
            errorMessage = error.localizedDescription
        }

        isSyncingTailscale = false
    }

    /// Prepare a temporary session, persisting only when explicitly requested.
    public func prepareQuickSession(_ request: ConnectionRequest, saveComputer: Bool) -> SessionViewModel {
        if saveComputer {
            store.addDevice(request.device, password: request.password)
            reload()
        }
        return SessionViewModel(device: request.device, password: request.password,
                                isTemporary: !saveComputer, deviceStore: store)
    }

    /// Start a remote desktop session with the given device
    public func connect(to device: RemoteDevice) {
        activeSessionDevice = device
    }
}
