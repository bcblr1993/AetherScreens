import XCTest
@testable import AetherScreensCore

final class ComputerSyncJournalTests: XCTestCase {
    func testCompleteLocalCaptureTracksEditsAndDeletionButIgnoresRuntimeChanges() throws {
        var journal = ComputerSyncJournal()
        var first = RemoteDevice(name: "First", host: "first.invalid")
        let second = RemoteDevice(name: "Second", host: "second.invalid")
        XCTAssertTrue(try journal.captureLocalComputers([first, second]))
        let clock = journal.counter
        first.isOnline = false
        first.lastConnected = Date()
        XCTAssertFalse(try journal.captureLocalComputers([second, first]))
        XCTAssertEqual(journal.counter, clock)
        first.name = "Edited"
        XCTAssertTrue(try journal.captureLocalComputers([first]))
        XCTAssertEqual(journal.counter, clock + 2)
        XCTAssertNil(try XCTUnwrap(journal.records[second.id]).metadata)
        XCTAssertEqual(journal.computers.map(\.name), ["Edited"])
        let before = try journal.encoded()
        XCTAssertThrowsError(try journal.captureLocalComputers([first, second]))
        XCTAssertEqual(try journal.encoded(), before)
    }

    func testInvalidOrDuplicateLocalBatchLeavesJournalUnchanged() throws {
        var journal = ComputerSyncJournal()
        let device = RemoteDevice(name: "Original", host: "original.invalid")
        try journal.captureLocalComputers([device])
        let before = try journal.encoded()
        XCTAssertThrowsError(try journal.captureLocalComputers([device, device]))
        XCTAssertThrowsError(try journal.captureLocalComputers([
            RemoteDevice(name: "New", host: "new.invalid"),
            RemoteDevice(name: "Invalid", host: "")]))
        XCTAssertEqual(try journal.encoded(), before)
    }

    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private func metadata(_ name: String = "Work Mac", id: UUID = UUID()) -> ComputerSyncMetadata {
        ComputerSyncMetadata(device: RemoteDevice(id: id, name: name, host: "127.0.0.1"))
    }

    func testEquivalentRecordsFromDifferentPeersDoNotRequestRewriteLoops() throws {
        var a = ComputerSyncJournal(peer: first), b = ComputerSyncJournal(peer: second)
        try a.upsert(metadata())
        let firstMerge = try b.merge(a.encoded())
        XCTAssertTrue(firstMerge.didChangeRecords)
        XCTAssertFalse(firstMerge.remoteNeedsUpdate)
        // Local persistence differs by peer; cloud-write decisions compare records.
        XCTAssertNotEqual(try a.encoded(), try b.encoded())
        let echo = try a.merge(b.encoded())
        XCTAssertFalse(echo.didChangeRecords)
        XCTAssertFalse(echo.didAdvanceClock)
        XCTAssertFalse(echo.remoteNeedsUpdate)
        try a.delete(a.computers[0].id)
        let stale = try a.merge(b.encoded())
        XCTAssertFalse(stale.didChangeRecords)
        XCTAssertTrue(stale.remoteNeedsUpdate)
    }

    func testConcurrentEditsConvergeIndependentlyOfMergeOrder() throws {
        var a = ComputerSyncJournal(peer: first), b = ComputerSyncJournal(peer: second)
        let original = metadata()
        try a.upsert(original); try b.merge(a.encoded())
        var left = original, right = original
        left.name = "Office"; right.name = "Home"
        try a.upsert(left); try b.upsert(right)
        let aData = try a.encoded(), bData = try b.encoded()
        try a.merge(bData); try b.merge(aData)
        XCTAssertEqual(a.records, b.records)
        XCTAssertEqual(a.computers.first?.name, "Home")
        try a.merge(bData)
        XCTAssertEqual(a.records, b.records)
    }

