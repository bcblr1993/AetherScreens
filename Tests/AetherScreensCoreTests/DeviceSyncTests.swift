import XCTest
@testable import AetherScreensCore
import AetherScreensSSH

final class DeviceSyncTests: XCTestCase {
    private let replicaA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let replicaB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let replicaC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let deviceID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    private func device() -> RemoteDevice {
        RemoteDevice(id: deviceID, name: "Mac QA", host: "qa.invalid", authMethod: .macAccount,
                     username: "qa-user", isOnline: true, lastConnected: Date(timeIntervalSince1970: 123),
                     preferredDisplayID: 0)
    }

    private func seed() throws -> DeviceSyncDocument {
        var document = DeviceSyncDocument(replicaID: replicaA)
        XCTAssertTrue(try document.recordLocalDevices([device()]))
        return document
    }

    private func replica(_ source: DeviceSyncDocument, id: UUID) throws -> DeviceSyncDocument {
        try .init(data: source.encoded(), replicaID: id)
    }

    private func transformJSON(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func testConcurrentIndependentPreferencesMergeWithoutLosingEitherEdit() throws {
        var a = try seed(); var b = try replica(a, id: replicaB)
        var left = try XCTUnwrap(a.devices().first); left.name = "Renamed on Mac"
        var right = try XCTUnwrap(b.devices().first); right.cursorSpeed = 1.75
        right.sharedClipboard = false
        try a.recordLocalDevices([left]); try b.recordLocalDevices([right])
        let originalA = a
        try a.merge(b); try b.merge(originalA)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        let result = try XCTUnwrap(a.devices().first)
        XCTAssertEqual(result.name, left.name)
        XCTAssertEqual(result.cursorSpeed, right.cursorSpeed)
        XCTAssertFalse(result.effectiveSharedClipboard)
        XCTAssertEqual(result.preferredDisplayID, 0)
    }

    func testConcurrentSamePreferenceHasDeterministicWinnerOnBothReplicas() throws {
        var a = try seed(); var b = try replica(a, id: replicaB)
        var left = try XCTUnwrap(a.devices().first); left.name = "Left"
        var right = try XCTUnwrap(b.devices().first); right.name = "Right"
        try a.recordLocalDevices([left]); try b.recordLocalDevices([right])
        let originalA = a
        try a.merge(b); try b.merge(originalA)
        XCTAssertEqual(a.devices().first?.name, "Right")
        XCTAssertEqual(try a.encoded(), try b.encoded())
        XCTAssertFalse(try a.merge(b))
    }

    func testConcurrentEndpointAndDisplaySelectionDoNotApplyOldServersScreenID() throws {
        var a = try seed(); var b = try replica(a, id: replicaB)
        var left = try XCTUnwrap(a.devices().first); left.host = "new.qa.invalid"
        left.username = "new-account"; left.preferredDisplayID = nil
        var right = try XCTUnwrap(b.devices().first); right.preferredDisplayID = 9
        try a.recordLocalDevices([left]); try b.recordLocalDevices([right])
        let originalA = a
        try a.merge(b); try b.merge(originalA)
        XCTAssertEqual(a.devices().first?.host, left.host)
        XCTAssertNil(a.devices().first?.preferredDisplayID)
        XCTAssertEqual(try a.encoded(), try b.encoded())
    }

    func testOfflineDeletionWinsOverMultipleLaterEditsAndStaleReplay() throws {
        let initial = try seed()
        var a = initial; var b = try replica(initial, id: replicaB)
        try a.recordLocalDevices([])
        var right = try XCTUnwrap(b.devices().first)
        for i in 0..<5 { right.name = "Offline \(i)"; try b.recordLocalDevices([right]) }
        let originalA = a
        try a.merge(b); try b.merge(originalA)
        XCTAssertTrue(a.devices().isEmpty); XCTAssertTrue(b.devices().isEmpty)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        XCTAssertFalse(try a.merge(initial))
        let deleted = try a.encoded()
        XCTAssertThrowsError(try a.recordLocalDevices([right])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .deletedIdentifier)
        }
        XCTAssertEqual(try a.encoded(), deleted)
        let fresh = RemoteDevice(name: right.name, host: right.host)
        XCTAssertTrue(try a.recordLocalDevices([fresh]))
        XCTAssertEqual(a.devices().first?.id, fresh.id)
    }

