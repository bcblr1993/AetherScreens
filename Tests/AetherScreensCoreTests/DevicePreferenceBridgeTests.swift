import XCTest
@testable import AetherScreensCore

final class DevicePreferenceBridgeTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func library() throws -> (DeviceStore, UserDefaults, KeyboardToolbarStore) {
        let suite = "test.aetherscreens.preference-bridge." + UUID().uuidString
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (TestStorage.make(userDefaults: defaults), defaults, KeyboardToolbarStore(defaults: defaults))
    }

    private func computer() -> RemoteDevice { RemoteDevice(name: "Preference QA", host: "qa.invalid") }

    private func document(_ store: DeviceStore) throws -> DeviceSyncDocument {
        try DeviceSyncDocument(data: store.synchronizationReplica().exportedData(), replicaID: UUID())
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 30_000_000) }

    @MainActor
    func testNativePreferencesStayLocalUntilSelectedThenPersistOfflineAcrossRestart() throws {
        let previousLanguage = AppLocalization.language
        defer { AppLocalization.select(previousLanguage) }
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device)
        let language = AppLanguageSettings(defaults: defaults)
        language.language = .simplifiedChinese
        var config = KeyboardToolbarConfiguration(); config.size = .large
        config.pencilSqueezeAction = .secondaryClick
        keyboards.save(config, for: device.id)
        XCTAssertNil(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key))
        try store.selectStorage(.iCloud)
        config = keyboards.load(for: device.id); config.position = .top
        keyboards.save(config, for: device.id)
        let checkpoint = try DeviceLibrarySyncCheckpoint(data: XCTUnwrap(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)))
        XCTAssertEqual(try checkpoint.document().applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(try checkpoint.document().keyboardConfigurations[device.id], config)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(try document(restarted).keyboardConfigurations[device.id], config)
        XCTAssertEqual(try document(restarted).applicationLanguage, .simplifiedChinese)
    }

    @MainActor
    func testFactoryLoadsAndUnrelatedKeysNeverCreateOverridesOrChangeCloudBytes() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        let replica = try store.synchronizationReplica(), before = try replica.exportedData()
        _ = keyboards.load(for: device.id); _ = keyboards.load(for: device.id)
        keyboards.save(KeyboardToolbarConfiguration(), for: UUID())
        defaults.set("qa-local-token", forKey: "qa.unrelated.token")
        XCTAssertEqual(try replica.exportedData(), before)
        XCTAssertTrue(try document(store).keyboardConfigurations.isEmpty)
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("qa-local-token"))
    }

    @MainActor
    func testForegroundNativeEditDuringFetchMergesWithRemoteLanguageAndToolbarSize() async throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device)
        keyboards.save(KeyboardToolbarConfiguration(), for: device.id)
        try store.selectStorage(.iCloud)
        var remote = try document(store)
        var larger = try XCTUnwrap(remote.keyboardConfigurations[device.id]); larger.size = .large
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [device.id: larger])
        var local = keyboards.load(for: device.id); local.pencilSqueezeAction = .secondaryClick
        let transport = SyncTestTransport()
        await transport.seed(try remote.encoded(), for: remote.replicaID)
        let localEdit = local
        await transport.configure(fetchStarted: { keyboards.save(localEdit, for: device.id) })
        let exchange = DeviceSyncExchange(store: try store.synchronizationReplica(), transport: transport, defaults: defaults)
        let completed = try await exchange.synchronize()
        XCTAssertEqual(completed, .synchronized)
        XCTAssertEqual(defaults.string(forKey: AppLocalization.preferenceKey), "zh-Hans")
        let merged = keyboards.load(for: device.id)
        XCTAssertEqual(merged.size, .large)
        XCTAssertEqual(merged.pencilSqueezeAction, .secondaryClick)
        XCTAssertEqual(try document(store).keyboardConfigurations[device.id], merged)
    }

    @MainActor
    func testNativeEditDuringPublicationRemainsPendingAndIsPublishedOnRetry() async throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var config = KeyboardToolbarConfiguration(); config.position = .top
        let transport = SyncTestTransport()
        let localEdit = config
        await transport.configure(onPublish: { keyboards.save(localEdit, for: device.id) })
        let exchange = DeviceSyncExchange(store: try store.synchronizationReplica(), transport: transport, defaults: defaults)
        let pending = try await exchange.synchronize()
        XCTAssertEqual(pending, .pendingLocalChanges)
        await transport.configure()
        let completed = try await exchange.synchronize()
        XCTAssertEqual(completed, .synchronized)
        XCTAssertEqual(try document(store).keyboardConfigurations[device.id], keyboards.load(for: device.id))
    }

    @MainActor
    func testPublicationFailureKeepsImportedPreferencesAndRetryCannotClearThem() async throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var remote = try document(store)
        var config = KeyboardToolbarConfiguration(); config.size = .small; config.position = .top
        config.normalize()
        try remote.recordLocalPreferences(language: .english, keyboards: [device.id: config])
        let transport = SyncTestTransport()
        await transport.seed(try remote.encoded(), for: remote.replicaID)
        await transport.configure(publishFailure: .remoteConflict)
        let exchange = DeviceSyncExchange(store: try store.synchronizationReplica(), transport: transport, defaults: defaults)
        do { _ = try await exchange.synchronize(); XCTFail("Expected publication failure") }
        catch { XCTAssertEqual(error as? DeviceSyncFailure, .remoteConflict) }
        XCTAssertEqual(keyboards.load(for: device.id), config)
        XCTAssertEqual(defaults.string(forKey: AppLocalization.preferenceKey), "en")
        let restarted = TestStorage.make(userDefaults: defaults)
        await transport.configure()
        let retry = DeviceSyncExchange(store: try restarted.synchronizationReplica(), transport: transport, defaults: defaults)
        let completed = try await retry.synchronize()
        XCTAssertEqual(completed, .synchronized)
        XCTAssertEqual(try document(restarted).keyboardConfigurations[device.id], config)
        XCTAssertEqual(try document(restarted).applicationLanguage, .english)
    }

    @MainActor
    func testRemoteDeletionClearsOnlyItsSavedOverrideAndCannotResurrectIt() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(), other = computer(), unrelated = UUID()
        store.addDevice(device); store.addDevice(other)
        keyboards.save(KeyboardToolbarConfiguration(), for: device.id)
        keyboards.save(KeyboardToolbarConfiguration(), for: other.id)
        keyboards.save(KeyboardToolbarConfiguration(), for: unrelated)
        try store.selectStorage(.iCloud)
        let untouched = keyboards.savedData(for: other.id), temporary = keyboards.savedData(for: unrelated)
        var remote = try document(store)
        try remote.recordLocalDevices([other])
        _ = try store.synchronizationReplica().receiveDocuments([remote.encoded()])
        XCTAssertNil(keyboards.savedData(for: device.id))
        XCTAssertEqual(keyboards.savedData(for: other.id), untouched)
        XCTAssertEqual(keyboards.savedData(for: unrelated), temporary)
        XCTAssertNil(store.device(withID: device.id))
        XCTAssertNil(try document(store).keyboardConfigurations[device.id])
        XCTAssertNotNil(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key))
    }

    @MainActor
    func testInvalidFetchedBatchAppliesNoNativePreferenceOrLibraryChanges() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var remote = try document(store)
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [device.id: KeyboardToolbarConfiguration()])
        let before = defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)
        XCTAssertThrowsError(try store.synchronizationReplica().receiveDocuments([remote.encoded(), Data("invalid".utf8)]))
        XCTAssertNil(keyboards.savedData(for: device.id))
        XCTAssertNil(defaults.object(forKey: AppLocalization.preferenceKey))
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), before)
        XCTAssertEqual(store.devicesSnapshot(), [device])
    }

    @MainActor
    func testInterruptedMirrorRecoversEachOldKeyButPreservesLaterNativeEdits() throws {
        let (store, defaults, keyboards) = try library()
        let first = computer(), second = computer(); store.addDevice(first); store.addDevice(second)
        defaults.set("en", forKey: AppLocalization.preferenceKey)
        keyboards.save(KeyboardToolbarConfiguration(), for: first.id)
        keyboards.save(KeyboardToolbarConfiguration(), for: second.id)
        try store.selectStorage(.iCloud)
        let oldFirst = keyboards.savedData(for: first.id)
        var remote = try document(store)
        var remoteFirst = keyboards.load(for: first.id); remoteFirst.position = .top
        var remoteSecond = keyboards.load(for: second.id); remoteSecond.position = .top
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [first.id: remoteFirst, second.id: remoteSecond])
        _ = try store.synchronizationReplica().receiveDocuments([remote.encoded()])
        defaults.set("en", forKey: AppLocalization.preferenceKey)
        defaults.set(oldFirst, forKey: KeyboardToolbarStore.keyPrefix + first.id.uuidString)
        var newerSecond = remoteSecond; newerSecond.size = .large
        defaults.set(try JSONEncoder().encode(newerSecond), forKey: KeyboardToolbarStore.keyPrefix + second.id.uuidString)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppLocalization.preferenceKey), "zh-Hans")
        XCTAssertEqual(keyboards.load(for: first.id), remoteFirst)
        XCTAssertEqual(keyboards.load(for: second.id), newerSecond)
        XCTAssertEqual(try document(restarted).keyboardConfigurations[second.id], newerSecond)
        XCTAssertEqual(try document(restarted).applicationLanguage, .simplifiedChinese)
    }

    @MainActor
    func testSelectingLocalDoesNotReplayOldCloudPreferencesAfterNativeEditsAndRestart() throws {
        let previousLanguage = AppLocalization.language
        defer { AppLocalization.select(previousLanguage) }
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var remote = try document(store)
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [device.id: KeyboardToolbarConfiguration()])
        _ = try store.synchronizationReplica().receiveDocuments([remote.encoded()])
        try store.selectStorage(.local)
        let settings = AppLanguageSettings(defaults: defaults); settings.language = .english
        var config = keyboards.load(for: device.id); config.size = .large
        keyboards.save(config, for: device.id)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(restarted.storageMode, .local)
        XCTAssertEqual(defaults.string(forKey: AppLocalization.preferenceKey), "en")
        XCTAssertEqual(keyboards.load(for: device.id), config)
        try restarted.selectStorage(.iCloud)
        XCTAssertEqual(try document(restarted).applicationLanguage, .english)
        XCTAssertEqual(try document(restarted).keyboardConfigurations[device.id], config)
    }

    @MainActor
    func testCorruptNativePreferencePreservesLocalDeviceEditsAndCanBeCorrected() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        let invalid = Data("broken local preference".utf8)
        defaults.set(invalid, forKey: KeyboardToolbarStore.keyPrefix + device.id.uuidString)
        var edited = device; edited.name = "Preserved local edit"; store.updateDevice(edited)
        XCTAssertEqual(TestStorage.make(userDefaults: defaults).devicesSnapshot(), [edited])
        XCTAssertEqual(keyboards.savedData(for: device.id), invalid)
        XCTAssertThrowsError(try store.synchronizationReplica().exportedData())
        keyboards.save(KeyboardToolbarConfiguration(), for: device.id)
        XCTAssertEqual(try document(store).devices(retainingLocalState: store.devicesSnapshot()), [edited])
        XCTAssertNil(store.synchronizationFailure)
    }

    @MainActor
    func testRetainedLanguageAndSessionRefreshWithoutSavingOrReconnecting() async throws {
        let previousLanguage = AppLocalization.language
        defer { AppLocalization.select(previousLanguage) }
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device)
        let language = AppLanguageSettings(defaults: defaults)
        let session = TestSession.make(device: device, password: nil, deviceStore: store, keyboardStore: keyboards)
        let temporary = TestSession.make(device: device, password: nil, isTemporary: true, deviceStore: store, keyboardStore: keyboards)
        let temporaryConfiguration = temporary.keyboardConfiguration
        let client = session.client, inputGeneration = session.inputGeneration
        try store.selectStorage(.iCloud)
        var remote = try document(store)
        var configuration = KeyboardToolbarConfiguration(); configuration.size = .large; configuration.normalize()
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [device.id: configuration])
        _ = try store.synchronizationReplica().receiveDocuments([remote.encoded()])
        let before = try store.synchronizationReplica().exportedData()
        await settle()
        XCTAssertEqual(language.language, .simplifiedChinese)
        XCTAssertEqual(session.keyboardConfiguration, configuration)
        XCTAssertTrue(session.client === client)
        XCTAssertEqual(session.inputGeneration, inputGeneration)
        XCTAssertEqual(temporary.keyboardConfiguration, temporaryConfiguration)
        XCTAssertEqual(try store.synchronizationReplica().exportedData(), before, "Remote refresh must not create a local preference edit")
    }

    @MainActor
    func testLanguageOnlyImportDoesNotRegenerateUnsavedSessionToolbarIDs() async throws {
        let (store, _, keyboards) = try library()
        let device = computer(); store.addDevice(device)
        let session = TestSession.make(device: device, password: nil, deviceStore: store, keyboardStore: keyboards)
        let items = session.keyboardConfiguration.items
        try store.selectStorage(.iCloud)
        var remote = try document(store); try remote.recordLocalPreferences(language: .english, keyboards: [:])
        _ = try store.synchronizationReplica().receiveDocuments([remote.encoded()])
        await settle()
        XCTAssertEqual(session.keyboardConfiguration.items, items)
        XCTAssertNil(keyboards.savedData(for: device.id))
    }

    @MainActor
    func testStaleLibraryWriterCannotApplyFetchedNativePreferences() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        let stale = TestStorage.make(userDefaults: defaults)
        var remote = try document(stale)
        try remote.recordLocalPreferences(language: .simplifiedChinese, keyboards: [device.id: KeyboardToolbarConfiguration()])
        var edited = device; edited.name = "Current writer"; store.updateDevice(edited)
        let checkpoint = defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)
        XCTAssertThrowsError(try stale.synchronizationReplica().receiveDocuments([remote.encoded()])) {
            XCTAssertEqual($0 as? DeviceSyncDocument.Failure, .staleLocalReplica)
        }
        XCTAssertNil(keyboards.savedData(for: device.id))
        XCTAssertNil(defaults.object(forKey: AppLocalization.preferenceKey))
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), checkpoint)
    }

    @MainActor
    func testOlderCheckpointCapturesExistingNativeOverridesWithoutGeneratingDefaults() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var checkpoint = try DeviceLibrarySyncCheckpoint(data: XCTUnwrap(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)))
        checkpoint.preferencesData = nil; checkpoint.previousPreferencesData = nil
        defaults.set(try checkpoint.encoded(), forKey: DeviceLibrarySyncCheckpoint.key)
        var config = KeyboardToolbarConfiguration(); config.size = .small; config.normalize()
        defaults.set(try JSONEncoder().encode(config), forKey: KeyboardToolbarStore.keyPrefix + device.id.uuidString)
        defaults.set("zh-Hans", forKey: AppLocalization.preferenceKey)
        let restarted = TestStorage.make(userDefaults: defaults)
        let migrated = try document(restarted)
        XCTAssertEqual(migrated.keyboardConfigurations[device.id], config)
        XCTAssertEqual(migrated.applicationLanguage, .simplifiedChinese)
        XCTAssertEqual(keyboards.load(for: device.id), config)
        XCTAssertEqual(try restarted.synchronizationReplica().exportedData(), try migrated.encoded())
    }

    @MainActor
    func testMismatchedPreferenceCheckpointIsPreservedAndCannotImportOrResetNativeData() throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        var checkpoint = try DeviceLibrarySyncCheckpoint(data: XCTUnwrap(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key)))
        checkpoint.preferencesData = try DevicePreferenceSnapshot(language: .simplifiedChinese,
            keyboards: [device.id: KeyboardToolbarConfiguration()], scope: [device.id]).encoded()
        let corrupted = try checkpoint.encoded()
        defaults.set(corrupted, forKey: DeviceLibrarySyncCheckpoint.key)
        let restarted = TestStorage.make(userDefaults: defaults)
        XCTAssertEqual(restarted.synchronizationFailure, .invalidDocument)
        XCTAssertEqual(restarted.devicesSnapshot(), [device])
        XCTAssertNil(keyboards.savedData(for: device.id))
        XCTAssertNil(defaults.object(forKey: AppLocalization.preferenceKey))
        XCTAssertEqual(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key), corrupted)
        XCTAssertThrowsError(try restarted.selectStorage(.iCloud))
    }

    @MainActor
    func testControllerPublishesNativePreferenceEditWithoutRemoteFeedbackLoop() async throws {
        let (store, defaults, keyboards) = try library()
        let device = computer(); store.addDevice(device); try store.selectStorage(.iCloud)
        let transport = SyncTestTransport()
        let controller = DeviceLibrarySyncController(store: store, transportFactory: { transport }, debounceNanoseconds: 1_000_000)
        controller.resumeAutomaticSynchronization()
        await controller.synchronizeNow()
        let before = await transport.counts()
        var config = KeyboardToolbarConfiguration(); config.size = .large
        keyboards.save(config, for: device.id)
        for _ in 0..<100 {
            if await transport.counts().publish > before.publish, controller.status == .synchronized { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await settle()
        XCTAssertEqual(controller.status, .synchronized)
        let after = await transport.counts()
        XCTAssertEqual(after.publish, before.publish + 1)
        let replica = try store.synchronizationReplica()
        let bytes = await transport.uploaded(for: replica.replicaID)
        XCTAssertEqual(try DeviceSyncDocument(data: XCTUnwrap(bytes), replicaID: UUID()).keyboardConfigurations[device.id], keyboards.load(for: device.id))
        XCTAssertNotNil(defaults.data(forKey: DeviceLibrarySyncCheckpoint.key))
        controller.suspendAutomaticSynchronization()
    }
}
