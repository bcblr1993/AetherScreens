import Foundation
import SwiftUI
import Combine

/// ViewModel managing the device library, Bonjour nearby discovery, Tailnet discovery, and active sessions.
@MainActor
public final class DeviceListViewModel: ObservableObject {
    public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
        case custom = "Default Order"
        case name = "Sort by Name"
        case lastConnected = "Sort by Recently Connected"
        case favoritesFirst = "Sort by Favorites First"
        case protocolType = "Sort by Protocol"

        public var id: String { rawValue }
    }

    public static let sortOrderKey = "com.aethernative.aetherscreens.library.sortOrder"

    @Published public var devices: [RemoteDevice] = []
    @Published public var discoveredNearbyMacs: [DiscoveredMac] = []
    @Published public var isSearchingBonjour: Bool = false
    @Published public var searchText: String = ""
    @Published public var selectedTag: String? = nil
    @Published public var sortOrder: SortOrder = .custom {
        didSet {
            userDefaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }
    @Published public var isSyncingTailscale: Bool = false
    @Published public var tailscaleApiKey: String = ""
    @Published public var tailnetName: String = ""
    @Published public var activeSessionDevice: RemoteDevice?
    @Published public var errorMessage: String?
    @Published public var statusNotice: String?
    @Published public var syncService: ComputerSyncService
    @Published public private(set) var lastProbeLatencyMs: [UUID: Int] = [:]
    @Published public private(set) var isProbingReachability: Bool = false

    private let store: DeviceStore
    private let userDefaults: UserDefaults
    private let sshCredentials: SSHCredentialStore
    private let sshTrust: SSHHostTrustStore
    private let bonjourService: BonjourDiscoveryService
    private var cancellables = Set<AnyCancellable>()

    public init(store: DeviceStore = .shared, bonjourService: BonjourDiscoveryService = .shared,
                sshTrust: SSHHostTrustStore = .shared, syncService: ComputerSyncService? = nil,
                userDefaults: UserDefaults = .standard) {
        self.store = store
        self.userDefaults = userDefaults
        self.sshCredentials = store.sshCredentials
        self.sshTrust = sshTrust
        self.bonjourService = bonjourService
        self.syncService = syncService ?? ComputerSyncService(store: store)
        self.devices = store.devices
        if let raw = userDefaults.string(forKey: Self.sortOrderKey),
           let savedOrder = SortOrder(rawValue: raw) {
            self.sortOrder = savedOrder
        }

        setupBonjourBindings()
        setupSyncBindings()
    }

    private func setupSyncBindings() {
        syncService.$status
            .sink { [weak self] status in
                if case .synced = status {
                    self?.reload()
                }
            }
            .store(in: &cancellables)
    }

    private func setupBonjourBindings() {
        bonjourService.$discoveredMacs
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] discovered in
                guard let self else { return }
                if self.discoveredNearbyMacs != discovered { self.discoveredNearbyMacs = discovered }
                if self.store.repairLegacyBonjourHosts(using: discovered) { self.reload() }
            }
            .store(in: &cancellables)

        bonjourService.$isSearching
            .receive(on: DispatchQueue.main)
            .sink { [weak self] searching in
                guard let self, self.isSearchingBonjour != searching else { return }
                self.isSearchingBonjour = searching
            }
            .store(in: &cancellables)

        // Start local network discovery
        bonjourService.startDiscovery()
    }

    public var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var filteredNearbyMacs: [DiscoveredMac] {
        let query = normalizedSearchQuery
        guard !query.isEmpty else { return discoveredNearbyMacs }
        return discoveredNearbyMacs.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.host.localizedCaseInsensitiveContains(query)
        }
    }

    public var allTags: [String] {
        var unique = Set<String>()
        for dev in devices {
            for tag in dev.tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { unique.insert(trimmed) }
            }
        }
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public var tagCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for dev in devices {
            var seenOnDevice = Set<String>()
            for tag in dev.tags {
                let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, seenOnDevice.insert(trimmed).inserted {
                    counts[trimmed, default: 0] += 1
                }
            }
        }
        return counts
    }

    public var filteredDevices: [RemoteDevice] {
        let query = normalizedSearchQuery
        let activeTag = selectedTag?.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = devices.filter { dev in
            if let activeTag, !activeTag.isEmpty {
                let matchesTag = dev.tags.contains { $0.caseInsensitiveCompare(activeTag) == .orderedSame }
                if !matchesTag { return false }
            }
            if query.isEmpty { return true }
            return dev.name.localizedCaseInsensitiveContains(query)
                || dev.host.localizedCaseInsensitiveContains(query)
                || (dev.username?.localizedCaseInsensitiveContains(query) ?? false)
                || (dev.notes?.localizedCaseInsensitiveContains(query) ?? false)
                || dev.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
        return sortDevices(matching)
    }

    private func sortDevices(_ list: [RemoteDevice]) -> [RemoteDevice] {
        switch sortOrder {
        case .custom:
            return list
        case .name:
            return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastConnected:
            return list.sorted { lhs, rhs in
                switch (lhs.lastConnected, rhs.lastConnected) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        case .favoritesFirst:
            return list.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        case .protocolType:
            return list.sorted { lhs, rhs in
                if lhs.remoteProtocol != rhs.remoteProtocol {
                    return lhs.remoteProtocol.rawValue < rhs.remoteProtocol.rawValue
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    public func exportLibraryArchive() throws -> Data {
        try store.exportArchive()
    }

    @discardableResult
    public func importLibraryArchive(_ data: Data) throws -> Int {
        let count = try store.importArchive(data)
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
        statusNotice = AppLocalization.format("Imported %d computer(s)", count)
        return count
    }

    @discardableResult
    public func importFromSSHConfig(contents: String) -> Int {
        let entries = SSHConfigParser.parse(contents)
        var addedCount = 0
        for entry in entries {
            guard let sshSettings = entry.toSSHConnectionSettings() else { continue }
            let existing = devices.contains { $0.name.caseInsensitiveCompare(entry.alias) == .orderedSame || $0.host.caseInsensitiveCompare(entry.hostName) == .orderedSame }
            guard !existing else { continue }
            let dev = RemoteDevice(
                name: entry.alias,
                host: entry.hostName,
                port: RFBConstants.defaultPort,
                deviceType: .mac,
                remoteProtocol: .rfb,
                authMethod: .vncPassword,
                username: entry.user,
                ssh: sshSettings,
                tags: ["SSH"]
            )
            _ = store.addDevice(dev)
            addedCount += 1
        }
        if addedCount > 0 {
            reload()
            Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
            statusNotice = AppLocalization.format("Imported %d computer(s)", addedCount)
        } else {
            statusNotice = AppLocalization.string("No new SSH hosts found in ~/.ssh/config")
        }
        return addedCount
    }

    /// Reload devices from store
    public func reload() {
        store.loadDevices()
        if devices != store.devices { devices = store.devices }
    }

    /// Publish one coherent list update after the configuration snapshot is persisted.
    /// Connection state and the active session are independent of remote library edits.
    @discardableResult
    public func applySyncJournal(_ journal: ComputerSyncJournal) throws -> Bool {
        guard try store.applySyncJournal(journal) else { return false }
        devices = store.devices
        return true
    }

    @discardableResult
    public func mergeSyncSnapshot(_ data: Data) throws -> ComputerSyncJournal.MergeResult {
        let result = try store.mergeSyncSnapshot(data)
        if devices != store.devices { devices = store.devices }
        return result
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
        if !store.addDevice(dev, password: password) {
            errorMessage = "Computer saved, but its password could not be saved to Keychain. Re-enter it after restarting the app."
        }
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
    }

    /// Connect directly to a discovered Bonjour Mac
    public func addDiscoveredMac(_ mac: DiscoveredMac, password: String? = nil) {
        let dev = mac.toRemoteDevice()
        if !store.addDevice(dev, password: password) {
            errorMessage = "Computer saved, but its password could not be saved to Keychain. Re-enter it after restarting the app."
        }
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
        connect(to: dev)
    }

    /// Delete a device
    public func deleteDevice(_ device: RemoteDevice) {
        guard store.deleteDevice(device) else {
            errorMessage = "Could not remove the SSH password from Keychain. The computer was kept."
            return
        }
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
    }

    /// Duplicate an existing device configuration
    @discardableResult
    public func duplicateDevice(_ device: RemoteDevice) -> RemoteDevice {
        let copy = store.duplicateDevice(device)
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
        statusNotice = AppLocalization.format("Duplicated '%@'", device.name)
        return copy
    }

    /// Probe saved computers via TCP handshake and update their online status and latency
    public func probeSavedDevicesReachability(using prober: HostPortReachabilityProber = HostPortReachabilityProber()) async {
        guard !isProbingReachability else { return }
        isProbingReachability = true
        defer { isProbingReachability = false }

        let snapshot = devices
        guard !snapshot.isEmpty else { return }
        let results = await prober.probeAll(snapshot)
        var changed = false
        for var dev in snapshot {
            guard let res = results[dev.id] else { continue }
            if let ms = res.latencyMs {
                lastProbeLatencyMs[dev.id] = ms
            } else {
                lastProbeLatencyMs.removeValue(forKey: dev.id)
            }
            if dev.isOnline != res.isReachable {
                dev.isOnline = res.isReachable
                _ = store.updateDevice(dev)
                changed = true
            }
        }
        if changed {
            reload()
        }
    }

    /// Toggle favorite status of a device and persist
    public func toggleFavorite(for device: RemoteDevice) {
        var updated = device
        updated.isFavorite.toggle()
        _ = store.updateDevice(updated)
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
    }

    /// Update tags for a device and persist
    public func updateTags(for device: RemoteDevice, tags: [String]) {
        var updated = device
        updated.tags = tags
        _ = store.updateDevice(updated)
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
    }

    /// Read only public identity for the editor. Saved key bytes never become
    /// editable form state or an implicitly imported replacement.
    public func sshKeyFingerprint(for settings: SSHConnectionSettings?) throws -> String? {
        guard case .privateKey(let reference) = settings?.authentication else { return nil }
        guard let data = try sshCredentials.load(kind: .privateKey, reference: reference) else {
            throw SSHPrivateKey.Failure.missing
        }
        return try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data))
    }

    @Published private var libraryKeyChoices: [SavedSSHKey] = []

    public struct SavedSSHKey: Identifiable {
        public let id: UUID
        public let name: String
    }

    /// Shared references appear once; listing computers never reads private data.
    public var savedSSHKeys: [SavedSSHKey] {
        var seen = Set<UUID>()
        let computerKeys: [SavedSSHKey] = devices.compactMap { device in
            guard let settings = device.ssh, case .privateKey(let reference) = settings.authentication,
                  seen.insert(reference).inserted else { return nil }
            return SavedSSHKey(id: reference, name: store.sshKeyName(for: reference) ?? device.name)
        }
        return computerKeys + libraryKeyChoices.filter { seen.insert($0.id).inserted }
    }

    public func selectSavedSSHKey(_ key: SavedSSHKey, draft: inout SSHConnectionDraft) throws {
        guard let data = try sshCredentials.load(kind: .privateKey, reference: key.id) else {
            throw SSHPrivateKey.Failure.missing
        }
        let fingerprint = try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data))
        draft.useSavedPrivateKey(reference: key.id, fingerprint: fingerprint)
    }

    public struct ManagedSSHKey: Identifiable {
        public let id: UUID
        public let name: String?
        public let fingerprint: String?
        public let problem: String?
        public let computers: [String]
    }
    public enum KeyManagementFailure: Error, LocalizedError {
        case inUse, changed
        public var errorDescription: String? {
            switch self {
            case .inUse: return AppLocalization.string("This private key is used by a saved computer or an open session.")
            case .changed: return AppLocalization.string("This private key changed. Reload the key library and try again.")
            }
        }
    }

    public func managedSSHKeys() throws -> [ManagedSSHKey] {
        let keys = try sshCredentials.references(kind: .privateKey).map { reference in
            let data = try sshCredentials.load(kind: .privateKey, reference: reference)
            var fingerprint: String?
            var problem: String?
            do {
                guard let data else { throw SSHPrivateKey.Failure.missing }
                fingerprint = try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data))
            } catch {
                problem = (error as? SSHPrivateKey.Failure)?.errorDescription
                    ?? AppLocalization.string("Could not read the SSH key file.")
            }
            return ManagedSSHKey(id: reference, name: store.sshKeyName(for: reference), fingerprint: fingerprint, problem: problem,
                computers: store.devices.filter { $0.ssh?.authentication == .privateKey(reference) }.map(\.name).sorted())
        }
        libraryKeyChoices = keys.compactMap { key in
            guard let fingerprint = key.fingerprint else { return nil }
            return SavedSSHKey(id: key.id, name: key.name ?? fingerprint)
        }
        return keys
    }

    @discardableResult
    public func importManagedSSHKey(_ data: Data) throws -> ManagedSSHKey {
        let fingerprint = try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data))
        let reference = UUID()
        guard try sshCredentials.load(kind: .privateKey, reference: reference) == nil else {
            throw SSHPrivateKey.Failure.invalid
        }
        try sshCredentials.save(data, kind: .privateKey, reference: reference)
        libraryKeyChoices.append(SavedSSHKey(id: reference, name: fingerprint))
        return ManagedSSHKey(id: reference, name: store.sshKeyName(for: reference), fingerprint: fingerprint, problem: nil, computers: [])
    }

    /// Read only after export confirmation, rechecking the identity shown to the user.
    public func exportManagedSSHKey(_ reference: UUID, expectedFingerprint: String) throws -> Data {
        guard let data = try sshCredentials.load(kind: .privateKey, reference: reference) else {
            throw SSHPrivateKey.Failure.missing
        }
        let fingerprint = try SSHPrivateKey.fingerprint(SSHPrivateKey.decode(data))
        guard fingerprint == expectedFingerprint else { throw KeyManagementFailure.changed }
        return data
    }

    public func renameManagedSSHKey(_ reference: UUID, name: String) throws {
        // Check the vault before recording metadata for a deleted or denied key.
        guard try sshCredentials.load(kind: .privateKey, reference: reference) != nil else {
            throw SSHPrivateKey.Failure.missing
        }
        // Finish every fallible vault read before changing persisted labels.
        let entries = try managedSSHKeys()
        store.setSSHKeyName(String(name.prefix(120)), for: reference)
        libraryKeyChoices = entries.compactMap { key in
            guard let fingerprint = key.fingerprint else { return nil }
            return SavedSSHKey(id: key.id, name: store.sshKeyName(for: key.id) ?? fingerprint)
        }
    }

    public func removeManagedSSHKey(_ reference: UUID, sessions: SessionRegistry? = nil) throws {
        let registry = sessions ?? SessionRegistry.shared
        let used = store.devices.contains { $0.ssh?.authentication == .privateKey(reference) }
            || registry.sessions.contains { $0.viewModel.device.ssh?.authentication == .privateKey(reference) }
        guard !used else { throw KeyManagementFailure.inUse }
        try sshCredentials.remove(kind: .privateKey, reference: reference)
        store.setSSHKeyName(nil, for: reference)
        libraryKeyChoices.removeAll { $0.id == reference }
    }

    /// Persist secrets before changing the saved computer. A vault failure must
    /// leave its prior configuration intact and keep the editing sheet open.
    public func saveConfiguredDevice(_ device: RemoteDevice, password: String?, sshPassword: String?, sshPrivateKey: Data? = nil) throws {
        let previous = store.devices.first { $0.id == device.id }
        var newlySavedKey: UUID?
        if let sshPrivateKey, case .privateKey(let reference) = device.ssh?.authentication {
            _ = try SSHPrivateKey.decode(sshPrivateKey)
            // Imported keys use a new reference; never overwrite a shared key.
            guard try sshCredentials.load(kind: .privateKey, reference: reference) == nil else {
                throw SSHPrivateKey.Failure.invalid
            }
            try sshCredentials.save(sshPrivateKey, kind: .privateKey, reference: reference)
            newlySavedKey = reference
        } else if case .privateKey = device.ssh?.authentication,
                  device.ssh?.authentication != previous?.ssh?.authentication {
            // Recheck reused identities at commit time: a key can disappear
            // after selection. Do not save a new dangling key reference.
            _ = try sshKeyFingerprint(for: device.ssh)
        }
        do {
            if let sshPassword, device.ssh != nil {
                try sshCredentials.save(Data(sshPassword.utf8), kind: .password, reference: device.id)
                store.bindSavedSSHPassword(for: device)
            } else if let previousSSH = previous?.ssh,
                      device.ssh?.server.identity != previousSSH.server.identity || device.ssh?.username != previousSSH.username || device.ssh?.authentication != previousSSH.authentication {
                try sshCredentials.remove(kind: .password, reference: device.id)
            }
        } catch {
            if let newlySavedKey { try? sshCredentials.remove(kind: .privateKey, reference: newlySavedKey) }
            throw error
        }
        if !store.addDevice(device, password: password) {
            errorMessage = "Computer saved, but its password could not be saved to Keychain. Re-enter it after restarting the app."
        }
        reload()
        Task { [weak self] in await self?.syncService.notifyLibraryChanged() }
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

    /// Sync online devices from Tailscale API (or zero-config local Tailscale CLI on macOS)
    public func syncTailscale() async {
        guard !isSyncingTailscale, !Task.isCancelled else { return }

        isSyncingTailscale = true
        defer { isSyncingTailscale = false }
        errorMessage = nil

        if tailscaleApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let nodes = try await TailscaleClient.fetchLocalStatusDevices()
                try Task.checkCancellation()
                store.mergeTailscaleDevices(nodes)
                reload()
                statusNotice = "Synced \(nodes.count) nodes from Tailscale"
                return
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Please enter your Tailscale API Key in Settings"
                }
                return
            }
        }

        let client = TailscaleClient(apiKey: tailscaleApiKey, tailnet: tailnetName)
        do {
            let nodes = try await client.fetchDevices()
            try Task.checkCancellation()
            store.mergeTailscaleDevices(nodes)
            reload()
            statusNotice = "Synced \(nodes.count) nodes from Tailscale"
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    /// Prepare a temporary session, persisting only when explicitly requested.
    public func prepareQuickSession(_ request: ConnectionRequest, saveComputer: Bool) throws -> SessionViewModel {
        if saveComputer {
            try saveConfiguredDevice(request.device, password: request.password, sshPassword: request.sshPassword, sshPrivateKey: request.sshPrivateKey)
        }
        return SessionViewModel(device: request.device, password: request.password,
                                isTemporary: !saveComputer, deviceStore: store,
                                sshCredentials: sshCredentials, sshTrust: sshTrust,
                                initialSSHPassword: request.sshPassword, initialSSHPrivateKey: request.sshPrivateKey)
    }

    /// Start a remote desktop session with the given device
    public func connect(to device: RemoteDevice) {
        activeSessionDevice = device
    }
}