    func testThreeReplicaMergeIsAssociativeAndDeliveryOrderDoesNotMatter() throws {
        let initial = try seed()
        var a = initial; var b = try replica(initial, id: replicaB)
        var c = try replica(initial, id: replicaC)
        var da = try XCTUnwrap(a.devices().first); da.name = "Mac"
        var db = try XCTUnwrap(b.devices().first); db.sharedClipboard = false
        var dc = try XCTUnwrap(c.devices().first); dc.disconnectAction = .lockScreen
        try a.recordLocalDevices([da]); try b.recordLocalDevices([db]); try c.recordLocalDevices([dc])
        var first = a; try first.merge(b); try first.merge(c)
        var bc = b; try bc.merge(c)
        var second = a; try second.merge(bc)
        var third = c; try third.merge(a); try third.merge(b)
        XCTAssertEqual(try first.encoded(), try second.encoded())
        XCTAssertEqual(try first.encoded(), try third.encoded())
        XCTAssertFalse(try first.merge(first))
    }

    func testRuntimeStatusAndHistoryStayLocalAndDoNotGenerateSyncWrites() throws {
        var a = try seed()
        let before = try a.encoded()
        var local = device(); local.isOnline = false
        local.lastConnected = Date(timeIntervalSince1970: 456)
        XCTAssertFalse(try a.recordLocalDevices([local]))
        XCTAssertEqual(try a.encoded(), before)
        XCTAssertFalse(try XCTUnwrap(a.devices().first).isOnline)
        XCTAssertNil(a.devices().first?.lastConnected)
        XCTAssertEqual(a.devices(retainingLocalState: [local]).first?.lastConnected, local.lastConnected)
        var new = try XCTUnwrap(a.devices().first); new.host = "new.qa.invalid"
        new.preferredDisplayID = nil; try a.recordLocalDevices([new])
        XCTAssertNil(a.devices(retainingLocalState: [local]).first?.lastConnected)
        XCTAssertFalse(try XCTUnwrap(a.devices(retainingLocalState: [device()]).first).isOnline)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("lastConnected"))
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("isOnline"))
    }

    func testRoundTripCarriesSSHConfigurationWithoutCredentialFields() throws {
        var device = device()
        device.sshConfiguration = try SSHConfiguration(host: "ssh.qa.invalid", username: "qa-ssh",
                                                        authentication: .ed25519)
        var a = DeviceSyncDocument(replicaID: replicaA)
        try a.recordLocalDevices([device])
        let data = try a.encoded()
        let restored = try DeviceSyncDocument(data: data, replicaID: replicaB)
        XCTAssertEqual(restored.devices().first?.sshConfiguration, device.sshConfiguration)
        XCTAssertEqual(restored.devices().first?.username, device.username)
        // Authentication method is metadata; private key bytes and passwords have no field in the schema.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func keys(_ object: Any) -> Set<String> {
            if let dictionary = object as? [String: Any] {
                return Set(dictionary.keys).union(dictionary.values.reduce(into: Set<String>()) { $0.formUnion(keys($1)) })
            }
            if let array = object as? [Any] { return array.reduce(into: []) { $0.formUnion(keys($1)) } }
            return []
        }
        XCTAssertTrue(keys(object).isDisjoint(with: ["password", "privateKey", "passphrase", "credentials", "hostKeyPin"]))
        XCTAssertEqual(data, try restored.encoded())
    }

    func testCorruptVersionDuplicateIDsAndInvalidClockCannotOverwriteReplica() throws {
        let a = try seed(); let data = try a.encoded()
        let unknown = try transformJSON(data) { $0["version"] = 99 }
        XCTAssertThrowsError(try DeviceSyncDocument(data: unknown, replicaID: replicaB)) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .unsupportedVersion)
        }
        let duplicate = try transformJSON(data) {
            let records = $0["records"] as! [Any]; $0["records"] = records + records
        }
        XCTAssertThrowsError(try DeviceSyncDocument(data: duplicate, replicaID: replicaB))
        let invalid = try transformJSON(data) { $0["observedClock"] = 0 }
        XCTAssertThrowsError(try DeviceSyncDocument(data: invalid, replicaID: replicaB))
        XCTAssertThrowsError(try DeviceSyncDocument(data: Data("broken".utf8), replicaID: replicaB))
        XCTAssertEqual(try a.encoded(), data)
    }

    func testConflictingEqualRevisionRejectsWholeMergeInsteadOfPartialChanges() throws {
        var a = try seed(); let before = try a.encoded()
        let forged = try transformJSON(before) {
            var records = $0["records"] as! [[String: Any]]
            var name = records[0]["name"] as! [String: Any]; name["value"] = "Changed without revision"
            records[0]["name"] = name; $0["records"] = records
        }
        let b = try DeviceSyncDocument(data: forged, replicaID: replicaB)
        XCTAssertThrowsError(try a.merge(b)) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .conflictingRevision)
        }
        XCTAssertEqual(try a.encoded(), before)
    }

    func testQuotaOverflowAndDuplicateLocalIDsAreAtomic() throws {
        var a = try seed(); let before = try a.encoded()
        var large = device(); large.name = String(repeating: "x", count: DeviceSyncDocument.maximumEncodedBytes)
        XCTAssertThrowsError(try a.recordLocalDevices([large])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .quotaExceeded)
        }
        XCTAssertEqual(try a.encoded(), before)
        XCTAssertThrowsError(try a.recordLocalDevices([device(), device()]))
        XCTAssertEqual(try a.encoded(), before)
        XCTAssertThrowsError(try DeviceSyncDocument(data: Data(repeating: 32, count: DeviceSyncDocument.maximumEncodedBytes + 1), replicaID: replicaB))
    }

    func testClockOverflowFailsWithoutWrappingAndLearnedClockSurvivesRestart() throws {
        var a = try seed()
        let before = try transformJSON(a.encoded()) { $0["observedClock"] = NSNumber(value: UInt64.max) }
        a = try DeviceSyncDocument(data: before, replicaID: replicaA)
        var edit = device(); edit.name = "Changed"
        XCTAssertThrowsError(try a.recordLocalDevices([edit])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .clockExhausted)
        }
        XCTAssertEqual(try a.encoded(), before)
    }

    func testDurableReplicaKeepsOfflineEditsAndDeletionAcrossRestarts() throws {
        let suite = "test.aetherscreens.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try DeviceSyncStore(defaults: defaults)
        try first.recordLocalDevices([device()]); let initial = try first.exportedData()
        let reopened = try DeviceSyncStore(defaults: defaults)
        XCTAssertEqual(try reopened.exportedData(), initial)
        var edited = device(); edited.name = "Offline name"
        try reopened.recordLocalDevices([edited])
        let afterEdit = try reopened.exportedData()
        let afterRestart = try DeviceSyncStore(defaults: defaults)
        XCTAssertEqual(try afterRestart.exportedData(), afterEdit)
        try afterRestart.recordLocalDevices([])
        let deleted = try afterRestart.exportedData()
        let final = try DeviceSyncStore(defaults: defaults)
        XCTAssertFalse(try final.receive(initial))
        XCTAssertTrue(final.devices().isEmpty)
        // Receiving stale data cannot discard the durable tombstone or offline revision clock.
        XCTAssertEqual(try final.exportedData(), deleted)
        XCTAssertThrowsError(try final.receive(Data("corrupt".utf8)))
        XCTAssertEqual(try final.exportedData(), deleted)
    }

    func testMalformedLocalLedgerIsPreservedAndDoesNotResetToEmpty() throws {
        let suite = "test.aetherscreens.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("corrupt-ledger".utf8)
        defaults.set(corrupt, forKey: DeviceSyncStore.documentKey)
        XCTAssertThrowsError(try DeviceSyncStore(defaults: defaults))
        XCTAssertEqual(defaults.data(forKey: DeviceSyncStore.documentKey), corrupt)
    }

    func testStaleLocalStoreCannotOverwriteNewerOfflineEdits() throws {
        let suite = "test.aetherscreens.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try DeviceSyncStore(defaults: defaults)
        try first.recordLocalDevices([device()])
        let stale = try DeviceSyncStore(defaults: defaults)
        var latest = device(); latest.name = "Newer saved edit"
        try first.recordLocalDevices([latest])
        let before = try first.exportedData()
        var oldEdit = device(); oldEdit.cursorSpeed = 1.5
        XCTAssertThrowsError(try stale.recordLocalDevices([oldEdit])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .staleLocalReplica)
        }
        XCTAssertEqual(defaults.data(forKey: DeviceSyncStore.documentKey), before)
        XCTAssertEqual(try DeviceSyncStore(defaults: defaults).devices().first?.name, latest.name)
    }

    func testDeletionMergePreservesLearnedClockEvenWhenIncomingRecordsAreDiscarded() throws {
        var a = try seed(); var b = try replica(a, id: replicaB)
        try a.recordLocalDevices([])
        var edit = device()
        for i in 0..<10 { edit.name = "Offline \(i)"; try b.recordLocalDevices([edit]) }
        XCTAssertFalse(try a.merge(b))
        let bytes = try a.encoded()
        var restored = try DeviceSyncDocument(data: bytes, replicaID: replicaA)
        let new = RemoteDevice(name: "Another target", host: "another.qa.invalid")
        try restored.recordLocalDevices([new])
        let data = try restored.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["observedClock"] as? NSNumber)?.uint64Value, 12)
        XCTAssertEqual(restored.devices().first?.id, new.id)
    }
}
