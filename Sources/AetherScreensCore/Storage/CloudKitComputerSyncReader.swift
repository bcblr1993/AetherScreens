import Foundation
import CloudKit

protocol ComputerSyncTransport: Sendable {
    func fetch() async throws -> CloudKitComputerSyncReader.Read
    func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> CloudKitComputerSyncReader.Read
}

/// Opt-in CloudKit read path. Construction does not perform requests; the app
/// must configure its container and deliberately call fetch after user opt-in.
actor CloudKitComputerSyncReader: ComputerSyncTransport {
    struct Snapshot: Sendable {
        let journal: Data
        let changeTag: String
    }
    struct Read: Sendable {
        let accountIdentifier: String
        let snapshot: Snapshot?
    }
    enum Failure: Error { case accountUnavailable, accountChanged, invalidRecord, versionConflict }
    static let recordType = "AetherScreensComputerLibrary"
    static let recordID = CKRecord.ID(recordName: "computer-library-v1")
    private let container: CKContainer
    private let accountGate = CloudKitAccountOperationGate()

    init(containerIdentifier: String) {
        container = CKContainer(identifier: containerIdentifier)
    }

    func fetch() async throws -> Read {
        try Task.checkCancellation()
        let token = accountGate.begin()
        guard try await accountStatus() == .available else { throw Failure.accountUnavailable }
        let account = try await accountRecordID()
        let record: CKRecord?
        do { record = try await container.privateCloudDatabase.record(for: Self.recordID) }
        catch let error as CKError where error.code == .unknownItem { record = nil }
        let current = try await accountRecordID()
        guard current == account, accountGate.isCurrent(token) else { throw Failure.accountChanged }
        try Task.checkCancellation()
        guard let record else { return Read(accountIdentifier: account.recordName, snapshot: nil) }
        let journal = try Self.decodeJournal(record)
        guard let changeTag = record.recordChangeTag, !changeTag.isEmpty else { throw Failure.invalidRecord }
        return Read(accountIdentifier: account.recordName, snapshot: Snapshot(journal: journal, changeTag: changeTag))
    }

    /// Opt-in conditional upload. Re-read the server record rather than rebuild
    /// its system fields from a change tag; a stale caller must merge and retry.
    func save(journal: Data, accountIdentifier: String, expectedChangeTag: String?) async throws -> Read {
        try Task.checkCancellation()
        let token = accountGate.begin()
        guard try await accountStatus() == .available else { throw Failure.accountUnavailable }
        let account = try await accountRecordID()
        guard account.recordName == accountIdentifier, accountGate.isCurrent(token) else { throw Failure.accountChanged }
        let base: CKRecord?
        do { base = try await container.privateCloudDatabase.record(for: Self.recordID) }
        catch let error as CKError where error.code == .unknownItem { base = nil }
        let current = try await accountRecordID()
        guard current == account, accountGate.isCurrent(token) else { throw Failure.accountChanged }
        try Task.checkCancellation()
        let operation = try Self.modification(journal: journal, base: base, expectedChangeTag: expectedChangeTag)
        let database = container.privateCloudDatabase
        let saved = try await CloudKitModifyOperationRunner.runSaving(operation, gate: accountGate, token: token) {
            database.add($0)
        }
        let after = try await accountRecordID()
        guard after == account, accountGate.isCurrent(token) else { throw Failure.accountChanged }
        try Task.checkCancellation()
        return Read(accountIdentifier: account.recordName, snapshot: saved)
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await CloudKitAccountRequestRunner.run { completion in
            container.accountStatus { status, error in
                if let error { completion(.failure(error)) }
                else { completion(.success(status)) }
            }
        }
    }

    private func accountRecordID() async throws -> CKRecord.ID {
        try await CloudKitAccountRequestRunner.run { completion in
            container.fetchUserRecordID { record, error in
                if let error { completion(.failure(error)) }
                else if let record { completion(.success(record)) }
                else { completion(.failure(Failure.accountUnavailable)) }
            }
        }
    }

    /// CKRecord system metadata is separate; application fields must be exactly
    /// the version and whitelist journal, never a local checkpoint or secrets.
    static func decodeJournal(_ record: CKRecord) throws -> Data {
        guard record.recordType == recordType, record.recordID == recordID,
              Set(record.allKeys()) == Set(["schema", "journal"]),
              let schema = record["schema"] as? NSNumber, schema == NSNumber(value: 1),
              let data = record["journal"] as? Data, data.count <= 512 * 1024 else { throw Failure.invalidRecord }
        return try ComputerSyncJournal(restoring: data).encoded()
    }

    /// Copy the base's CloudKit system fields/change tag without mutating it.
    /// The eventual writer must use ifServerRecordUnchanged. No I/O occurs here.
    static func replacementRecord(journal data: Data, base: CKRecord?) throws -> CKRecord {
        guard data.count <= 512 * 1024 else { throw Failure.invalidRecord }
        let canonical = try ComputerSyncJournal(restoring: data).encoded()
        let record: CKRecord
        if let base {
            _ = try decodeJournal(base)
            guard let copy = base.copy() as? CKRecord else { throw Failure.invalidRecord }
            record = copy
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record["schema"] = NSNumber(value: 1)
        record["journal"] = canonical as CKRecordValue
        return record
    }

    /// Build but do not enqueue the operation. Account-change/cancellation gates
    /// must be installed by the writer before handing this to CloudKit.
    static func modification(journal: Data, base: CKRecord?, expectedChangeTag: String?) throws -> CKModifyRecordsOperation {
        if let base {
            guard let tag = base.recordChangeTag, !tag.isEmpty, tag == expectedChangeTag else {
                throw Failure.versionConflict
            }
        } else if expectedChangeTag != nil { throw Failure.versionConflict }
        let record = try replacementRecord(journal: journal, base: base)
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        operation.configuration = configuration
        operation.savePolicy = .ifServerRecordUnchanged
        // One complete journal in one record; no cross-record atomicity is needed
        // in the default private zone. Server change-tag checks remain mandatory.
        operation.isAtomic = false
        return operation
    }
}
