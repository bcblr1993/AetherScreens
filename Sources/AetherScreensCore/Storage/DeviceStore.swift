import Foundation

/// Manages persistence, discovery merging, and updates for configured remote devices.
public final class DeviceStore: @unchecked Sendable {
    private static let credentialBindingsKey = "com.aethernative.aetherscreens.credential-targets"
    static let syncJournalStorageKey = "com.aethernative.aetherscreens.computer-sync-journal"
    static let pendingSyncJournalStorageKey = "com.aethernative.aetherscreens.pending-computer-sync-journal"
    public static let shared = DeviceStore(legacySources: [.standard])

    public static let storageKey = "com.aethernative.aetherscreens.devices.list"
    /// Key used by builds released under the TailScreens name.
    public static let legacyStorageKey = "com.tailscreens.devices.list"

    private let storageKey = DeviceStore.storageKey
    private let userDefaults: UserDefaults
    private let keychain: KeychainStore
    let sshCredentials: SSHCredentialStore
    private let lock = NSLock()

    public private(set) var devices: [RemoteDevice] = []

    /// - Parameter legacySources: defaults searched for a TailScreens device list when nothing is stored yet.
    public init(userDefaults: UserDefaults = .standard,
                legacySources: [UserDefaults] = [],
                keychain: KeychainStore = .shared,
                sshCredentials: SSHCredentialStore = .shared) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.sshCredentials = sshCredentials
        migrateLegacyDevicesIfNeeded(from: legacySources)
        loadDevices()
    }

    /// Copies the TailScreens device list into the current key once. Legacy data is left untouched.
    private func migrateLegacyDevicesIfNeeded(from sources: [UserDefaults]) {
        guard userDefaults.data(forKey: storageKey) == nil else { return }

        for source in sources {
            guard let data = source.data(forKey: DeviceStore.legacyStorageKey),
                  let decoded = try? JSONDecoder().decode([RemoteDevice].self, from: data) else { continue }
            userDefaults.set(data, forKey: storageKey)
            AppLogger.shared.info("Migrated \(decoded.count) device(s) from TailScreens storage", category: "General")
            return
        }
    }

    /// User labels only; private keys and passphrases never enter preferences.
    static let sshKeyNamesStorageKey = "com.aethernative.aetherscreens.ssh.key-names"

    func sshKeyName(for reference: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return (userDefaults.dictionary(forKey: Self.sshKeyNamesStorageKey) as? [String: String])?[reference.uuidString]
    }

    func setSSHKeyName(_ name: String?, for reference: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var names = userDefaults.dictionary(forKey: Self.sshKeyNamesStorageKey) as? [String: String] ?? [:]
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { names[reference.uuidString] = trimmed }
        else { names.removeValue(forKey: reference.uuidString) }
        if names.isEmpty { userDefaults.removeObject(forKey: Self.sshKeyNamesStorageKey) }
        else { userDefaults.set(names, forKey: Self.sshKeyNamesStorageKey) }
    }

    /// Reload devices from storage.
    public func loadDevices() {
        lock.lock()
        defer { lock.unlock() }

        if let data = userDefaults.data(forKey: storageKey) {
            do {
                let decoded = try JSONDecoder().decode([RemoteDevice].self, from: data)
                self.devices = decoded
            } catch {
                print("[DeviceStore] Failed to decode devices: \(error)")
                self.devices = []
            }
        } else {
            self.devices = []
        }
        do { try recoverPendingSyncLocked() }
        catch { AppLogger.shared.error("Pending computer sync could not be recovered", category: "General") }
    }

    /// Add a new device and optionally save its password to Keychain.
    @discardableResult
    public func addDevice(_ device: RemoteDevice, password: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let previous = devices.first(where: { $0.id == device.id }) {
            captureCredentialBindings(for: [previous])
        }
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
        } else {
            devices.append(device)
        }

        var passwordPersisted = true
        if let pwd = password {
            passwordPersisted = keychain.savePassword(pwd, forKey: device.id.uuidString)
            bindCredential(kind: "vnc", for: device)
        }

        persist()
        return passwordPersisted
    }

    /// Update an existing device.
    @discardableResult
    public func updateDevice(_ device: RemoteDevice, password: String? = nil) -> Bool {
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

        if devices.first(where: { $0.id == device.id })?.ssh != nil {
            do { try sshCredentials.remove(kind: .password, reference: device.id) }
            catch { return false }
        }
        devices.removeAll { $0.id == device.id }
        keychain.deletePassword(forKey: device.id.uuidString)
        DisplayQualityStore(defaults: userDefaults).remove(for: device.id)
        DisconnectActionStore(defaults: userDefaults).remove(for: device.id)
        ThumbnailStore.shared.removeThumbnail(for: device.id)
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

    /// Retrieve the saved password for a device.
    public func getPassword(for device: RemoteDevice) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard credentialMatches(kind: "vnc", device: device) else { return nil }
        return keychain.loadPassword(forKey: device.id.uuidString)
    }

    /// Missing or differently bound passwords use the existing interactive SSH prompt.
    public func getSSHPassword(for device: RemoteDevice, credentials: SSHCredentialStore? = nil) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard credentialMatches(kind: "ssh", device: device) else { return nil }
        return try (credentials ?? sshCredentials).load(kind: .password, reference: device.id)
    }

    func bindSavedSSHPassword(for device: RemoteDevice) {
        lock.lock()
        defer { lock.unlock() }
        bindCredential(kind: "ssh", for: device)
    }

    /// Check if a saved password exists for this device.
    public func hasPassword(for device: RemoteDevice) -> Bool {
        guard let pwd = getPassword(for: device) else { return false }
        return !pwd.isEmpty
    }

    /// Update or save password for an existing device.
    @discardableResult
    public func updatePassword(_ password: String, for device: RemoteDevice) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let persisted = keychain.savePassword(password, forKey: device.id.uuidString)
        bindCredential(kind: "vnc", for: device)
        if persisted { AppLogger.shared.info("Remote password saved to Keychain", category: "Auth") }
        else { AppLogger.shared.error("Remote password could not be saved to Keychain", category: "Auth") }
        return persisted
    }

    /// Remove password from Keychain for a device.
    public func clearPassword(for device: RemoteDevice) {
        keychain.deletePassword(forKey: device.id.uuidString)
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

    /// Explicitly capture local edits and persist the peer identity, clock and tombstones together.
    /// Invalid stored data is reported without replacing it or silently creating a new peer.
    public func captureLocalSyncJournal() throws -> ComputerSyncJournal {
        lock.lock()
        defer { lock.unlock() }
        return try captureLocalSyncJournalLocked(checkpointFile: nil)
    }

    /// Capture the full local library into the same durable commit envelope used
    /// by remote merges. Explicit opt-in; UI mutation wiring remains separate.
    func captureLocalSyncJournal(checkpointURL: URL, accountScope: ComputerSyncAccountScope? = nil) throws -> ComputerSyncJournal {
        lock.lock()
        defer { lock.unlock() }
        return try captureLocalSyncJournalLocked(checkpointFile: ComputerSyncCheckpointFile(url: checkpointURL, accountScope: accountScope))
    }

    private func captureLocalSyncJournalLocked(checkpointFile: ComputerSyncCheckpointFile?) throws -> ComputerSyncJournal {
        try recoverPendingSyncLocked()
        let checkpointBase = try checkpointBaseLocked(checkpointFile)
        let stored = userDefaults.data(forKey: Self.syncJournalStorageKey)
        var journal = try stored.map { try ComputerSyncJournal(restoring: $0) } ?? ComputerSyncJournal()
        let changed = try journal.captureLocalComputers(devices)
        let encoded = try journal.encoded()
        if let checkpointFile {
            let checkpoint = try syncCheckpointLocked(journal)
            try checkpointFile.save(checkpoint, replacing: checkpointBase)
            userDefaults.set(checkpoint.credentialBindings, forKey: Self.credentialBindingsKey)
        }
        if stored == nil || changed {
            userDefaults.set(encoded, forKey: Self.syncJournalStorageKey)
        }
        return journal
    }

    /// Capture local changes before merging remote data. Cloud transport remains separate.
    /// Pending state is recoverable when present; UserDefaults is not a durable transaction log.
    @discardableResult
    public func mergeSyncSnapshot(_ data: Data) throws -> ComputerSyncJournal.MergeResult {
        lock.lock()
        defer { lock.unlock() }
        return try mergeSyncSnapshotLocked(data, checkpointFile: nil)
    }

    /// Explicit durable commit boundary for the future account-scoped coordinator.
    /// The caller owns the directory and must recover a retained checkpoint before
    /// allowing local edits after restart. This does not enable cloud synchronization.
    func mergeSyncSnapshot(_ data: Data, checkpointURL: URL, accountScope: ComputerSyncAccountScope? = nil) throws -> ComputerSyncJournal.MergeResult {
        lock.lock()
        defer { lock.unlock() }
        return try mergeSyncSnapshotLocked(data, checkpointFile: ComputerSyncCheckpointFile(url: checkpointURL, accountScope: accountScope))
    }

    private func mergeSyncSnapshotLocked(_ data: Data, checkpointFile: ComputerSyncCheckpointFile?) throws -> ComputerSyncJournal.MergeResult {
        try recoverPendingSyncLocked()
        let checkpointBase = try checkpointBaseLocked(checkpointFile)
        let stored = userDefaults.data(forKey: Self.syncJournalStorageKey)
        var journal = try stored.map { try ComputerSyncJournal(restoring: $0) } ?? ComputerSyncJournal()
        try journal.captureLocalComputers(devices)
        let result = try journal.merge(data)
        let encoded = try journal.encoded()
        let checkpoint = try syncCheckpointLocked(journal)
        let devicesData = try JSONEncoder().encode(checkpoint.devices)
        // A pre-rename failure leaves both the old file and all preferences intact.
        // A post-rename durability error retains the new file for explicit recovery.
        try checkpointFile?.save(checkpoint, replacing: checkpointBase)
        userDefaults.set(encoded, forKey: Self.pendingSyncJournalStorageKey)
        _ = publishSyncCheckpointLocked(checkpoint, devicesData: devicesData)
        userDefaults.set(encoded, forKey: Self.syncJournalStorageKey)
        userDefaults.removeObject(forKey: Self.pendingSyncJournalStorageKey)
        return result
    }

    /// Replay every part of the retained local commit, never a partial preference
    /// mirror. Keep the file; deleting it would discard the durable source of truth.
    @discardableResult
    func recoverSyncCheckpoint(at url: URL, accountScope: ComputerSyncAccountScope? = nil) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let checkpoint = try ComputerSyncCheckpointFile(url: url, accountScope: accountScope).load() else { return false }
        let data = try JSONEncoder().encode(checkpoint.devices)
        userDefaults.set(checkpoint.credentialBindings, forKey: Self.credentialBindingsKey)
        userDefaults.set(data, forKey: storageKey)
        userDefaults.set(checkpoint.journal, forKey: Self.syncJournalStorageKey)
        userDefaults.removeObject(forKey: Self.pendingSyncJournalStorageKey)
        devices = checkpoint.devices
        return true
    }

    private func recoverPendingSyncLocked() throws {
        guard let pending = userDefaults.data(forKey: Self.pendingSyncJournalStorageKey) else { return }
        let journal = try ComputerSyncJournal(restoring: pending)
        _ = try applySyncJournalLocked(journal)
        userDefaults.set(pending, forKey: Self.syncJournalStorageKey)
        userDefaults.removeObject(forKey: Self.pendingSyncJournalStorageKey)
    }

    /// Applies an already merged, validated journal explicitly; this does not enable cloud sync.
    /// Remote removals affect configuration only. Credentials and open sessions remain local.
    @discardableResult
    public func applySyncJournal(_ journal: ComputerSyncJournal) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return try applySyncJournalLocked(journal)
    }

    private func applySyncJournalLocked(_ journal: ComputerSyncJournal) throws -> Bool {
        let checkpoint = try syncCheckpointLocked(journal)
        let data = try JSONEncoder().encode(checkpoint.devices)
        return publishSyncCheckpointLocked(checkpoint, devicesData: data)
    }

    private func publishSyncCheckpointLocked(_ checkpoint: ComputerSyncCheckpoint, devicesData: Data) -> Bool {
        guard checkpoint.devices != devices else { return false }
        userDefaults.set(checkpoint.credentialBindings, forKey: Self.credentialBindingsKey)
        userDefaults.set(devicesData, forKey: storageKey)
        devices = checkpoint.devices
        return true
    }

    /// Build the complete commit candidate before changing any stored key.
    private func syncCheckpointLocked(_ journal: ComputerSyncJournal) throws -> ComputerSyncCheckpoint {
        _ = try journal.encoded()
        var candidate = devices
        for record in journal.records.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let metadata = record.metadata else {
                candidate.removeAll { $0.id == record.id }
                continue
            }
            let index = candidate.firstIndex { $0.id == metadata.id }
            let local = index.map { candidate[$0] }
            let device = RemoteDevice(
                id: metadata.id, name: metadata.name, host: metadata.host, port: metadata.port,
                deviceType: metadata.deviceType, authMethod: metadata.authMethod,
                username: metadata.username, isOnline: local?.isOnline ?? false,
                lastConnected: local?.lastConnected, isTailscaleNode: metadata.isTailscaleNode,
                macAddress: metadata.macAddress, ssh: metadata.ssh)
            if let index { candidate[index] = device }
            else { candidate.append(device) }
        }
        return try ComputerSyncCheckpoint(journal: journal, devices: candidate,
            credentialBindings: syncCredentialBindingsLocked(for: candidate))
    }

    private func syncCredentialBindingsLocked(for candidate: [RemoteDevice]) -> [String: String] {
        var bindings = userDefaults.dictionary(forKey: Self.credentialBindingsKey) as? [String: String] ?? [:]
        for device in devices {
            let token = targetToken(for: device)
            for kind in ["vnc", "ssh"] {
                let key = "\(kind):\(device.id.uuidString)"
                if bindings[key] == nil { bindings[key] = token }
            }
        }
        let localIDs = Set(devices.map(\.id))
        for device in candidate where !localIDs.contains(device.id) {
            for kind in ["vnc", "ssh"] {
                let key = "\(kind):\(device.id.uuidString)"
                // A new remote ID must not inherit an orphaned legacy password.
                if bindings[key] == nil { bindings[key] = "unbound" }
            }
        }
        return bindings
    }

    /// Full local configuration transaction for the account coordinator. No vault
    /// writes or credential deletion here: secret operations require their own
    /// UI/vault policy. The caller supplies the full unfiltered library.
    func commitLocalSyncConfiguration(_ candidate: [RemoteDevice], checkpointURL: URL, accountScope: ComputerSyncAccountScope? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        try recoverPendingSyncLocked()
        let checkpointFile = ComputerSyncCheckpointFile(url: checkpointURL, accountScope: accountScope)
        let checkpointBase = try checkpointBaseLocked(checkpointFile)
        let stored = userDefaults.data(forKey: Self.syncJournalStorageKey)
        var journal = try stored.map { try ComputerSyncJournal(restoring: $0) } ?? ComputerSyncJournal()
        // Enroll the previous complete list before detecting removals, including
        // the first local transaction before a journal has ever been created.
        try journal.captureLocalComputers(devices)
        try journal.captureLocalComputers(candidate)
        let checkpoint = try ComputerSyncCheckpoint(journal: journal, devices: candidate,
            credentialBindings: syncCredentialBindingsLocked(for: candidate))
        let data = try JSONEncoder().encode(candidate)
        try checkpointFile.save(checkpoint, replacing: checkpointBase)
        userDefaults.set(checkpoint.credentialBindings, forKey: Self.credentialBindingsKey)
        userDefaults.set(data, forKey: storageKey)
        userDefaults.set(checkpoint.journal, forKey: Self.syncJournalStorageKey)
        userDefaults.removeObject(forKey: Self.pendingSyncJournalStorageKey)
        devices = candidate
    }

    private func checkpointBaseLocked(_ file: ComputerSyncCheckpointFile?) throws -> ComputerSyncCheckpoint? {
        guard let file, let checkpoint = try file.load() else { return nil }
        // A newer file must be explicitly recovered before preparing edits from
        // an older preference mirror. Never overwrite it with an older journal.
        guard userDefaults.data(forKey: Self.syncJournalStorageKey) == checkpoint.journal else {
            throw ComputerSyncCheckpointFile.Failure.conflict
        }
        return checkpoint
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(devices)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            print("[DeviceStore] Failed to persist devices: \(error)")
        }
    }

    private func targetToken(for device: RemoteDevice) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let target = ComputerCredentialTarget(host: device.host, port: device.port,
            authMethod: device.authMethod, username: device.username, ssh: device.ssh)
        // This fixed Codable whitelist contains no secrets and cannot fail encoding.
        return (try? encoder.encode(target))?.base64EncodedString() ?? "invalid"
    }

    private func credentialMatches(kind: String, device: RemoteDevice) -> Bool {
        let bindings = userDefaults.dictionary(forKey: Self.credentialBindingsKey) as? [String: String] ?? [:]
        if let token = bindings["\(kind):\(device.id.uuidString)"] {
            return token == targetToken(for: device)
        }
        // Legacy entries are usable only for their currently persisted target.
        // Preserve explicitly injected SSH vaults for temporary sessions. Synced
        // additions always have an explicit unbound marker and cannot take this path.
        guard let saved = devices.first(where: { $0.id == device.id }) else { return kind == "ssh" }
        return targetToken(for: saved) == targetToken(for: device)
    }

    private func captureCredentialBindings(for devices: [RemoteDevice]) {
        var bindings = userDefaults.dictionary(forKey: Self.credentialBindingsKey) as? [String: String] ?? [:]
        var changed = false
        for device in devices {
            let token = targetToken(for: device)
            for kind in ["vnc", "ssh"] {
                let key = "\(kind):\(device.id.uuidString)"
                if bindings[key] == nil { bindings[key] = token; changed = true }
            }
        }
        if changed { userDefaults.set(bindings, forKey: Self.credentialBindingsKey) }
    }

    private func bindCredential(kind: String, for device: RemoteDevice) {
        var bindings = userDefaults.dictionary(forKey: Self.credentialBindingsKey) as? [String: String] ?? [:]
        bindings["\(kind):\(device.id.uuidString)"] = targetToken(for: device)
        userDefaults.set(bindings, forKey: Self.credentialBindingsKey)
    }
}
