import Foundation
import CryptoKit

public enum DeviceLibraryStorage: String, Codable, Sendable {
    case local, iCloud
}

/// One local value contains both the visible library and its convergent document.
/// Only documentData is exported. Runtime state and credential invalidations stay local.
struct DeviceLibrarySyncCheckpoint: Codable {
    static let key = "com.aethernative.aetherscreens.devices.sync-checkpoint.v1"
    var version = 1
    var storage: DeviceLibraryStorage
    let replicaID: UUID
    var devicesData: Data
    var documentData: Data
    var previousLegacyDigest: String?
    var preferencesData: Data?
    var previousPreferencesData: Data?
    var passwordInvalidations: Set<UUID> = []
    var sshInvalidations: Set<UUID> = []

    init(storage: DeviceLibraryStorage, devices: [RemoteDevice]) throws {
        self.storage = storage
        replicaID = UUID()
        devicesData = try Self.encodeDevices(devices)
        var document = DeviceSyncDocument(replicaID: replicaID)
        if storage == .iCloud { try document.recordLocalDevices(devices) }
        documentData = try document.encoded()
    }

    init(data: Data) throws {
        do { self = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw DeviceSyncDocument.Failure.invalidDocument }
        guard version == 1 else { throw DeviceSyncDocument.Failure.unsupportedVersion }
        _ = try devices()
        let document = try document()
        if let preferencesData {
            let preferences = try DevicePreferenceSnapshot(data: preferencesData)
            guard storage == .iCloud,
                  preferences.language == document.applicationLanguage,
                  preferences.keyboardConfigurations == document.keyboardConfigurations,
                  Set(document.devices().map(\.id)).isSubset(of: preferences.scope) else {
                throw DeviceSyncDocument.Failure.invalidDocument
            }
        }
        if let previousPreferencesData { _ = try DevicePreferenceSnapshot(data: previousPreferencesData) }
    }

    func devices() throws -> [RemoteDevice] {
        do { return try JSONDecoder().decode([RemoteDevice].self, from: devicesData) }
        catch { throw DeviceSyncDocument.Failure.invalidDocument }
    }

    func document() throws -> DeviceSyncDocument {
        try DeviceSyncDocument(data: documentData, replicaID: replicaID)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func encodeDevices(_ devices: [RemoteDevice]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(devices)
    }

    static func digest(_ data: Data?) -> String? {
        data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
    }

    static func sameConnection(_ a: RemoteDevice, _ b: RemoteDevice) -> Bool {
        a.host == b.host && a.port == b.port && a.authMethod == b.authMethod &&
        a.username == b.username && a.sshConfiguration == b.sshConfiguration
    }
}

/// The adapter reads the current library at every exchange boundary; it never
/// applies a captured full list over edits made while network requests were pending.
final class DeviceLibrarySyncReplica: DeviceSyncReplica, @unchecked Sendable {
    let replicaID: UUID
    private let store: DeviceStore
    private let generation: UUID

    init(store: DeviceStore, replicaID: UUID, generation: UUID) {
        self.store = store; self.replicaID = replicaID; self.generation = generation
    }

    func recordLocalDevices(_ devices: [RemoteDevice]) throws -> Bool {
        try store.prepareLibrarySynchronization(generation: generation, expected: devices)
    }

    func prepareForExchange() throws {
        _ = try store.prepareLibrarySynchronization(generation: generation)
    }

    func receiveDocuments(_ documents: [Data]) throws -> Bool {
        try store.receiveLibrarySynchronization(documents, generation: generation)
    }

    func exportedData() throws -> Data {
        try store.exportLibrarySynchronization(generation: generation)
    }
}
