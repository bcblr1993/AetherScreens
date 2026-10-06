import Foundation
import AetherScreensSSH

/// Manages persistence, discovery merging, and updates for configured remote devices.
public final class DeviceStore: @unchecked Sendable {
    public static let shared = DeviceStore(legacySources: [.standard])

    public static let storageKey = "com.aethernative.aetherscreens.devices.list"
    /// Key used by builds released under the TailScreens name.
    public static let legacyStorageKey = "com.tailscreens.devices.list"
    static let libraryDidChange = Notification.Name("AetherScreensDeviceLibraryDidChange")
    var synchronizationDefaults: UserDefaults { userDefaults }

    public func devicesSnapshot() -> [RemoteDevice] {
        lock.lock(); defer { lock.unlock() }
        return devices
    }

    /// Destructive shortcut pruning requires verified saved metadata, not the
    /// empty fallback used when loading an unavailable or damaged library.
    /// This read never repairs preferences, migrates data, or reads credentials.
    public func shortcutPruningSnapshot() -> Set<UUID>? {
        verifiedSavedDevicesSnapshot().map { Set($0.map(\.id)) }
    }

    /// Resolve a widget from the same verified, current metadata that admits its ID.
    public func verifiedSavedDevicesSnapshot() -> [RemoteDevice]? {
        lock.lock(); defer { lock.unlock() }
        let legacyObject = userDefaults.object(forKey: storageKey)
        let checkpointObject = userDefaults.object(forKey: DeviceLibrarySyncCheckpoint.key)
        if let legacyObject, !(legacyObject is Data) { return nil }
        if let checkpointObject, !(checkpointObject is Data) { return nil }
        let legacyData = legacyObject as? Data
        let saved: [RemoteDevice]
        if let checkpointData = checkpointObject as? Data {
            guard let checkpoint = try? DeviceLibrarySyncCheckpoint(data: checkpointData) else { return nil }
            let legacyDigest = DeviceLibrarySyncCheckpoint.digest(legacyData)
            guard legacyDigest == DeviceLibrarySyncCheckpoint.digest(checkpoint.devicesData) ||
                    legacyDigest == checkpoint.previousLegacyDigest,
                  let decoded = try? checkpoint.devices() else { return nil }
            saved = decoded
        } else {
            guard let legacyData,
                  let decoded = try? JSONDecoder().decode([RemoteDevice].self, from: legacyData) else { return nil }
            saved = decoded
        }
        let identifiers = Set(saved.map(\.id))
        return identifiers.count == saved.count ? saved : nil
    }

    private let storageKey = DeviceStore.storageKey
    private let userDefaults: UserDefaults
    private let keychain: any DevicePasswordStore
    private let sshKeychain: SSHKeychainStore
    var sshCredentialStore: SSHKeychainStore { sshKeychain }
    private let lock = NSLock()
    private static let checkpointPersistenceLock = NSLock()
    private var syncCheckpoint: DeviceLibrarySyncCheckpoint?
    private var storedCheckpointData: Data?
    private var storedLegacyData: Data?
    private var syncGeneration = UUID()
    private var syncFailure: DeviceSyncDocument.Failure?
    private var preferenceObserver: NSObjectProtocol?
    private var credentialSync: DeviceCredentialSyncStore?
    private var credentialFailure: DeviceCredentialSyncStore.Failure?

    public var credentialSynchronizationFailure: DeviceCredentialSyncStore.Failure? {
        lock.lock(); defer { lock.unlock() }; return credentialFailure
    }

