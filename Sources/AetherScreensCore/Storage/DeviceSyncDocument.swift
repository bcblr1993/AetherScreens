import Foundation
import AetherScreensSSH

/// A convergent, credential-free saved-connection document. It never accesses iCloud or Keychain.
/// Each preference is a separate register; connection identity changes as one atomic value.
public struct DeviceSyncDocument: Equatable, Sendable {
    public enum Failure: Error, Equatable {
        case unsupportedVersion, invalidDocument, conflictingRevision, quotaExceeded, clockExhausted
        case deletedIdentifier
        case staleLocalReplica
    }

    // Leave space within Apple's key-value quota for settings and transport metadata.
    public static let maximumEncodedBytes = 900 * 1024
    private static let maximumRecords = 1024

    private struct Revision: Codable, Equatable, Comparable, Sendable {
        let counter: UInt64
        let replica: UUID

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.counter == rhs.counter
                ? lhs.replica.uuidString < rhs.replica.uuidString
                : lhs.counter < rhs.counter
        }
    }

    private struct Register<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        var value: Value
        var revision: Revision

        mutating func update(_ value: Value, at revision: Revision) {
            guard self.value != value else { return }
            self = .init(value: value, revision: revision)
        }

        mutating func merge(_ incoming: Self) throws {
            guard revision != incoming.revision else {
                guard value == incoming.value else { throw Failure.conflictingRevision }
                return
            }
            if revision < incoming.revision { self = incoming }
        }
    }

    private struct Connection: Codable, Equatable, Sendable {
        var host: String
        var port: UInt16
        var authentication: RemoteDevice.AuthMethod
        var username: String?
        var ssh: SSHConfiguration?

        init(_ device: RemoteDevice) {
            host = device.host; port = device.port; authentication = device.authMethod
            username = device.username; ssh = device.sshConfiguration
        }
    }

    private struct DisplayPreference: Codable, Equatable, Sendable {
        var identifier: UInt32?
        var connection: Connection
    }

    /// Order and visibility form one layout; other controls merge independently.
    private struct ToolbarPreferences: Codable, Equatable, Sendable {
        static func baseline() -> Self {
            // A common baseline never competes with a real customization (the
            // computer has already consumed revision 1 before its first edit).
            let revision = Revision(counter: 1, replica: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
            var configuration = KeyboardToolbarConfiguration()
            configuration.items = []
            var result = Self(configuration, at: revision)
            result.enabled.value = false
            return result
        }
        var enabled: Register<Bool>
        var size: Register<KeyboardToolbarConfiguration.Size>
        var position: Register<KeyboardToolbarConfiguration.Position>
        var layout: Register<[KeyboardToolbarConfiguration.Item]>
        var hardwareConfigured: Register<Bool>
        var swapCommandControl: Register<Bool?>
        var commandBackslashSwitchesApps: Register<Bool?>
        var repeatEnabled: Register<Bool>
        var repeatDelay: Register<Double>
        var repeatInterval: Register<Double>
        var pencilDoubleTap: Register<String?>
        var pencilSqueeze: Register<String?>

        init(_ configuration: KeyboardToolbarConfiguration, at revision: Revision) {
            let hardware = configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
            enabled = .init(value: true, revision: revision)
            size = .init(value: configuration.size, revision: revision)
            position = .init(value: configuration.position, revision: revision)
            layout = .init(value: configuration.items, revision: revision)
            hardwareConfigured = .init(value: configuration.hardwareKeyboard != nil, revision: revision)
            swapCommandControl = .init(value: hardware.swapCommandControl, revision: revision)
            commandBackslashSwitchesApps = .init(value: hardware.commandBackslashSwitchesApps, revision: revision)
            repeatEnabled = .init(value: hardware.repeatEnabled, revision: revision)
            repeatDelay = .init(value: hardware.repeatDelay, revision: revision)
            repeatInterval = .init(value: hardware.repeatInterval, revision: revision)
            pencilDoubleTap = .init(value: configuration.pencilDoubleTapAction?.rawValue, revision: revision)
            pencilSqueeze = .init(value: configuration.pencilSqueezeAction?.rawValue, revision: revision)
        }

        var revisions: [Revision] {
            [enabled.revision, size.revision, position.revision, layout.revision,
             hardwareConfigured.revision, swapCommandControl.revision,
             commandBackslashSwitchesApps.revision, repeatEnabled.revision,
             repeatDelay.revision, repeatInterval.revision, pencilDoubleTap.revision, pencilSqueeze.revision]
        }

        func configuration() -> KeyboardToolbarConfiguration? {
            guard enabled.value else { return nil }
            var result = KeyboardToolbarConfiguration()
            result.size = size.value; result.position = position.value; result.items = layout.value
            if hardwareConfigured.value {
                var hardware = HardwareKeyboardConfiguration()
                hardware.swapCommandControl = swapCommandControl.value
                hardware.commandBackslashSwitchesApps = commandBackslashSwitchesApps.value
                hardware.repeatEnabled = repeatEnabled.value
                hardware.repeatDelay = repeatDelay.value; hardware.repeatInterval = repeatInterval.value
                result.hardwareKeyboard = hardware
            }
            result.pencilDoubleTapAction = pencilDoubleTap.value.flatMap(PencilGestureAction.init(rawValue:))
            result.pencilSqueezeAction = pencilSqueeze.value.flatMap(PencilGestureAction.init(rawValue:))
            return result
        }

        func validate() throws {
            guard layout.value.count <= 128, repeatDelay.value.isFinite, repeatInterval.value.isFinite,
                  (0.2...2).contains(repeatDelay.value), (0.03...0.5).contains(repeatInterval.value),
                  pencilDoubleTap.value == nil || PencilGestureAction(rawValue: pencilDoubleTap.value!) != nil,
                  pencilSqueeze.value == nil || PencilGestureAction(rawValue: pencilSqueeze.value!) != nil else {
                throw Failure.invalidDocument
            }
            var ids = Set<UUID>(), actions = Set<KeyboardToolbarConfiguration.Action>()
            for item in layout.value {
                guard ids.insert(item.id).inserted,
                      item.action == .spacer || actions.insert(item.action).inserted else { throw Failure.invalidDocument }
            }
        }

        mutating func update(_ configuration: KeyboardToolbarConfiguration?, at revision: Revision) {
            enabled.update(configuration != nil, at: revision)
            guard let configuration else { return }
            let hardware = configuration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
            size.update(configuration.size, at: revision); position.update(configuration.position, at: revision)
            layout.update(configuration.items, at: revision)
            hardwareConfigured.update(configuration.hardwareKeyboard != nil, at: revision)
            swapCommandControl.update(hardware.swapCommandControl, at: revision)
            commandBackslashSwitchesApps.update(hardware.commandBackslashSwitchesApps, at: revision)
            repeatEnabled.update(hardware.repeatEnabled, at: revision)
            repeatDelay.update(hardware.repeatDelay, at: revision); repeatInterval.update(hardware.repeatInterval, at: revision)
            pencilDoubleTap.update(configuration.pencilDoubleTapAction?.rawValue, at: revision)
            pencilSqueeze.update(configuration.pencilSqueezeAction?.rawValue, at: revision)
        }

        mutating func merge(_ other: Self) throws {
            try enabled.merge(other.enabled); try size.merge(other.size); try position.merge(other.position)
            try layout.merge(other.layout); try hardwareConfigured.merge(other.hardwareConfigured)
            try swapCommandControl.merge(other.swapCommandControl)
            try commandBackslashSwitchesApps.merge(other.commandBackslashSwitchesApps)
            try repeatEnabled.merge(other.repeatEnabled); try repeatDelay.merge(other.repeatDelay)
            try repeatInterval.merge(other.repeatInterval); try pencilDoubleTap.merge(other.pencilDoubleTap)
            try pencilSqueeze.merge(other.pencilSqueeze)
        }
    }

    private struct Record: Codable, Equatable, Sendable {
        let id: UUID
        var created: Revision
        var name: Register<String>
        var connection: Register<Connection>
        var type: Register<RemoteDevice.DeviceType>
        var tailscale: Register<Bool>
        var macAddress: Register<String?>
        var disconnectAction: Register<RemoteDisconnectAction?>
        var cursorSpeed: Register<Double?>
        var sharedClipboard: Register<Bool?>
        var imageCompression: Register<RemoteImageCompressionPolicy?>?
        var display: Register<DisplayPreference>
        var toolbar: ToolbarPreferences?

        init(_ device: RemoteDevice, at revision: Revision) {
            id = device.id; created = revision
            name = .init(value: device.name, revision: revision)
            connection = .init(value: Connection(device), revision: revision)
            type = .init(value: device.deviceType, revision: revision)
            tailscale = .init(value: device.isTailscaleNode, revision: revision)
            macAddress = .init(value: device.macAddress, revision: revision)
            disconnectAction = .init(value: device.disconnectAction, revision: revision)
            cursorSpeed = .init(value: device.cursorSpeed, revision: revision)
            sharedClipboard = .init(value: device.sharedClipboard, revision: revision)
            if let policy = device.imageCompression {
                imageCompression = .init(value: policy, revision: revision)
            }
            display = .init(value: .init(identifier: device.preferredDisplayID,
                                       connection: Connection(device)), revision: revision)
        }

        var revisions: [Revision] {
            [created, name.revision, connection.revision, type.revision, tailscale.revision,
             macAddress.revision, disconnectAction.revision, cursorSpeed.revision,
             sharedClipboard.revision, display.revision] + (toolbar?.revisions ?? []) +
                (imageCompression.map { [$0.revision] } ?? [])
        }

        func materialize(retaining local: RemoteDevice?) -> RemoteDevice {
            let endpoint = connection.value
            let local = local.flatMap { Connection($0) == endpoint ? $0 : nil }
            // A screen ID is only meaningful for the endpoint/account that supplied it.
            let screenID = display.value.connection == endpoint ? display.value.identifier : nil
            return RemoteDevice(id: id, name: name.value, host: endpoint.host, port: endpoint.port,
                                deviceType: type.value, authMethod: endpoint.authentication,
                                username: endpoint.username, isOnline: local?.isOnline ?? false,
                                lastConnected: local?.lastConnected, isTailscaleNode: tailscale.value,
                                macAddress: macAddress.value, disconnectAction: disconnectAction.value,
                                cursorSpeed: cursorSpeed.value, sharedClipboard: sharedClipboard.value,
                                imageCompression: imageCompression?.value,
                                preferredDisplayID: screenID, sshConfiguration: endpoint.ssh)
        }

        mutating func update(_ device: RemoteDevice, at revision: Revision) {
            name.update(device.name, at: revision)
            connection.update(Connection(device), at: revision)
            type.update(device.deviceType, at: revision)
            tailscale.update(device.isTailscaleNode, at: revision)
            macAddress.update(device.macAddress, at: revision)
            disconnectAction.update(device.disconnectAction, at: revision)
            cursorSpeed.update(device.cursorSpeed, at: revision)
            sharedClipboard.update(device.sharedClipboard, at: revision)
            if imageCompression != nil { imageCompression!.update(device.imageCompression, at: revision) }
            else if let policy = device.imageCompression {
                imageCompression = .init(value: policy, revision: revision)
            }
            display.update(.init(identifier: device.preferredDisplayID,
                                 connection: Connection(device)), at: revision)
        }

        mutating func merge(_ other: Self) throws {
            created = min(created, other.created)
            try name.merge(other.name); try connection.merge(other.connection)
            try type.merge(other.type); try tailscale.merge(other.tailscale)
            try macAddress.merge(other.macAddress); try disconnectAction.merge(other.disconnectAction)
            try cursorSpeed.merge(other.cursorSpeed); try sharedClipboard.merge(other.sharedClipboard)
            if let incoming = other.imageCompression {
                if imageCompression != nil { try imageCompression!.merge(incoming) }
                else { imageCompression = incoming }
            }
            try display.merge(other.display)
            if let incoming = other.toolbar {
                if toolbar != nil { try toolbar!.merge(incoming) }
                else { toolbar = incoming }
            }
        }
    }

    private struct Tombstone: Codable, Equatable, Sendable {
        let id: UUID
        let revision: Revision
    }

    private struct Envelope: Codable {
        let version: Int
        let observedClock: UInt64
        let records: [Record]
        let deletions: [Tombstone]
        let applicationLanguage: Register<AppLanguage?>?
    }

    public let replicaID: UUID
    private var clock: UInt64 = 0
    private var records: [UUID: Record] = [:]
    private var deletions: [UUID: Revision] = [:]
    /// Identifiers only; credential cleanup never needs the exported secret data.
    var deletedIdentifiers: Set<UUID> { Set(deletions.keys) }
    private var language: Register<AppLanguage?>?

    public init(replicaID: UUID) { self.replicaID = replicaID }

    /// Restore or receive a document without adopting the other machine's identity.
    public init(data: Data, replicaID: UUID) throws {
        self.init(replicaID: replicaID)
        guard data.count <= Self.maximumEncodedBytes else { throw Failure.quotaExceeded }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw Failure.invalidDocument }
        guard envelope.version == 1 || envelope.version == 2 else { throw Failure.unsupportedVersion }
        guard envelope.version == 2 || (envelope.applicationLanguage == nil && envelope.records.allSatisfy { $0.toolbar == nil }) else {
            throw Failure.invalidDocument
        }
        guard envelope.records.count + envelope.deletions.count <= Self.maximumRecords else {
            throw Failure.quotaExceeded
        }
        for record in envelope.records {
            guard records[record.id] == nil, record.revisions.allSatisfy({ $0.counter > 0 }) else {
                throw Failure.invalidDocument
            }
            let device = record.materialize(retaining: nil)
            try record.toolbar?.validate()
            guard device.cursorSpeed == nil ||
                    (device.cursorSpeed!.isFinite && (0.25...2).contains(device.cursorSpeed!)) else {
                throw Failure.invalidDocument
            }
            records[record.id] = record
            clock = max(clock, record.revisions.map(\.counter).max() ?? 0)
        }
        for deletion in envelope.deletions {
            guard deletion.revision.counter > 0, deletions[deletion.id] == nil,
                  records[deletion.id] == nil else { throw Failure.invalidDocument }
            deletions[deletion.id] = deletion.revision
            clock = max(clock, deletion.revision.counter)
        }
        if let language = envelope.applicationLanguage {
            guard language.revision.counter > 0 else { throw Failure.invalidDocument }
            self.language = language; clock = max(clock, language.revision.counter)
        }
        guard envelope.observedClock >= clock else { throw Failure.invalidDocument }
        clock = envelope.observedClock
    }

    /// Stable bytes allow transports to avoid rewriting unchanged metadata.
    public func encoded() throws -> Data {
        guard records.count + deletions.count <= Self.maximumRecords else { throw Failure.quotaExceeded }
        let version = language != nil || records.values.contains(where: { $0.toolbar != nil }) ? 2 : 1
        let envelope = Envelope(version: version, observedClock: clock,
            records: records.values.sorted { $0.id.uuidString < $1.id.uuidString },
            deletions: deletions.map { Tombstone(id: $0.key, revision: $0.value) }
                .sorted { $0.id.uuidString < $1.id.uuidString }, applicationLanguage: language)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEncodedBytes else { throw Failure.quotaExceeded }
        return data
    }

    /// Online status and connection history belong to each machine and are never synchronized.
    public func devices(retainingLocalState localDevices: [RemoteDevice] = []) -> [RemoteDevice] {
        var local: [UUID: RemoteDevice] = [:]
        for device in localDevices { local[device.id] = device }
        return records.values.sorted {
            $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created
        }.map { $0.materialize(retaining: local[$0.id]) }
    }

    public var applicationLanguage: AppLanguage? { language?.value }

    public var keyboardConfigurations: [UUID: KeyboardToolbarConfiguration] {
        records.reduce(into: [:]) { result, entry in
            if let configuration = entry.value.toolbar?.configuration() { result[entry.key] = configuration }
        }
    }

    /// Capture actual saved overrides, never randomly generated factory toolbar defaults.
    /// Missing overrides clear prior customization. Temporary/deleted computers cannot enter this document.
    @discardableResult
    public mutating func recordLocalPreferences(language: AppLanguage?,
                                               keyboards: [UUID: KeyboardToolbarConfiguration]) throws -> Bool {
        guard keyboards.keys.allSatisfy({ records[$0] != nil }) else { throw Failure.invalidDocument }
        var candidate = self
        if candidate.language?.value != language {
            let revision = try candidate.nextRevision()
            candidate.language = .init(value: language, revision: revision)
        }
        for id in candidate.records.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            var record = candidate.records[id]!
            let configuration = keyboards[id]
            guard record.toolbar?.configuration() != configuration else { continue }
            let revision = try candidate.nextRevision()
            if record.toolbar != nil { record.toolbar!.update(configuration, at: revision) }
            else if let configuration {
                var preferences = ToolbarPreferences.baseline()
                preferences.update(configuration, at: revision)
                record.toolbar = preferences
            }
            try record.toolbar?.validate()
            candidate.records[id] = record
        }
        _ = try candidate.encoded()
        let changed = candidate.language != self.language || candidate.records != records
        if changed { self = candidate }
        return changed
    }

    /// Capture a complete LOCAL saved list, before applying incoming documents.
    /// Absence records a durable deletion. Re-adding a removed target requires a new UUID.
    @discardableResult
    public mutating func recordLocalDevices(_ devices: [RemoteDevice]) throws -> Bool {
        var candidate = self
        var incoming: [UUID: RemoteDevice] = [:]
        for device in devices {
            guard incoming[device.id] == nil else { throw Failure.invalidDocument }
            guard candidate.deletions[device.id] == nil else { throw Failure.deletedIdentifier }
            guard device.cursorSpeed == nil ||
                    (device.cursorSpeed!.isFinite && (0.25...2).contains(device.cursorSpeed!)) else {
                throw Failure.invalidDocument
            }
            incoming[device.id] = device
        }
        for id in candidate.records.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard incoming[id] == nil else { continue }
            candidate.deletions[id] = try candidate.nextRevision()
            candidate.records.removeValue(forKey: id)
        }
        for device in devices {
            if var record = candidate.records[device.id] {
                let previous = record.materialize(retaining: device)
                guard previous != device else { continue }
                let revision = try candidate.nextRevision()
                record.update(device, at: revision)
                candidate.records[device.id] = record
            } else {
                candidate.records[device.id] = Record(device, at: try candidate.nextRevision())
            }
        }
        _ = try candidate.encoded()
        let changed = candidate.records != records || candidate.deletions != deletions
        if changed { self = candidate }
        return changed
    }

    /// Atomic, idempotent merge. Deletion wins even against an offline concurrent edit.
    /// Tombstones are retained: removing them would resurrect data on a long-offline device.
    @discardableResult
    public mutating func merge(_ other: Self) throws -> Bool {
        var candidate = self
        candidate.clock = max(clock, other.clock)
        if let incoming = other.language {
            if candidate.language != nil { try candidate.language!.merge(incoming) }
            else { candidate.language = incoming }
        }
        for (id, revision) in other.deletions {
            candidate.deletions[id] = max(candidate.deletions[id] ?? revision, revision)
            candidate.records.removeValue(forKey: id)
        }
        for (id, incoming) in other.records where candidate.deletions[id] == nil {
            if var existing = candidate.records[id] {
                try existing.merge(incoming)
                candidate.records[id] = existing
            } else {
                candidate.records[id] = incoming
            }
        }
        _ = try candidate.encoded()
        let changed = candidate.records != records || candidate.deletions != deletions || candidate.language != language
        self = candidate
        return changed
    }

    private mutating func nextRevision() throws -> Revision {
        guard clock < UInt64.max else { throw Failure.clockExhausted }
        clock += 1
        return .init(counter: clock, replica: replicaID)
    }
}