    func testDeletionCannotBeResurrectedByHigherClockOfflineEdit() throws {
        var a = ComputerSyncJournal(peer: first), b = ComputerSyncJournal(peer: second)
        let original = metadata()
        try a.upsert(original); try b.merge(a.encoded())
        let stale = try b.encoded()
        try a.delete(original.id)
        for i in 0..<20 { try b.upsert(metadata("Other \(i)")) }
        var edited = original; edited.name = "Offline rename"
        try b.upsert(edited)
        let editedData = try b.encoded(), deletedData = try a.encoded()
        try a.merge(editedData); try b.merge(deletedData)
        try a.merge(stale)
        XCTAssertNil(a.records[original.id]?.metadata)
        XCTAssertEqual(a.records, b.records)
        XCTAssertThrowsError(try a.upsert(original)) { XCTAssertEqual($0 as? ComputerSyncJournal.Failure, .deletedRecord) }
        let replacement = metadata("Added again")
        try a.upsert(replacement)
        XCTAssertTrue(a.computers.contains { $0.id == replacement.id })
    }

    func testRelaunchKeepsPeerClockAndUnchangedMetadataDoesNotWrite() throws {
        var journal = ComputerSyncJournal(peer: first)
        let original = metadata()
        try journal.upsert(original)
        let data = try journal.encoded()
        var restored = try ComputerSyncJournal(restoring: data)
        XCTAssertEqual(restored.peer, first); XCTAssertEqual(restored.counter, 1)
        try restored.upsert(original)
        XCTAssertEqual(try restored.encoded(), data)
        var edited = original; edited.name = "Updated"
        try restored.upsert(edited)
        XCTAssertEqual(restored.counter, 2)
    }

    func testCorruptDuplicateRecordAndUnknownSchemaAreRejectedAtomically() throws {
        var journal = ComputerSyncJournal(peer: first)
        try journal.upsert(metadata())
        let before = try journal.encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        object["records"] = records + records
        XCTAssertThrowsError(try journal.merge(JSONSerialization.data(withJSONObject: object)))
        XCTAssertEqual(try journal.encoded(), before)
        object["records"] = records; object["schema"] = 2
        XCTAssertThrowsError(try journal.merge(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? ComputerSyncJournal.Failure, .unsupportedSchema)
        }
        XCTAssertEqual(try journal.encoded(), before)
    }

    func testSameVersionWithDifferentPayloadDoesNotPartiallyMerge() throws {
        var journal = ComputerSyncJournal(peer: first)
        try journal.upsert(metadata())
        let before = try journal.encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        var payload = try XCTUnwrap(records[0]["metadata"] as? [String: Any])
        payload["name"] = "Conflicting backup"
        records[0]["metadata"] = payload; object["records"] = records
        XCTAssertThrowsError(try journal.merge(JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? ComputerSyncJournal.Failure, .conflictingVersion)
        }
        XCTAssertEqual(try journal.encoded(), before)
    }

    func testRuntimeStateIsExcludedAndSSHReferenceRetainsFailClosedConfiguration() throws {
        let key = UUID()
        let ssh = try XCTUnwrap(SSHConnectionSettings(server: SSHServerAddress(host: "localhost")!, username: "qa-user", authentication: .privateKey(key)))
        let device = RemoteDevice(name: "SSH Mac", host: "127.0.0.1", isOnline: true, lastConnected: Date(), ssh: ssh)
        var journal = ComputerSyncJournal(peer: first)
        try journal.upsert(ComputerSyncMetadata(device: device))
        let data = try journal.encoded(), text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("isOnline")); XCTAssertFalse(text.contains("lastConnected"))
        XCTAssertFalse(text.contains("thumbnail")); XCTAssertFalse(text.contains("passphrase"))
        let restored = try ComputerSyncJournal(restoring: data)
        XCTAssertEqual(restored.computers.first?.ssh, ssh)
    }

    func testOversizedSnapshotAndExhaustedClockFailWithoutMutation() throws {
        var journal = ComputerSyncJournal(peer: first)
        try journal.upsert(metadata())
        let before = try journal.encoded()
        XCTAssertThrowsError(try journal.merge(Data(repeating: 0, count: ComputerSyncJournal.maximumBytes + 1)))
        XCTAssertEqual(try journal.encoded(), before)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        object["counter"] = NSNumber(value: UInt64.max)
        var exhausted = try ComputerSyncJournal(restoring: JSONSerialization.data(withJSONObject: object))
        let unchanged = try exhausted.encoded()
        XCTAssertThrowsError(try exhausted.delete(journal.computers[0].id)) {
            XCTAssertEqual($0 as? ComputerSyncJournal.Failure, .clockExhausted)
        }
        XCTAssertEqual(try exhausted.encoded(), unchanged)
    }
}