    /// Invoked only by the controller after the metadata account check. The same
    /// lock protects live endpoints, invalidations, and credential bootstrap.
    func synchronizeCredentials(using provider: DeviceCredentialSyncStore) throws {
        lock.lock(); defer { lock.unlock() }
        guard let checkpoint = syncCheckpoint, checkpoint.storage == .iCloud else {
            throw DeviceSyncFailure.localStorageSelected
        }
        credentialSync?.setCloudAccess(false)
        credentialSync = provider; provider.setCloudAccess(true)
        do {
            try provider.synchronize(devices: devices, deletedIDs: checkpoint.document().deletedIdentifiers,
                localPassword: { device in
                    checkpoint.passwordInvalidations.contains(device.id) ? nil : self.keychain.loadPassword(forKey: device.id.uuidString)
                }, localSSH: { device in
                    guard !checkpoint.sshInvalidations.contains(device.id), let configuration = device.sshConfiguration else { return nil }
                    return try self.sshKeychain.load(for: device.id, configuration: configuration)
                })
            credentialFailure = nil
        } catch {
            credentialFailure = error as? DeviceCredentialSyncStore.Failure ?? .invalidRecord
            throw error
        }
    }

    func installLocalCredentialProvider(_ provider: DeviceCredentialSyncStore) {
        lock.lock(); defer { lock.unlock() }
        credentialSync?.setCloudAccess(false); provider.setCloudAccess(false)
        credentialSync = provider
    }

    func suspendCredentialSynchronization() {
        lock.lock(); defer { lock.unlock() }
        credentialSync?.setCloudAccess(false)
    }

    public private(set) var devices: [RemoteDevice] = []

    public var storageMode: DeviceLibraryStorage {
        lock.lock(); defer { lock.unlock() }
        return syncCheckpoint?.storage ?? .local
    }

    public var synchronizationFailure: DeviceSyncDocument.Failure? {
        lock.lock(); defer { lock.unlock() }
        return syncFailure
    }

    /// - Parameter legacySources: defaults searched for a TailScreens device list when nothing is stored yet.
    public convenience init(userDefaults: UserDefaults = .standard,
                legacySources: [UserDefaults] = [],
                keychain: KeychainStore = .shared,
                sshKeychain: SSHKeychainStore = .shared) {
        self.init(userDefaults: userDefaults, legacySources: legacySources, passwordStore: keychain, sshKeychain: sshKeychain)
    }

    init(userDefaults: UserDefaults, legacySources: [UserDefaults] = [],
         passwordStore: any DevicePasswordStore, sshKeychain: SSHKeychainStore) {
        self.userDefaults = userDefaults
        self.keychain = passwordStore
        self.sshKeychain = sshKeychain
        migrateLegacyDevicesIfNeeded(from: legacySources)
        loadDevices()
        preferenceObserver = NotificationCenter.default.addObserver(forName: DevicePreferenceStorage.didChange,
                                                                      object: nil, queue: nil) { [weak self] change in
            guard let self, (change.object as? UserDefaults) === self.userDefaults,
                  change.userInfo?["origin"] as? DevicePreferenceStorage.Origin == .local else { return }
            self.capturePreferenceChange()
        }
    }

