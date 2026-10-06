import Foundation
import CloudKit
import CryptoKit

/// Encrypted metadata in the user's private CloudKit database. Construction does not perform I/O;
/// the app must supply a registered, correctly provisioned container before enabling this transport.
public actor CloudKitDeviceSyncTransport: DeviceSyncTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
    }

    public func accountIdentifier() async throws -> String {
        let owner = try await accountOwner()
        return accountHash(owner)
    }

    public func fetchDocuments(replicaID: UUID, account: String) async throws -> DeviceSyncRemoteSnapshot {
        let zoneID = try await requireAccount(account)
        do { _ = try await database.recordZone(for: zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }
        _ = try await requireAccount(account)
        var token: CKServerChangeToken?
        var records: [CKRecord.ID: CKRecord] = [:]
        var pages = 0
        repeat {
            try Task.checkCancellation()
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token,
                                                            desiredKeys: [DeviceCloudRecordCodec.payloadKey],
                                                            resultsLimit: 32)
            _ = try await requireAccount(account)
            for (id, modification) in page.modificationResultsByID {
                let record = try modification.get().record
                guard record.recordType == DeviceCloudRecordCodec.recordType else {
                    throw DeviceSyncFailure.invalidRemoteData
                }
                records[id] = record
            }
            for deletion in page.deletions { records.removeValue(forKey: deletion.recordID) }
            guard records.count <= 32 else { throw DeviceSyncFailure.tooManyReplicas }
            pages += 1
            guard pages <= 128 else { throw DeviceSyncFailure.invalidRemoteData }
            token = page.changeToken
            if !page.moreComing { break }
        } while true
        var documents: [Data] = []
        var localVersion: Data?
        let localID = DeviceCloudRecordCodec.recordID(replicaID: replicaID, zoneID: zoneID)
        for record in records.values.sorted(by: { $0.recordID.recordName < $1.recordID.recordName }) {
            documents.append(try DeviceCloudRecordCodec.document(from: record, zoneID: zoneID))
            if record.recordID == localID { localVersion = try DeviceCloudRecordCodec.version(of: record) }
        }
        return .init(documents: documents, localReplicaVersion: localVersion)
    }

    public func publish(_ document: Data, replicaID: UUID, account: String, version: Data?) async throws {
        try Task.checkCancellation()
        let zoneID = try await requireAccount(account)
        let record = try DeviceCloudRecordCodec.record(document: document, replicaID: replicaID,
                                                       zoneID: zoneID, version: version)
        do {
            let results = try await database.modifyRecords(saving: [record], deleting: [],
                                                           savePolicy: .ifServerRecordUnchanged, atomically: true)
            guard let saved = results.saveResults[record.recordID] else {
                throw DeviceSyncFailure.invalidRemoteData
            }
            _ = try saved.get()
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw DeviceSyncFailure.remoteConflict
        }
        _ = try await requireAccount(account)
    }

    private func accountOwner() async throws -> String {
        try Task.checkCancellation()
        guard try await container.accountStatus() == .available else {
            throw DeviceSyncFailure.accountUnavailable
        }
        return try await container.userRecordID().recordName
    }

    private func accountHash(_ owner: String) -> String {
        SHA256.hash(data: Data((containerIdentifier + "\0" + owner).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func requireAccount(_ expected: String) async throws -> CKRecordZone.ID {
        let owner = try await accountOwner()
        guard accountHash(owner) == expected else { throw DeviceSyncFailure.accountChanged }
        // Use the concrete account owner, never a default-owner alias that could rebind mid-flight.
        return .init(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: owner)
    }
}

/// Pure record serialization is independently testable without creating a CKContainer or account.
enum DeviceCloudRecordCodec {
    static let recordType = "SavedConnectionReplicaV1"
    static let payloadKey = "encryptedDocumentV1"
    static let zoneName = "AetherScreensSavedConnectionsV1"

    static func recordID(replicaID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        .init(recordName: "replica-" + replicaID.uuidString, zoneID: zoneID)
    }

    static func record(document: Data, replicaID: UUID, zoneID: CKRecordZone.ID, version: Data?) throws -> CKRecord {
        let decoded = try DeviceSyncDocument(data: document, replicaID: replicaID)
        let canonical = try decoded.encoded()
        guard canonical == document else { throw DeviceSyncFailure.invalidRemoteData }
        let identifier = recordID(replicaID: replicaID, zoneID: zoneID)
        let record: CKRecord
        if let version {
            guard version.count <= 64 * 1024 else { throw DeviceSyncFailure.invalidRemoteData }
            let decoder = try NSKeyedUnarchiver(forReadingFrom: version)
            decoder.requiresSecureCoding = true
            decoder.decodingFailurePolicy = .setErrorAndReturn
            defer { decoder.finishDecoding() }
            guard let restored = CKRecord(coder: decoder), decoder.error == nil, restored.recordID == identifier,
                  restored.recordType == recordType else { throw DeviceSyncFailure.invalidRemoteData }
            record = restored
        } else {
            record = CKRecord(recordType: recordType, recordID: identifier)
        }
        record.encryptedValues[payloadKey] = canonical as NSData
        return record
    }

    static func document(from record: CKRecord, zoneID: CKRecordZone.ID) throws -> Data {
        guard record.recordType == recordType, record.recordID.zoneID == zoneID,
              record.recordID.recordName.hasPrefix("replica-"),
              let replica = UUID(uuidString: String(record.recordID.recordName.dropFirst(8))),
              let data = record.encryptedValues[payloadKey] as? Data else {
            throw DeviceSyncFailure.invalidRemoteData
        }
        return try DeviceSyncDocument(data: data, replicaID: replica).encoded()
    }

    static func version(of record: CKRecord) throws -> Data {
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        guard encoder.encodedData.count <= 64 * 1024 else { throw DeviceSyncFailure.invalidRemoteData }
        return encoder.encodedData
    }
}
