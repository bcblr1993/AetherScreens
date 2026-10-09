import XCTest
import CloudKit
@testable import AetherScreensCore

final class CloudKitComputerSyncReaderTests: XCTestCase {
    func testPreparedCreationCannotUseUnconditionalOverwriteOrDeleteRecords() throws {
        let data = try ComputerSyncJournal().encoded()
        let operation = try CloudKitComputerSyncReader.modification(journal: data, base: nil, expectedChangeTag: nil)
        XCTAssertEqual(operation.savePolicy, .ifServerRecordUnchanged)
        XCTAssertEqual(operation.recordsToSave?.count, 1)
        XCTAssertTrue(operation.recordIDsToDelete?.isEmpty ?? true)
        XCTAssertThrowsError(try CloudKitComputerSyncReader.modification(journal: data, base: nil, expectedChangeTag: "stale"))
        let unsaved = try CloudKitComputerSyncReader.replacementRecord(journal: data, base: nil)
        XCTAssertThrowsError(try CloudKitComputerSyncReader.modification(journal: data, base: unsaved, expectedChangeTag: nil))
    }

    func testReplacementUsesIndependentCopyAndRejectsUnknownBaseFields() throws {
        var journal = ComputerSyncJournal()
        let original = RemoteDevice(name: "Original", host: "generated.invalid")
        try journal.captureLocalComputers([original])
        let base = try CloudKitComputerSyncReader.replacementRecord(journal: journal.encoded(), base: nil)
        let originalBytes = try XCTUnwrap(base["journal"] as? Data)
        var edited = original
        edited.name = "Edited"
        try journal.captureLocalComputers([edited])
        let replacement = try CloudKitComputerSyncReader.replacementRecord(journal: journal.encoded(), base: base)
        XCTAssertFalse(replacement === base)
        XCTAssertEqual(replacement.recordID, base.recordID)
        XCTAssertEqual(replacement.recordChangeTag, base.recordChangeTag)
        XCTAssertEqual(base["journal"] as? Data, originalBytes)
        XCTAssertEqual(try ComputerSyncJournal(restoring: CloudKitComputerSyncReader.decodeJournal(replacement)).computers.map(\.name), ["Edited"])
        base["unexpected"] = "generated" as CKRecordValue
        XCTAssertThrowsError(try CloudKitComputerSyncReader.replacementRecord(journal: journal.encoded(), base: base))
    }

    func testRecordDecodesOnlyValidConfigurationJournal() throws {
        var journal = ComputerSyncJournal()
        let device = RemoteDevice(name: "Generated", host: "generated.invalid")
        try journal.captureLocalComputers([device])
        let record = CKRecord(recordType: CloudKitComputerSyncReader.recordType, recordID: CloudKitComputerSyncReader.recordID)
        record["schema"] = NSNumber(value: 1)
        record["journal"] = try journal.encoded() as CKRecordValue
        let decoded = try CloudKitComputerSyncReader.decodeJournal(record)
        XCTAssertEqual(try ComputerSyncJournal(restoring: decoded).records, journal.records)
        record["password"] = "generated-test-value" as CKRecordValue
        XCTAssertThrowsError(try CloudKitComputerSyncReader.decodeJournal(record))
    }

    func testLocalCheckpointAndMalformedCloudPayloadAreRejected() throws {
        let record = CKRecord(recordType: CloudKitComputerSyncReader.recordType, recordID: CloudKitComputerSyncReader.recordID)
        record["schema"] = NSNumber(value: 1)
        let checkpoint = try ComputerSyncCheckpoint(journal: ComputerSyncJournal(), devices: [], credentialBindings: [:])
        record["journal"] = try JSONEncoder().encode(checkpoint) as CKRecordValue
        XCTAssertThrowsError(try CloudKitComputerSyncReader.decodeJournal(record))
        record["journal"] = Data(repeating: 0, count: 512 * 1024 + 1) as CKRecordValue
        XCTAssertThrowsError(try CloudKitComputerSyncReader.decodeJournal(record))
    }
}