    deinit { if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) } }

    /// Copies the TailScreens device list into the current key once. Legacy data is left untouched.
    private func migrateLegacyDevicesIfNeeded(from sources: [UserDefaults]) {
        guard userDefaults.data(forKey: storageKey) == nil,
              userDefaults.data(forKey: DeviceLibrarySyncCheckpoint.key) == nil else { return }

        for source in sources {
            guard let data = source.data(forKey: DeviceStore.legacyStorageKey),
                  let decoded = try? JSONDecoder().decode([RemoteDevice].self, from: data) else { continue }
            userDefaults.set(data, forKey: storageKey)
            AppLogger.shared.info("Migrated \(decoded.count) device(s) from TailScreens storage", category: "General")
            return
        }
    }

    /// Reload devices from storage.
    public func loadDevices() {
        lock.lock()
        defer { lock.unlock() }

        let previousReplica = syncCheckpoint?.replicaID
        let previousStorage = syncCheckpoint?.storage
        storedLegacyData = userDefaults.data(forKey: storageKey)
        storedCheckpointData = userDefaults.data(forKey: DeviceLibrarySyncCheckpoint.key)
        syncCheckpoint = nil
        syncFailure = nil
        if let data = storedCheckpointData {
            do {
                let checkpoint = try DeviceLibrarySyncCheckpoint(data: data)
                let legacyDigest = DeviceLibrarySyncCheckpoint.digest(storedLegacyData)
                guard legacyDigest == DeviceLibrarySyncCheckpoint.digest(checkpoint.devicesData) ||
                        legacyDigest == checkpoint.previousLegacyDigest else {
                    throw DeviceSyncDocument.Failure.staleLocalReplica
                }
                devices = try checkpoint.devices()
                if let target = checkpoint.preferencesData, let prior = checkpoint.previousPreferencesData {
                    let recovered = try DevicePreferenceStorage.withLock {
                        try DevicePreferenceSnapshot(data: target).recoverMirror(
                            in: userDefaults, previous: DevicePreferenceSnapshot(data: prior))
                    }
                    if recovered { DevicePreferenceStorage.notify(userDefaults, origin: .remote) }
                }
                syncCheckpoint = checkpoint
                if previousReplica != checkpoint.replicaID || previousStorage != checkpoint.storage {
                    syncGeneration = UUID()
                }
                return
            } catch {
                // Preserve the invalid checkpoint. Local edits can still use the legacy list.
                syncFailure = error as? DeviceSyncDocument.Failure ?? .invalidDocument
            }
        }
        guard let data = storedLegacyData else {
            self.devices = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([RemoteDevice].self, from: data)
            self.devices = decoded
        } catch {
            print("[DeviceStore] Failed to decode devices: \(error)")
            self.devices = []
        }
    }

    /// Add a new device and optionally save its password to Keychain.
    /// SSH storage must succeed before the corresponding device becomes visible.
    public func saveConnection(_ request: ConnectionRequest) throws {
        if let configuration = request.device.sshConfiguration, let credentials = request.sshCredentials {
            try sshKeychain.save(credentials, for: request.device.id, configuration: configuration)
            authorizeLocalSSHCredentials(for: request.device.id)
            try stageSSHCredential(credentials, for: request.device)
        }
        try saveDevice(request.device, password: request.password, newSSHCredentials: request.sshCredentials != nil)
    }

    public func getSSHCredentials(for device: RemoteDevice) throws -> SSHSessionCredentials? {
        lock.lock(); defer { lock.unlock() }
        guard let current = devices.first(where: { $0.id == device.id }),
              DeviceLibrarySyncCheckpoint.sameConnection(current, device) else {
            throw SSHKeychainStore.Failure.credentialMismatch
        }
        if let credentialSync {
            switch try credentialSync.sshCredentials(for: device) {
            case .value(let credentials): return credentials
            case .deleted: return nil
            case .missing: break
            }
        }
        guard syncCheckpoint?.sshInvalidations.contains(device.id) != true else {
            throw SSHKeychainStore.Failure.credentialMismatch
        }
        guard let configuration = device.sshConfiguration else { return nil }
        return try sshKeychain.load(for: device.id, configuration: configuration)
    }

    public func trustedSSHIdentity(for device: RemoteDevice) throws -> SSHHostKeyIdentity? {
        guard let configuration = device.sshConfiguration else { return nil }
        return try sshKeychain.trustedKey(for: configuration)
    }

    public func forgetSSHIdentity(for device: RemoteDevice, matching identity: SSHHostKeyIdentity) throws {
        guard let configuration = device.sshConfiguration,
              self.device(withID: device.id)?.sshConfiguration == configuration else {
            throw SSHKeychainStore.Failure.credentialMismatch
        }
        try sshKeychain.forgetTrustedKey(for: configuration, matching: identity)
    }

    /// Replacing SSH configuration without a new credential is rejected.
    public func updateConnection(_ device: RemoteDevice, password: String?, sshCredentials: SSHSessionCredentials?) throws {
        if let configuration = device.sshConfiguration {
            if let sshCredentials {
                try sshKeychain.save(sshCredentials, for: device.id, configuration: configuration)
                authorizeLocalSSHCredentials(for: device.id)
                try stageSSHCredential(sshCredentials, for: device)
            } else {
                guard try sshKeychain.load(for: device.id, configuration: configuration) != nil else {
                    throw SSHKeychainStore.Failure.credentialMismatch
                }
            }
        } else if self.device(withID: device.id)?.sshConfiguration != nil {
            try stageSSHDeletion(for: device.id)
            try sshKeychain.deleteCredentials(for: device.id)
        }
        try saveDevice(device, password: password, newSSHCredentials: sshCredentials != nil)
    }

    public func addDevice(_ device: RemoteDevice, password: String? = nil) {
        do { try saveDevice(device, password: password) }
        catch { AppLogger.shared.error("Could not save connection credentials.", category: "Auth") }
    }

    private func saveDevice(_ device: RemoteDevice, password: String?, newSSHCredentials: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }

        if let password, let credentialSync {
            do { try credentialSync.stagePassword(password, for: device); credentialFailure = nil }
            catch { reportCredentialFailure(error); throw error }
        }

        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            var updated = device
            let previous = devices[idx]
            if !DeviceLibrarySyncCheckpoint.sameConnection(previous, device) {
                // A UUID-only legacy entry cannot follow a new endpoint/account.
                // Local mode also records invalidation; no cloud transport is created.
                if syncCheckpoint == nil {
                    syncCheckpoint = try DeviceLibrarySyncCheckpoint(storage: .local, devices: devices)
                }
                syncCheckpoint?.passwordInvalidations.insert(device.id)
                syncCheckpoint?.sshInvalidations.insert(device.id)
            }
            if previous.host != device.host || previous.port != device.port ||
                previous.username != device.username || previous.sshConfiguration != device.sshConfiguration {
                updated.preferredDisplayID = nil
            }
            devices[idx] = updated
        } else {
            devices.append(device)
        }

        if let pwd = password {
            keychain.savePassword(pwd, forKey: device.id.uuidString)
            syncCheckpoint?.passwordInvalidations.remove(device.id)
        }
        if newSSHCredentials { syncCheckpoint?.sshInvalidations.remove(device.id) }

        persist()
        if password != nil, credentialSync != nil { notifyLibraryChange(.local, credentialsChanged: true) }
    }

    /// Merge a live speed preference without overwriting newer edits or restoring deleted targets.
    public func updateCursorSpeed(_ value: Double, for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              devices[index].host == device.host, devices[index].port == device.port,
              devices[index].username == device.username,
              devices[index].sshConfiguration == device.sshConfiguration else { return }
        let speed = RemoteDevice.validatedCursorSpeed(value)
        devices[index].cursorSpeed = speed == 1 ? nil : speed
        persist()
    }

    /// Merge only this preference into the same saved target/account.
    public func updateSharedClipboard(_ enabled: Bool, for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              devices[index].host == device.host, devices[index].port == device.port,
              devices[index].username == device.username,
              devices[index].sshConfiguration == device.sshConfiguration else { return }
        devices[index].sharedClipboard = enabled ? nil : false
        persist()
    }

    /// Merge this preference without replacing newer connection edits.
    public func updateImageCompression(_ policy: RemoteImageCompressionPolicy, for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              devices[index].host == device.host, devices[index].port == device.port,
              devices[index].username == device.username,
              devices[index].sshConfiguration == device.sshConfiguration else { return }
        devices[index].imageCompression = policy == .never ? nil : policy
        persist()
    }

    /// Save only the monitor preference for the same saved endpoint/account.
    public func updatePreferredDisplay(_ identifier: UInt32?, for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              devices[index].host == device.host, devices[index].port == device.port,
              devices[index].username == device.username,
              devices[index].sshConfiguration == device.sshConfiguration else { return }
        devices[index].preferredDisplayID = identifier
        persist()
    }

    /// Update an existing device.
    public func updateDevice(_ device: RemoteDevice, password: String? = nil) {
        addDevice(device, password: password)
    }

    /// Repair only the addresses generated by the old Bonjour name guessing.
    /// Keep the device ID and account so its Keychain entry stays associated.
    @discardableResult
    public func repairLegacyBonjourHosts(using discovered: [DiscoveredMac]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for index in devices.indices {
            let device = devices[index]
            let guessed = "\(device.name).local.".replacingOccurrences(of: " ", with: "-")
            guard !device.isTailscaleNode, device.port == RFBConstants.defaultPort,
                  device.host == guessed else { continue }
            let matches = discovered.filter { $0.name == device.name }
            guard matches.count == 1, let resolved = matches.first,
                  resolved.host != device.host || resolved.port != device.port else { continue }
            devices[index].host = resolved.host
            devices[index].port = resolved.port
            changed = true
        }
        if changed { persist() }
        return changed
    }

    /// Remove a device and its stored password.
    @discardableResult
    public func deleteDevice(_ device: RemoteDevice) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        do {
            if devices.contains(where: { $0.id == device.id }) { try credentialSync?.stageDeletion(for: device.id) }
            try sshKeychain.deleteCredentials(for: device.id)
        }
        catch {
            if credentialSync != nil { reportCredentialFailure(error) }
            AppLogger.shared.error("Could not remove SSH credentials from Keychain.", category: "Auth")
            return false
        }
        devices.removeAll { $0.id == device.id }
        keychain.deletePassword(forKey: device.id.uuidString)
        persist()
        return true
    }

    /// Merge discovered Tailscale nodes into the device list (preserves existing saved credentials).
    public func mergeTailscaleDevices(_ tailscaleNodes: [TailscaleDevice]) {
        lock.lock()
        defer { lock.unlock() }

        for ts in tailscaleNodes {
            guard let ip = ts.tailscaleIPv4 else { continue }

            if let existingIdx = devices.firstIndex(where: { $0.host == ip }) {
                // Update online status and name
                devices[existingIdx].isOnline = ts.isOnline
                devices[existingIdx].name = ts.displayName
                devices[existingIdx].isTailscaleNode = true
            } else {
                // Add new discovered Tailscale device
                if let newDev = RemoteDevice.fromTailscaleDevice(ts) {
                    devices.append(newDev)
                }
            }
        }

        persist()
    }

    /// Read a current record without racing a discovery/settings update.
    public func device(withID id: UUID) -> RemoteDevice? {
        lock.lock()
        defer { lock.unlock() }
        return devices.first { $0.id == id }
    }

    /// Retrieve the saved password for a device.
    public func getPassword(for device: RemoteDevice) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let current = devices.first(where: { $0.id == device.id }),
              DeviceLibrarySyncCheckpoint.sameConnection(current, device) else { return nil }
        if let credentialSync {
            do {
                switch try credentialSync.password(for: device) {
                case .value(let password): return password
                case .deleted: return nil
                case .missing: break
                }
            } catch {
                reportCredentialFailure(error)
                return nil
            }
        }
        guard syncCheckpoint?.passwordInvalidations.contains(device.id) != true else { return nil }
        if syncCheckpoint != nil, let current = devices.first(where: { $0.id == device.id }),
           !DeviceLibrarySyncCheckpoint.sameConnection(current, device) { return nil }
        return keychain.loadPassword(forKey: device.id.uuidString)
    }

    /// Check if a saved password exists for this device.
    public func hasPassword(for device: RemoteDevice) -> Bool {
        guard let pwd = getPassword(for: device) else { return false }
        return !pwd.isEmpty
    }

    /// Update or save password for an existing device.
    public func updatePassword(_ password: String, for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let current = devices.first(where: { $0.id == device.id }),
              DeviceLibrarySyncCheckpoint.sameConnection(current, device) else { return }
        do { try credentialSync?.stagePassword(password, for: device); credentialFailure = nil }
        catch { reportCredentialFailure(error); return }
        keychain.savePassword(password, forKey: device.id.uuidString)
        syncCheckpoint?.passwordInvalidations.remove(device.id)
        persist()
        if credentialSync != nil { notifyLibraryChange(.local, credentialsChanged: true) }
        AppLogger.shared.info("Updated password in Keychain for device '\(device.name)' (\(device.id.uuidString))", category: "Auth")
    }

    /// Remove password from Keychain for a device.
    public func clearPassword(for device: RemoteDevice) {
        lock.lock(); defer { lock.unlock() }
        guard let current = devices.first(where: { $0.id == device.id }),
              DeviceLibrarySyncCheckpoint.sameConnection(current, device) else { return }
        do { try credentialSync?.stagePasswordDeletion(for: device.id); credentialFailure = nil }
        catch { reportCredentialFailure(error); return }
        if syncCheckpoint == nil {
            do { syncCheckpoint = try DeviceLibrarySyncCheckpoint(storage: .local, devices: devices) }
            catch { reportCredentialFailure(error); return }
        }
        keychain.deletePassword(forKey: device.id.uuidString)
        syncCheckpoint?.passwordInvalidations.insert(device.id)
        persist()
        if credentialSync != nil { notifyLibraryChange(.local, credentialsChanged: true) }
        AppLogger.shared.info("Cleared password in Keychain for device '\(device.name)'", category: "Auth")
    }

    /// Record connection timestamp.
    public func recordConnection(for device: RemoteDevice) {
        lock.lock()
        defer { lock.unlock() }

        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx].lastConnected = Date()
            persist()
        }
    }

    /// Select storage explicitly; this prepares local metadata without contacting iCloud.
    public func selectStorage(_ storage: DeviceLibraryStorage) throws {
        lock.lock(); defer { lock.unlock() }
        try DevicePreferenceStorage.withLock {
            guard syncFailure != .invalidDocument, syncFailure != .unsupportedVersion,
                  syncFailure != .staleLocalReplica else { throw syncFailure! }
            var checkpoint = try syncCheckpoint ?? DeviceLibrarySyncCheckpoint(storage: storage, devices: devices)
            var preferences: DevicePreferenceSnapshot?
            if storage == .iCloud {
                var document = try checkpoint.document()
                try document.recordLocalDevices(devices)
                preferences = try recordPreferences(in: &document, devices: devices)
                checkpoint.documentData = try document.encoded()
            }
            let previous = syncCheckpoint?.storage ?? .local
            checkpoint.storage = storage
            checkpoint.devicesData = try DeviceLibrarySyncCheckpoint.encodeDevices(devices)
            try commitCheckpoint(checkpoint, preferences: preferences)
            if storage != previous { syncGeneration = UUID() }
            if storage == .local { credentialSync?.setCloudAccess(false) }
            syncFailure = nil
            notifyLibraryChange(.storage)
        }
    }

    public func synchronizationReplica() throws -> any DeviceSyncReplica {
        lock.lock(); defer { lock.unlock() }
        guard let checkpoint = syncCheckpoint, checkpoint.storage == .iCloud else {
            throw DeviceSyncFailure.localStorageSelected
        }
        return DeviceLibrarySyncReplica(store: self, replicaID: checkpoint.replicaID, generation: syncGeneration)
    }

    @discardableResult
    func prepareLibrarySynchronization(generation: UUID, expected: [RemoteDevice]? = nil) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try DevicePreferenceStorage.withLock {
            var checkpoint = try requireSyncCheckpoint(generation: generation)
            if let expected, expected != devices { throw DeviceSyncFailure.configurationChanged }
            var document = try checkpoint.document()
            let previous = checkpoint.documentData
            try document.recordLocalDevices(devices)
            let preferences = try recordPreferences(in: &document, devices: devices)
            checkpoint.documentData = try document.encoded()
            checkpoint.devicesData = try DeviceLibrarySyncCheckpoint.encodeDevices(devices)
            try commitCheckpoint(checkpoint, preferences: preferences)
            syncFailure = nil
            return previous != checkpoint.documentData
        }
    }

    func exportLibrarySynchronization(generation: UUID) throws -> Data {
        _ = try prepareLibrarySynchronization(generation: generation)
        lock.lock(); defer { lock.unlock() }
        return try requireSyncCheckpoint(generation: generation).documentData
    }

    @discardableResult
    func receiveLibrarySynchronization(_ documents: [Data], generation: UUID) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try DevicePreferenceStorage.withLock {
            guard documents.count <= 32 else { throw DeviceSyncFailure.tooManyReplicas }
            var checkpoint = try requireSyncCheckpoint(generation: generation)
            var candidate = try checkpoint.document()
            try candidate.recordLocalDevices(devices)
            _ = try recordPreferences(in: &candidate, devices: devices)
            var changed = false
            for data in documents {
                let incoming = try DeviceSyncDocument(data: data, replicaID: checkpoint.replicaID)
                if try candidate.merge(incoming) { changed = true }
            }
            let merged = candidate.devices(retainingLocalState: devices)
            let previous = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
            let next = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
            for (id, old) in previous {
                if next[id].map({ DeviceLibrarySyncCheckpoint.sameConnection(old, $0) }) != true {
                    checkpoint.passwordInvalidations.insert(id)
                    checkpoint.sshInvalidations.insert(id)
                }
            }
            for id in next.keys where previous[id] == nil {
                checkpoint.passwordInvalidations.insert(id)
                checkpoint.sshInvalidations.insert(id)
            }
            checkpoint.documentData = try candidate.encoded()
            checkpoint.devicesData = try DeviceLibrarySyncCheckpoint.encodeDevices(merged)
            let preferences = DevicePreferenceSnapshot(language: candidate.applicationLanguage,
                keyboards: candidate.keyboardConfigurations, scope: preferenceScope.union(merged.map(\.id)))
            try commitCheckpoint(checkpoint, preferences: preferences)
            devices = merged
            syncFailure = nil
            notifyLibraryChange(.remote)
            return changed
        }
    }

    private func requireSyncCheckpoint(generation: UUID) throws -> DeviceLibrarySyncCheckpoint {
        guard generation == syncGeneration else { throw DeviceSyncFailure.configurationChanged }
        guard let checkpoint = syncCheckpoint, checkpoint.storage == .iCloud else {
            throw DeviceSyncFailure.localStorageSelected
        }
        return checkpoint
    }

    /// Call under lock. The checkpoint is the authoritative single local write;
    /// the old list is only a compatibility mirror, so an interrupted mirror cannot lose an import.
    private func commitCheckpoint(_ value: DeviceLibrarySyncCheckpoint, preferences: DevicePreferenceSnapshot? = nil) throws {
        Self.checkpointPersistenceLock.lock(); defer { Self.checkpointPersistenceLock.unlock() }
        guard userDefaults.data(forKey: DeviceLibrarySyncCheckpoint.key) == storedCheckpointData,
              userDefaults.data(forKey: storageKey) == storedLegacyData else {
            throw DeviceSyncDocument.Failure.staleLocalReplica
        }
        var checkpoint = value
        checkpoint.previousLegacyDigest = DeviceLibrarySyncCheckpoint.digest(storedLegacyData)
        let previous = try preferences.map { try DevicePreferenceSnapshot(defaults: userDefaults, scope: $0.scope) }
        checkpoint.preferencesData = try preferences?.encoded()
        checkpoint.previousPreferencesData = try previous?.encoded()
        let data = try checkpoint.encoded()
        userDefaults.set(data, forKey: DeviceLibrarySyncCheckpoint.key)
        userDefaults.set(checkpoint.devicesData, forKey: storageKey)
        if let preferences { try preferences.apply(to: userDefaults) }
        syncCheckpoint = checkpoint
        storedCheckpointData = data
        storedLegacyData = checkpoint.devicesData
        if preferences != previous { DevicePreferenceStorage.notify(userDefaults, origin: .remote) }
    }

    private func authorizeLocalSSHCredentials(for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        syncCheckpoint?.sshInvalidations.remove(id)
    }

    private func stageSSHCredential(_ credentials: SSHSessionCredentials, for device: RemoteDevice) throws {
        lock.lock(); defer { lock.unlock() }
        do { try credentialSync?.stageSSH(credentials, for: device); credentialFailure = nil }
        catch { reportCredentialFailure(error); throw error }
        if credentialSync != nil { notifyLibraryChange(.local, credentialsChanged: true) }
    }

    private func stageSSHDeletion(for id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        do { try credentialSync?.stageDeletion(for: id, sshOnly: true); credentialFailure = nil }
        catch { reportCredentialFailure(error); throw error }
        if credentialSync != nil { notifyLibraryChange(.local, credentialsChanged: true) }
    }

    private func reportCredentialFailure(_ error: Error) {
        credentialFailure = error as? DeviceCredentialSyncStore.Failure ?? .invalidRecord
        notifyLibraryChange(.local, credentialsChanged: true)
    }

    private func persist() {
        DevicePreferenceStorage.withLock { persistWithPreferencesLocked() }
    }

    private func persistWithPreferencesLocked() {
        let previousDocument = syncCheckpoint?.documentData
        do {
            let data = try DeviceLibrarySyncCheckpoint.encodeDevices(devices)
            if var checkpoint = syncCheckpoint {
                var preferences: DevicePreferenceSnapshot?
                checkpoint.devicesData = data
                if checkpoint.storage == .iCloud {
                    do {
                        var document = try checkpoint.document()
                        try document.recordLocalDevices(devices)
                        preferences = try recordPreferences(in: &document, devices: devices)
                        checkpoint.documentData = try document.encoded()
                        syncFailure = nil
                    } catch {
                        // Preserve the local edit even if it cannot yet enter the cloud ledger.
                        syncFailure = error as? DeviceSyncDocument.Failure ?? .invalidDocument
                    }
                }
                try commitCheckpoint(checkpoint, preferences: preferences)
                notifyLibraryChange(.local, metadataChanged: previousDocument != checkpoint.documentData)
                return
            }
            userDefaults.set(data, forKey: storageKey)
            storedLegacyData = data
            notifyLibraryChange(.local)
        } catch {
            syncFailure = error as? DeviceSyncDocument.Failure ?? .invalidDocument
            AppLogger.shared.error("Could not persist the saved-computer library.", category: "General")
        }
    }

    private var preferenceScope: Set<UUID> {
        let previous = syncCheckpoint?.preferencesData.flatMap { try? DevicePreferenceSnapshot(data: $0).scope } ?? []
        return previous.union(devices.map(\.id))
    }

    private func recordPreferences(in document: inout DeviceSyncDocument,
                                   devices: [RemoteDevice]) throws -> DevicePreferenceSnapshot {
        let current = try DevicePreferenceSnapshot(defaults: userDefaults, scope: Set(devices.map(\.id)))
        try document.recordLocalPreferences(language: current.language, keyboards: current.keyboardConfigurations)
        return DevicePreferenceSnapshot(language: document.applicationLanguage, keyboards: document.keyboardConfigurations,
                                        scope: preferenceScope.union(devices.map(\.id)))
    }

    private func capturePreferenceChange() {
        lock.lock(); defer { lock.unlock() }
        guard syncCheckpoint?.storage == .iCloud else { return }
        persist()
    }

    private func notifyLibraryChange(_ origin: DeviceLibraryChangeOrigin, metadataChanged: Bool = false,
                                     credentialsChanged: Bool = false) {
        NotificationCenter.default.post(name: Self.libraryDidChange, object: self,
                                        userInfo: ["origin": origin, "metadataChanged": metadataChanged,
                                                   "credentialsChanged": credentialsChanged])
    }
}

enum DeviceLibraryChangeOrigin: Equatable { case local, remote, storage }
