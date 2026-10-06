import XCTest
import CloudKit
@testable import AetherScreensCore

final class DeviceSyncPreferencesTests: XCTestCase {
    private let aID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let bID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let computer = RemoteDevice(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                                        name: "Preferences QA", host: "qa.invalid")

    private func seed() throws -> DeviceSyncDocument {
        var document = DeviceSyncDocument(replicaID: aID)
        try document.recordLocalDevices([computer])
        return document
    }

    private func restored(_ source: DeviceSyncDocument) throws -> DeviceSyncDocument {
        try DeviceSyncDocument(data: source.encoded(), replicaID: bID)
    }

    private func json(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func editToolbar(_ data: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        try json(data) {
            var records = $0["records"] as! [[String: Any]]
            var toolbar = records[0]["toolbar"] as! [String: Any]
            edit(&toolbar); records[0]["toolbar"] = toolbar; $0["records"] = records
        }
    }

    func testAbsentPreferencesPreserveVersionOneBytesAndDoNotGenerateFactoryOverrides() throws {
        var document = try seed()
        let before = try document.encoded()
        XCTAssertFalse(try document.recordLocalPreferences(language: nil, keyboards: [:]))
        XCTAssertEqual(try document.encoded(), before)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: before) as! [String: Any])["version"] as? Int, 1)
        XCTAssertNil(document.applicationLanguage)
        XCTAssertTrue(document.keyboardConfigurations.isEmpty)
        XCTAssertEqual(try restored(document).encoded(), before)
    }

    func testLanguageAndCompleteToolbarRoundTripAsVersionTwoWithoutCredentials() throws {
        var document = try seed(); var configuration = KeyboardToolbarConfiguration()
        configuration.size = .small; configuration.position = .top
        configuration.items[0].isVisible = false
        configuration.items.append(.init(action: .spacer))
        var hardware = HardwareKeyboardConfiguration()
        hardware.swapCommandControl = true; hardware.commandBackslashSwitchesApps = false
        hardware.repeatEnabled = false; hardware.repeatDelay = 0.8; hardware.repeatInterval = 0.08
        configuration.hardwareKeyboard = hardware
        configuration.pencilDoubleTapAction = .secondaryClick; configuration.pencilSqueezeAction = .toggleToolbar
        XCTAssertTrue(try document.recordLocalPreferences(language: .simplifiedChinese, keyboards: [computer.id: configuration]))
        let data = try document.encoded(); let copy = try restored(document)
        XCTAssertEqual(copy.applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(copy.keyboardConfigurations[computer.id], configuration)
        XCTAssertEqual(try copy.encoded(), data)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["version"] as? Int, 2)
        func keys(_ value: Any) -> Set<String> {
            if let object = value as? [String: Any] {
                return Set(object.keys).union(object.values.reduce(into: Set<String>()) { $0.formUnion(keys($1)) })
            }
            if let array = value as? [Any] { return array.reduce(into: []) { $0.formUnion(keys($1)) } }
            return []
        }
        XCTAssertTrue(keys(object).isDisjoint(with: ["password", "privateKey", "passphrase", "apiKey", "credentials", "clipboard", "inputText"]))
    }

    func testConcurrentFirstCustomizationsDoNotOverwriteUnchangedDefaults() throws {
        var a = try seed(); var b = try restored(a)
        var left = KeyboardToolbarConfiguration(); left.size = .large
        var lh = HardwareKeyboardConfiguration(); lh.swapCommandControl = true; left.hardwareKeyboard = lh
        var right = KeyboardToolbarConfiguration(); right.position = .top
        var rh = HardwareKeyboardConfiguration(); rh.repeatDelay = 1.2; right.hardwareKeyboard = rh
        right.pencilDoubleTapAction = .middleClick
        try a.recordLocalPreferences(language: .english, keyboards: [computer.id: left])
        try b.recordLocalPreferences(language: nil, keyboards: [computer.id: right])
        let original = a; try a.merge(b); try b.merge(original)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        let merged = try XCTUnwrap(a.keyboardConfigurations[computer.id])
        XCTAssertEqual(merged.size, .large); XCTAssertEqual(merged.position, .top)
        XCTAssertEqual(merged.hardwareKeyboard?.swapCommandControl, true)
        XCTAssertEqual(merged.hardwareKeyboard?.repeatDelay, 1.2)
        XCTAssertEqual(merged.pencilDoubleTapAction, .middleClick)
        XCTAssertEqual(a.applicationLanguage, .english)
    }

    func testConcurrentHardwareMappingRepeatAndPencilFieldsMergeIndependently() throws {
        var a = try seed(); var original = KeyboardToolbarConfiguration()
        original.hardwareKeyboard = HardwareKeyboardConfiguration()
        try a.recordLocalPreferences(language: .system, keyboards: [computer.id: original])
        var b = try restored(a); var left = original; var right = original
        left.hardwareKeyboard?.swapCommandControl = true; left.pencilDoubleTapAction = .secondaryClick
        right.hardwareKeyboard?.repeatEnabled = false; right.hardwareKeyboard?.repeatInterval = 0.1
        right.pencilSqueezeAction = .toggleToolbar
        try a.recordLocalPreferences(language: .system, keyboards: [computer.id: left])
        try b.recordLocalPreferences(language: .system, keyboards: [computer.id: right])
        let savedA = a; try a.merge(b); try b.merge(savedA)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        let result = try XCTUnwrap(a.keyboardConfigurations[computer.id])
        XCTAssertEqual(result.hardwareKeyboard?.swapCommandControl, true)
        XCTAssertEqual(result.hardwareKeyboard?.repeatEnabled, false)
        XCTAssertEqual(result.hardwareKeyboard?.repeatInterval, 0.1)
        XCTAssertEqual(result.pencilDoubleTapAction, .secondaryClick)
        XCTAssertEqual(result.pencilSqueezeAction, .toggleToolbar)
    }

    func testSameFieldAndLayoutHaveDeterministicWinnerAndPreserveValidOrder() throws {
        var a = try seed(); let configuration = KeyboardToolbarConfiguration()
        try a.recordLocalPreferences(language: .system, keyboards: [computer.id: configuration])
        var b = try restored(a); var left = configuration; var right = configuration
        left.size = .large; left.items[0].isVisible = false
        right.size = .small; right.items.swapAt(0, 1)
        try a.recordLocalPreferences(language: .english, keyboards: [computer.id: left])
        try b.recordLocalPreferences(language: .simplifiedChinese, keyboards: [computer.id: right])
        let savedA = a; try a.merge(b); try b.merge(savedA)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        XCTAssertEqual(a.applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(a.keyboardConfigurations[computer.id]?.size, .small)
        XCTAssertEqual(a.keyboardConfigurations[computer.id]?.items, right.items)
    }

    func testMissingLocalOverridesCanClearCustomizationAndLanguageWithoutResurrection() throws {
        var a = try seed()
        try a.recordLocalPreferences(language: .english, keyboards: [computer.id: KeyboardToolbarConfiguration()])
        let stale = try restored(a)
        XCTAssertTrue(try a.recordLocalPreferences(language: nil, keyboards: [:]))
        XCTAssertNil(a.applicationLanguage); XCTAssertTrue(a.keyboardConfigurations.isEmpty)
        XCTAssertFalse(try a.merge(stale))
        XCTAssertNil(a.applicationLanguage); XCTAssertTrue(a.keyboardConfigurations.isEmpty)
        XCTAssertEqual(try restored(a).encoded(), try a.encoded())
    }

    func testDeviceDeletionRemovesItsToolbarAndWinsAgainstOfflineCustomization() throws {
        var a = try seed()
        try a.recordLocalPreferences(language: .english, keyboards: [computer.id: KeyboardToolbarConfiguration()])
        var b = try restored(a); var configuration = try XCTUnwrap(b.keyboardConfigurations[computer.id])
        configuration.position = .top
        try b.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration])
        try a.recordLocalDevices([])
        let deleted = a; try a.merge(b); try b.merge(deleted)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        XCTAssertTrue(a.keyboardConfigurations.isEmpty); XCTAssertTrue(a.devices().isEmpty)
        XCTAssertThrowsError(try a.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
    }

    func testUnchangedPreferenceCaptureIsByteStableAndDoesNotAdvanceClock() throws {
        var document = try seed(); let configuration = KeyboardToolbarConfiguration()
        try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration])
        let before = try document.encoded()
        for _ in 0..<10 {
            XCTAssertFalse(try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
            XCTAssertEqual(try document.encoded(), before)
        }
    }

    func testMalformedToolbarLayoutsAndHardwareAreRejectedAtomically() throws {
        var document = try seed(); let before = try document.encoded()
        var configuration = KeyboardToolbarConfiguration()
        configuration.items.append(configuration.items[0])
        XCTAssertThrowsError(try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
        XCTAssertEqual(try document.encoded(), before)
        configuration = KeyboardToolbarConfiguration()
        configuration.items = (0..<129).map { _ in .init(action: .spacer) }
        XCTAssertThrowsError(try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
        configuration = KeyboardToolbarConfiguration()
        var hardware = HardwareKeyboardConfiguration(); hardware.repeatDelay = 99
        configuration.hardwareKeyboard = hardware
        XCTAssertThrowsError(try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
        hardware.repeatDelay = .infinity; configuration.hardwareKeyboard = hardware
        XCTAssertThrowsError(try document.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration]))
        XCTAssertEqual(try document.encoded(), before)
    }

    func testUnknownPreferenceValuesZeroRevisionsAndClockAreRejected() throws {
        var document = try seed()
        try document.recordLocalPreferences(language: .english, keyboards: [computer.id: KeyboardToolbarConfiguration()])
        let data = try document.encoded()
        for invalid in [
            try json(data) { var value = $0["applicationLanguage"] as! [String: Any]; value["value"] = "future-language"; $0["applicationLanguage"] = value },
            try editToolbar(data) { var value = $0["pencilSqueeze"] as! [String: Any]; value["value"] = "Future Action"; $0["pencilSqueeze"] = value },
            try editToolbar(data) { var value = $0["size"] as! [String: Any]; var revision = value["revision"] as! [String: Any]; revision["counter"] = 0; value["revision"] = revision; $0["size"] = value },
            try json(data) { $0["observedClock"] = 0 },
            try json(data) { $0["version"] = 1 }
        ] { XCTAssertThrowsError(try DeviceSyncDocument(data: invalid, replicaID: bID)) }
        XCTAssertEqual(try document.encoded(), data)
    }

    func testConflictingPreferenceRevisionRejectsWholeMergeIncludingComputerEdit() throws {
        var document = try seed()
        try document.recordLocalPreferences(language: .english, keyboards: [computer.id: KeyboardToolbarConfiguration()])
        let before = try document.encoded()
        let forged = try json(before) {
            var language = $0["applicationLanguage"] as! [String: Any]
            language["value"] = "zh-Hans"; $0["applicationLanguage"] = language
        }
        var incoming = try DeviceSyncDocument(data: forged, replicaID: bID)
        var changed = computer; changed.name = "Unaccepted name"
        try incoming.recordLocalDevices([changed])
        XCTAssertThrowsError(try document.merge(incoming)) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .conflictingRevision)
        }
        XCTAssertEqual(try document.encoded(), before)
    }

    func testDurableOfflineStorePreservesPreferencesAndRejectsStaleWriter() throws {
        let suite = "test.aetherscreens.sync.preferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try DeviceSyncStore(defaults: defaults)
        try first.recordLocalDevices([computer])
        let stale = try DeviceSyncStore(defaults: defaults)
        let configuration = KeyboardToolbarConfiguration()
        try first.recordLocalPreferences(language: .simplifiedChinese, keyboards: [computer.id: configuration])
        let restarted = try DeviceSyncStore(defaults: defaults)
        XCTAssertEqual(restarted.applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(restarted.keyboardConfigurations[computer.id], configuration)
        XCTAssertThrowsError(try stale.recordLocalPreferences(language: .english, keyboards: [:])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .staleLocalReplica)
        }
        XCTAssertEqual(try DeviceSyncStore(defaults: defaults).exportedData(), try first.exportedData())
    }

    func testConflictingToolbarRevisionRejectsWholeFetchedBatchAndKeepsDurablePreferences() throws {
        let suite = "test.aetherscreens.sync.preferences.batch." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try DeviceSyncStore(defaults: defaults)
        let configuration = KeyboardToolbarConfiguration()
        try store.recordLocalDevices([computer])
        try store.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration])
        let before = try store.exportedData()
        var valid = try DeviceSyncDocument(data: before, replicaID: bID)
        var changed = configuration; changed.position = .top
        try valid.recordLocalPreferences(language: .english, keyboards: [computer.id: changed])
        let forged = try editToolbar(before) {
            var size = $0["size"] as! [String: Any]; size["value"] = "Large"; $0["size"] = size
        }
        XCTAssertThrowsError(try store.receiveDocuments([valid.encoded(), forged])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .conflictingRevision)
        }
        XCTAssertEqual(try store.exportedData(), before)
        XCTAssertEqual(try DeviceSyncStore(defaults: defaults).keyboardConfigurations[computer.id], configuration)
    }

    func testTwoOfflineReplicasExchangeLanguageAndToolbarUsingEncryptedRecordCodec() async throws {
        let names = (0..<2).map { _ in "test.aetherscreens.sync.preferences.exchange." + UUID().uuidString }
        let da = try XCTUnwrap(UserDefaults(suiteName: names[0]))
        let db = try XCTUnwrap(UserDefaults(suiteName: names[1]))
        defer { for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
        let a = try DeviceSyncStore(defaults: da); let b = try DeviceSyncStore(defaults: db)
        let transport = SyncTestTransport()
        let ea = DeviceSyncExchange(store: a, transport: transport, defaults: da)
        let eb = DeviceSyncExchange(store: b, transport: transport, defaults: db)
        var configuration = KeyboardToolbarConfiguration(); configuration.size = .small
        try a.recordLocalDevices([computer])
        try a.recordLocalPreferences(language: .simplifiedChinese, keyboards: [computer.id: configuration])
        _ = try await ea.synchronize(); _ = try await eb.synchronize()
        XCTAssertEqual(b.applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(b.keyboardConfigurations[computer.id], configuration)
        try a.recordLocalPreferences(language: .english, keyboards: [computer.id: configuration])
        configuration.pencilSqueezeAction = .toggleToolbar
        try b.recordLocalPreferences(language: .simplifiedChinese, keyboards: [computer.id: configuration])
        _ = try await eb.synchronize(); _ = try await ea.synchronize(); _ = try await eb.synchronize()
        XCTAssertEqual(try a.exportedData(), try b.exportedData())
        XCTAssertEqual(b.applicationLanguage, .english)
        XCTAssertEqual(a.keyboardConfigurations[computer.id]?.pencilSqueezeAction, .toggleToolbar)
        let zone = CKRecordZone.ID(zoneName: DeviceCloudRecordCodec.zoneName, ownerName: "Synthetic QA Owner")
        let data = try a.exportedData()
        let record = try DeviceCloudRecordCodec.record(document: data, replicaID: a.replicaID,
                                                        zoneID: zone, version: nil)
        XCTAssertEqual(try DeviceCloudRecordCodec.document(from: record, zoneID: zone), data)
    }
}
