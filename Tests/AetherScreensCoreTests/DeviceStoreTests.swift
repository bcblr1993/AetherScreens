import XCTest
import Combine
@testable import AetherScreensCore
@testable import AetherScreensSSH

final class DeviceStoreTests: XCTestCase {
    func testWidgetSavedRecordSnapshotSeesExternalSameIDEditWithoutLoadingOrCredentials() throws {
        let old = RemoteDevice(id: UUID(), name: "Widget snapshot QA", host: "old.qa.invalid")
        tempDefaults.set(try JSONEncoder().encode([old]), forKey: DeviceStore.storageKey)
        let passwords = ShortcutSnapshotPasswordSpy()
        let ssh = ShortcutSnapshotSSHSpy()
        let store = TestStorage.make(userDefaults: tempDefaults, passwordStore: passwords,
                                sshKeychain: SSHKeychainStore(backend: ssh))
        var edited = old
        edited.host = "new.qa.invalid"
        edited.port = 5901
        edited.username = "fixture-account"
        edited.authMethod = .macAccount
        tempDefaults.set(try JSONEncoder().encode([edited]), forKey: DeviceStore.storageKey)
        let before = tempDefaults.dictionaryRepresentation()
        XCTAssertEqual(store.device(withID: old.id)?.host, "old.qa.invalid")
        let current = try XCTUnwrap(store.verifiedSavedDevicesSnapshot()?.first)
        XCTAssertEqual(current.id, old.id)
        XCTAssertEqual(current.host, "new.qa.invalid")
        XCTAssertEqual(current.port, 5901)
        XCTAssertEqual(current.username, "fixture-account")
        XCTAssertEqual(current.authMethod, .macAccount)
        XCTAssertEqual(passwords.callCount, 0)
        XCTAssertEqual(ssh.callCount, 0)
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: tempDefaults.dictionaryRepresentation()))
    }

    func testWidgetSavedRecordSnapshotRejectsDamagedCheckpointDespiteVisibleLegacyRecord() throws {
        let device = RemoteDevice(id: UUID(), name: "Widget damaged QA", host: "qa.invalid")
        tempDefaults.set(try JSONEncoder().encode([device]), forKey: DeviceStore.storageKey)
        tempDefaults.set(Data("invalid checkpoint".utf8), forKey: DeviceLibrarySyncCheckpoint.key)
        let passwords = ShortcutSnapshotPasswordSpy()
        let ssh = ShortcutSnapshotSSHSpy()
        let store = TestStorage.make(userDefaults: tempDefaults, passwordStore: passwords,
                                sshKeychain: SSHKeychainStore(backend: ssh))
        XCTAssertEqual(store.device(withID: device.id)?.id, device.id)
        let before = tempDefaults.dictionaryRepresentation()
        XCTAssertNil(store.verifiedSavedDevicesSnapshot())
        XCTAssertNil(store.shortcutPruningSnapshot())
        XCTAssertEqual(passwords.callCount, 0)
        XCTAssertEqual(ssh.callCount, 0)
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: tempDefaults.dictionaryRepresentation()))
    }

    @MainActor
    func testShortcutPruningSnapshotValidSavedListIsMetadataOnly() throws {
        let first = RemoteDevice(id: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!, name: "Snapshot one QA", host: "one.qa.invalid")
        let second = RemoteDevice(id: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!, name: "Snapshot two QA", host: "two.qa.invalid")
        let encoded = try JSONEncoder().encode([first, second])
        tempDefaults.set(encoded, forKey: DeviceStore.storageKey)
        let passwords = ShortcutSnapshotPasswordSpy()
        let ssh = ShortcutSnapshotSSHSpy()
        let store = TestStorage.make(userDefaults: tempDefaults, passwordStore: passwords, sshKeychain: SSHKeychainStore(backend: ssh))
        let before = tempDefaults.dictionaryRepresentation()
        let ids = try XCTUnwrap(store.shortcutPruningSnapshot())
        XCTAssertEqual(ids, [first.id, second.id])
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: tempDefaults.dictionaryRepresentation()))
        XCTAssertEqual(passwords.callCount, 0)
        XCTAssertEqual(ssh.callCount, 0)
        let missing = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let projectionData = try JSONEncoder().encode(ShortcutCatalog(entries: [
            .init(id: first.id, alias: "First slot"), .init(id: second.id, alias: "Second slot"), .init(id: missing, alias: "Removed slot")
        ]))
        var writes: [Data] = []
        let projection = ShortcutCatalogStore(readData: { projectionData }, writeData: { writes.append($0) })
        projection.prune(availableIDs: ids)
        XCTAssertEqual(Set(projection.catalog.entries.map(\.id)), ids)
        XCTAssertEqual(writes.count, 1)
    }

    @MainActor
    func testShortcutPruningSnapshotExplicitLastDeletionReturnsVerifiedEmptySet() throws {
        let device = RemoteDevice(id: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!, name: "Last snapshot QA", host: "last.qa.invalid")
        let passwords = ShortcutSnapshotPasswordSpy()
        let ssh = ShortcutSnapshotSSHSpy()
        let store = TestStorage.make(userDefaults: tempDefaults, passwordStore: passwords, sshKeychain: SSHKeychainStore(backend: ssh))
        XCTAssertNil(store.shortcutPruningSnapshot(), "Missing metadata is not a verified empty library")
        store.addDevice(device)
        XCTAssertEqual(store.shortcutPruningSnapshot(), [device.id])
        XCTAssertTrue(store.deleteDevice(device))
        let bytes = try XCTUnwrap(tempDefaults.data(forKey: DeviceStore.storageKey))
        XCTAssertTrue(try JSONDecoder().decode([RemoteDevice].self, from: bytes).isEmpty)
        let passwordCalls = passwords.callCount
        let sshCalls = ssh.callCount
        let ids = try XCTUnwrap(store.shortcutPruningSnapshot())
        XCTAssertTrue(ids.isEmpty)
        XCTAssertEqual(tempDefaults.data(forKey: DeviceStore.storageKey), bytes)
        XCTAssertEqual(passwords.callCount, passwordCalls)
        XCTAssertEqual(ssh.callCount, sshCalls)
        let projectionData = try JSONEncoder().encode(ShortcutCatalog(entries: [.init(id: device.id, alias: "Last slot")]))
        var writes: [Data] = []
        let projection = ShortcutCatalogStore(readData: { projectionData }, writeData: { writes.append($0) })
        projection.prune(availableIDs: ids)
        XCTAssertTrue(projection.catalog.entries.isEmpty)
        XCTAssertEqual(writes.count, 1)
    }

    @MainActor
    func testShortcutPruningSnapshotDamagedOrUnknownMetadataPreservesProjection() throws {
        let device = RemoteDevice(id: UUID(uuidString: "00000000-0000-4000-8000-000000000121")!, name: "Recoverable snapshot QA", host: "recover.qa.invalid")
        let validList = try JSONEncoder().encode([device])
        let emptyList = try JSONEncoder().encode([RemoteDevice]())
        var unknown = try DeviceLibrarySyncCheckpoint(storage: .local, devices: [device])
        unknown.version = 999
        var damaged = try DeviceLibrarySyncCheckpoint(storage: .local, devices: [device])
        damaged.documentData = Data("invalid document".utf8)
        let mismatch = try DeviceLibrarySyncCheckpoint(storage: .local, devices: [device])
        let fixtures: [(Any?, Any?)] = [
            (nil, nil), ("[]", nil), (Data(), nil), (Data("invalid library".utf8), nil),
            (Data("{}".utf8), nil), (try JSONEncoder().encode([device, device]), nil),
            (validList, "invalid checkpoint type"), (emptyList, Data("invalid checkpoint".utf8)),
            (validList, try unknown.encoded()), (validList, try damaged.encoded()),
            (emptyList, try mismatch.encoded())
        ]
        let projectionData = try JSONEncoder().encode(ShortcutCatalog(entries: [.init(id: device.id, alias: "Keep this slot")]))
        var writes: [Data] = []
        let projection = ShortcutCatalogStore(readData: { projectionData }, writeData: { writes.append($0) })
        for (index, fixture) in fixtures.enumerated() {
            tempDefaults.removeObject(forKey: DeviceStore.storageKey)
            tempDefaults.removeObject(forKey: DeviceLibrarySyncCheckpoint.key)
            if let legacy = fixture.0 { tempDefaults.set(legacy, forKey: DeviceStore.storageKey) }
            if let checkpoint = fixture.1 { tempDefaults.set(checkpoint, forKey: DeviceLibrarySyncCheckpoint.key) }
            let passwords = ShortcutSnapshotPasswordSpy()
            let ssh = ShortcutSnapshotSSHSpy()
            let store = TestStorage.make(userDefaults: tempDefaults, passwordStore: passwords, sshKeychain: SSHKeychainStore(backend: ssh))
            let before = tempDefaults.dictionaryRepresentation()
            let ids = store.shortcutPruningSnapshot()
            XCTAssertNil(ids, "Fixture \(index)")
            if let ids { projection.prune(availableIDs: ids) }
            XCTAssertEqual(projection.catalog.entries.map(\.id), [device.id], "Fixture \(index)")
            XCTAssertTrue(writes.isEmpty, "Fixture \(index)")
            XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: tempDefaults.dictionaryRepresentation()), "Fixture \(index)")
            XCTAssertEqual(passwords.callCount, 0, "Fixture \(index)")
            XCTAssertEqual(ssh.callCount, 0, "Fixture \(index)")
        }
    }

    func testCompressionPreferencePersistsWithoutOverwritingEditsOrRevivingStaleTargets() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Compression QA", host: "qa.invalid")
        store.addDevice(original)
        var edited = original; edited.name = "Renamed QA"; edited.cursorSpeed = 1.75
        store.updateDevice(edited)
        store.updateImageCompression(.always, for: original)
        let saved = try XCTUnwrap(makeStore().device(withID: original.id))
        XCTAssertEqual(saved.imageCompression, .always)
        XCTAssertEqual(saved.name, edited.name)
        XCTAssertEqual(saved.cursorSpeed, 1.75)
        store.updateImageCompression(.never, for: original)
        XCTAssertNil(makeStore().device(withID: original.id)?.imageCompression)
        edited.host = "changed.qa.invalid"; store.updateDevice(edited)
        store.updateImageCompression(.remoteOnly, for: original)
        XCTAssertNil(store.device(withID: original.id)?.imageCompression)
        store.deleteDevice(edited); store.updateImageCompression(.always, for: edited)
        XCTAssertNil(store.device(withID: edited.id))
    }
    func testChangingSavedEndpointClearsServerSpecificDisplayPreference() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Display endpoint QA", host: "qa.invalid", preferredDisplayID: 9)
        store.addDevice(original)
        var edited = original
        edited.name = "Renamed computer"
        store.updateDevice(edited)
        XCTAssertEqual(makeStore().device(withID: original.id)?.preferredDisplayID, 9)
        edited.host = "other.qa.invalid"
        store.updateDevice(edited)
        XCTAssertNil(makeStore().device(withID: original.id)?.preferredDisplayID,
                     "A screen ID from the old server must not select a monitor on the new endpoint")
        store.updatePreferredDisplay(9, for: original)
        XCTAssertNil(store.device(withID: original.id)?.preferredDisplayID,
                     "A stale session must not restore the previous server's choice")
    }

    func testPreferredDisplayPersistenceMergesWithoutRestoringEditedOrDeletedEndpoints() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Display QA", host: "qa.invalid")
        XCTAssertNil(try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(original)).preferredDisplayID)
        store.addDevice(original)
        var edited = original
        edited.name = "Edited display target"
        edited.cursorSpeed = 1.5
        store.updateDevice(edited)
        store.updatePreferredDisplay(UInt32.max, for: original)
        let loaded = try XCTUnwrap(makeStore().device(withID: original.id))
        XCTAssertEqual(loaded.preferredDisplayID, UInt32.max)
        XCTAssertEqual(loaded.name, edited.name)
        XCTAssertEqual(loaded.cursorSpeed, edited.cursorSpeed)
        store.updatePreferredDisplay(0, for: original)
        XCTAssertEqual(makeStore().device(withID: original.id)?.preferredDisplayID, 0)
        store.updatePreferredDisplay(nil, for: original)
        XCTAssertNil(makeStore().device(withID: original.id)?.preferredDisplayID)
        edited.port = 5999
        store.updateDevice(edited)
        store.updatePreferredDisplay(UInt32.max, for: original)
        XCTAssertNil(store.device(withID: original.id)?.preferredDisplayID)
        store.deleteDevice(edited)
        store.updatePreferredDisplay(0, for: original)
        XCTAssertNil(store.device(withID: original.id))
    }

    @MainActor
    func testSessionRestoresReportedMonitorAndOnlySavedExplicitChoicesPersist() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Display session QA", host: "qa.invalid", preferredDisplayID: 9)
        store.addDevice(original)
        let layout = RFBDisplayLayout(width: 4, height: 2, screens: [
            .init(id: 0, x: 0, y: 0, width: 2, height: 2, flags: 0),
            .init(id: 9, x: 2, y: 0, width: 2, height: 2, flags: 0)
        ])
        let session = TestSession.make(device: original, password: nil, deviceStore: store)
        session.client.framebuffer.resize(newWidth: 4, newHeight: 2)
        func drain() {
            let settled = expectation(description: "Display selection callbacks drained")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { settled.fulfill() }
            wait(for: [settled], timeout: 1)
        }
        session.client.onDisplayLayoutReceived?(layout)
        drain()
        XCTAssertEqual(session.activeCropRect, CGRect(x: 2, y: 0, width: 2, height: 2))
        XCTAssertEqual(session.multiDisplayManager.selectedDisplayId, 10)
        session.selectDisplay(id: 1)
        drain()
        let saved = try XCTUnwrap(makeStore().device(withID: original.id))
        XCTAssertEqual(saved.preferredDisplayID, 0)
        XCTAssertEqual(session.activeCropRect, CGRect(x: 0, y: 0, width: 2, height: 2))
        session.selectDisplay(id: 999)
        XCTAssertEqual(store.device(withID: original.id)?.preferredDisplayID, 0)
        let temporary = TestSession.make(device: saved, password: nil, isTemporary: true, deviceStore: store)
        temporary.multiDisplayManager.updateFromLayout(layout)
        temporary.selectDisplay(id: 0)
        XCTAssertEqual(store.device(withID: original.id)?.preferredDisplayID, 0, "A temporary session must not change saved selection")
        session.selectDisplay(id: 0)
        XCTAssertNil(makeStore().device(withID: original.id)?.preferredDisplayID)
        store.deleteDevice(original)
        session.selectDisplay(id: 10)
        XCTAssertNil(store.device(withID: original.id), "A stale session must not resurrect a deleted target")
        session.endSession()
        temporary.endSession()
    }

    func testSharedClipboardDefaultsAndMergePreserveNewerEditsAndDeletedTargets() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Clipboard QA", host: "127.0.0.1")
        XCTAssertTrue(original.effectiveSharedClipboard)
        let legacy = try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.sharedClipboard)
        XCTAssertTrue(legacy.effectiveSharedClipboard)
        store.addDevice(original)
        var latest = original
        latest.name = "Edited name"
        latest.cursorSpeed = 2
        store.updateDevice(latest)
        store.updateSharedClipboard(false, for: original)
        let loaded = try XCTUnwrap(makeStore().device(withID: original.id))
        XCTAssertFalse(loaded.effectiveSharedClipboard)
        XCTAssertEqual(loaded.name, latest.name)
        XCTAssertEqual(loaded.cursorSpeed, 2)
        store.updateSharedClipboard(true, for: original)
        XCTAssertNil(store.device(withID: original.id)?.sharedClipboard)
        latest.host = "127.0.0.2"
        store.updateDevice(latest)
        store.updateSharedClipboard(false, for: original)
        XCTAssertTrue(try XCTUnwrap(store.device(withID: original.id)).effectiveSharedClipboard)
        store.deleteDevice(original)
        store.updateSharedClipboard(false, for: original)
        XCTAssertNil(store.device(withID: original.id))
    }

    func testCursorSpeedPreservesNewEditsAndDoesNotRestoreChangedOrDeletedTargets() throws {
        let store = makeStore()
        let original = RemoteDevice(name: "Speed QA", host: "127.0.0.1")
        store.addDevice(original)
        var edited = original
        edited.name = "New name"
        edited.disconnectAction = .lockScreen
        edited.macAddress = "AA:BB:CC:DD:EE:FF"
        store.updateDevice(edited)
        store.updateCursorSpeed(2, for: original)
        let loaded = try XCTUnwrap(makeStore().device(withID: original.id))
        XCTAssertEqual(loaded.effectiveCursorSpeed, 2)
        XCTAssertEqual(loaded.name, edited.name)
        XCTAssertEqual(loaded.disconnectAction, .lockScreen)
        XCTAssertEqual(loaded.macAddress, edited.macAddress)
        edited.host = "127.0.0.2"
        store.updateDevice(edited)
        store.updateCursorSpeed(1.5, for: original)
        XCTAssertEqual(store.device(withID: original.id)?.effectiveCursorSpeed, 1)
        store.deleteDevice(original)
        store.updateCursorSpeed(2, for: original)
        XCTAssertNil(store.device(withID: original.id))
        let legacy = try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.cursorSpeed)
        XCTAssertEqual(legacy.effectiveCursorSpeed, 1)
    }


    var tempDefaults: UserDefaults!
    var suiteName: String!
    var keychain: KeychainStore!
    var legacyKeychain: KeychainStore!
    var legacyServiceName: String!
    var currentServiceName: String!
    var keychainBackend: TestKeychainBackend!

    override func setUp() {
        super.setUp()
        suiteName = "test.aetherscreens.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
        legacyServiceName = "test.aetherscreens.legacy.\(UUID().uuidString)"
        currentServiceName = "test.aetherscreens.credentials.\(UUID().uuidString)"
        keychainBackend = TestKeychainBackend()
        keychain = KeychainStore(serviceName: currentServiceName,
                                 legacyServiceName: legacyServiceName, backend: keychainBackend)
        legacyKeychain = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil,
                                       backend: keychainBackend)
    }

    override func tearDown() {
        tempDefaults.removePersistentDomain(forName: suiteName)
        tempDefaults = nil
        keychain = nil
        legacyKeychain = nil
        keychainBackend = nil
        super.tearDown()
    }

    private func makeStore(legacySources: [UserDefaults] = []) -> DeviceStore {
        TestStorage.make(userDefaults: tempDefaults, legacySources: legacySources, keychain: keychain)
    }

    func testLegacyDevicesAndUnknownDisconnectActionsKeepConnections() throws {
        let oldJSON = Data("""
        [{"id":"00000000-0000-0000-0000-000000000017","name":"Legacy Mac","host":"qa.invalid","port":5900,"deviceType":"macOS","authMethod":"VNC Password","isOnline":true,"isTailscaleNode":false}]
        """.utf8)
        tempDefaults.set(oldJSON, forKey: DeviceStore.storageKey)
        let store = makeStore()
        XCTAssertEqual(store.devices.count, 1)
        var device = try XCTUnwrap(store.devices.first)
        XCTAssertNil(device.disconnectAction)
        device.disconnectAction = .lockScreen
        store.updateDevice(device)
        XCTAssertEqual(makeStore().devices.first?.disconnectAction, .lockScreen)
        let unknownJSON = String(decoding: oldJSON, as: UTF8.self).replacingOccurrences(of: "\"isOnline\":true", with: "\"disconnectAction\":\"future-action\",\"isOnline\":true")
        tempDefaults.set(Data(unknownJSON.utf8), forKey: DeviceStore.storageKey)
        let restored = makeStore()
        XCTAssertEqual(restored.devices.count, 1)
        XCTAssertEqual(restored.devices.first?.host, "qa.invalid")
        XCTAssertEqual(restored.devices.first?.disconnectAction, .disconnectOnly)
    }

    @MainActor
    func testEndingSessionRejectsAlreadyQueuedFrameAndConnectionNotifications() {
        let store = makeStore()
        let device = RemoteDevice(name: "Ended callback QA", host: "qa.invalid")
        store.addDevice(device)
        let session = TestSession.make(device: device, password: nil, deviceStore: store)
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        session.client.onFrameUpdated?()
        session.client.onDownloadProgress?(1, 2)
        session.client.onStateChanged?(.connected)
        session.endSession()
        let drained = expectation(description: "Queued old callbacks drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertFalse(session.hasReceivedFirstFrame)
        XCTAssertNil(session.downloadProgress)
        XCTAssertNil(store.devices.first { $0.id == device.id }?.lastConnected)
        XCTAssertEqual(session.sessionState, .disconnected)
    }

    @MainActor
    func testEndedSessionRejectsQueuedPasswordPrompts() {
        let session = TestSession.make(device: RemoteDevice(name: "Ended prompt QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
        let passwordCancelled = expectation(description: "Old password prompt cancelled")
        let accountCancelled = expectation(description: "Old account prompt cancelled")
        session.client.onRequestPassword? { password in XCTAssertNil(password); passwordCancelled.fulfill() }
        session.client.onRequestMacAccount? { account, password in
            XCTAssertNil(account); XCTAssertNil(password); accountCancelled.fulfill()
        }
        session.endSession()
        wait(for: [passwordCancelled, accountCancelled], timeout: 2)
        XCTAssertFalse(session.isPromptingPassword)
    }

    @MainActor
    func testObserveModeChangeAndEndClearHeldTrackpadButtons() {
        let session = TestSession.make(device: RemoteDevice(name: "Held input QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
        session.trackpadEngine.beginDrag(button: [.left, .right])
        session.isObserveOnly = true
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        session.isObserveOnly = false
        session.trackpadEngine.beginDrag()
        session.inputMode = .touch
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        session.trackpadEngine.beginDrag()
        session.isPanningViewport = true
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        session.isPanningViewport = false
        session.trackpadEngine.beginDrag()
        session.endSession()
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
    }

    @MainActor
    func testServerDisplayLayoutUpdatesCropAndRejectsEndedSessionCallbacks() {
        let session = TestSession.make(device: RemoteDevice(name: "Display layout QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
        session.client.framebuffer.resize(newWidth: 4, newHeight: 2)
        let layout = RFBDisplayLayout(width: 4, height: 2, screens: [
            .init(id: 0, x: 2, y: 0, width: 2, height: 2, flags: 0)
        ])
        func drain() {
            let settled = expectation(description: "Display UI callbacks drained")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { settled.fulfill() }
            wait(for: [settled], timeout: 1)
        }
        session.client.onDisplayLayoutReceived?(layout)
        session.client.onFrameUpdated?()
        drain()
        XCTAssertEqual(session.multiDisplayManager.availableDisplays.count, 2)
        session.multiDisplayManager.selectDisplay(id: 1)
        drain()
        XCTAssertEqual(session.activeCropRect, CGRect(x: 2, y: 0, width: 2, height: 2))
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 2)
        session.zoomScale = 2
        session.isPanningViewport = true
        session.viewOffset = CGSize(width: 10, height: 10)
        session.client.onDisplayLayoutReceived?(.init(width: 4, height: 2, screens: []))
        drain()
        XCTAssertNil(session.activeCropRect)
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 4)
        XCTAssertEqual(session.zoomScale, 1)
        XCTAssertEqual(session.viewOffset, .zero)
        XCTAssertFalse(session.isPanningViewport, "Returning to an unzoomed desktop must restore pointer control")
        session.client.onDisplayLayoutReceived?(layout)
        session.endSession()
        drain()
        XCTAssertEqual(session.multiDisplayManager.availableDisplays.count, 1, "An ended session must not restore stale server monitor choices")
    }

    @MainActor
    func testRepeatedFramesDoNotRepublishUnchangedCanvasAndDisplayState() throws {
        let session = TestSession.make(device: RemoteDevice(name: "Frame state QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
        guard session.metalRenderer != nil else { throw XCTSkip("Requires a Metal device") }
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        var frameStateChanges = 0
        var displayChanges = 0
        let frameSubscription = session.$hasReceivedFirstFrame.dropFirst().sink { _ in frameStateChanges += 1 }
        let displaySubscription = session.multiDisplayManager.$availableDisplays.dropFirst().sink { _ in displayChanges += 1 }
        for _ in 0..<120 { session.client.onFrameUpdated?() }
        let drained = expectation(description: "Main actor frame notifications drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(session.hasReceivedFirstFrame)
        XCTAssertEqual(frameStateChanges, 1, "Incoming frames must not repeatedly invalidate the whole SwiftUI canvas")
        XCTAssertEqual(displayChanges, 1, "Unchanged display geometry must not be rebuilt for every frame")
        var resizeNotifications = 0
        let resizeSubscription = session.objectWillChange.sink { resizeNotifications += 1 }
        session.client.framebuffer.resize(newWidth: 4, newHeight: 2)
        session.client.onFrameUpdated?()
        let resized = expectation(description: "Remote display resize delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { resized.fulfill() }
        wait(for: [resized], timeout: 2)
        XCTAssertEqual(resizeNotifications, 1, "A real remote size change must still refresh canvas geometry")
        XCTAssertEqual(displayChanges, 2)
        resizeSubscription.cancel()
        frameSubscription.cancel()
        displaySubscription.cancel()
    }

    @MainActor
    func testStreamingProgressDoesNotInvalidateVisibleDesktop() {
        let session = TestSession.make(device: RemoteDevice(name: "Streaming QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        session.client.onDownloadProgress?(1, 4)
        let loading = expectation(description: "Initial progress delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { loading.fulfill() }
        wait(for: [loading], timeout: 2)
        XCTAssertEqual(session.downloadProgress?.current, 1)
        session.client.onFrameUpdated?()
        let firstFrame = expectation(description: "First frame delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { firstFrame.fulfill() }
        wait(for: [firstFrame], timeout: 2)
        XCTAssertTrue(session.hasReceivedFirstFrame)
        var progressChanges = 0
        let subscription = session.$downloadProgress.dropFirst().sink { _ in progressChanges += 1 }
        for _ in 0..<120 {
            session.client.onDownloadProgress?(2, 4)
            session.client.onFrameUpdated?()
        }
        let streaming = expectation(description: "Streaming callbacks drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { streaming.fulfill() }
        wait(for: [streaming], timeout: 2)
        XCTAssertNil(session.downloadProgress)
        XCTAssertEqual(progressChanges, 0, "Loading progress must not rebuild the visible desktop during streaming")
        subscription.cancel()
    }

    @MainActor
    func testInteractiveMacAccountPersistsOnlyForSavedDevice() {
        for temporary in [false, true] {
            let store = makeStore()
            let device = RemoteDevice(name: "Account prompt QA", host: "qa.invalid")
            if !temporary { store.addDevice(device) }
            let session = TestSession.make(device: device, password: nil, isTemporary: temporary, deviceStore: store)
            let prompt = expectation(description: "Account prompt presented")
            let submitted = expectation(description: "Entered account submitted")
            let subscription = session.$isPromptingPassword.sink { if $0 { prompt.fulfill() } }
            session.client.onRequestMacAccount? { account, password in
                XCTAssertEqual(account, "qa-account")
                XCTAssertEqual(password, "test-secret")
                submitted.fulfill()
            }
            wait(for: [prompt], timeout: 2)
            XCTAssertTrue(session.requiresMacAccountPrompt)
            session.submitPassword("test-secret", rememberInKeychain: true, accountUsername: " ")
            XCTAssertTrue(session.isPromptingPassword)
            session.submitPassword("test-secret", rememberInKeychain: true, accountUsername: " qa-account ")
            wait(for: [submitted], timeout: 2)
            XCTAssertFalse(session.isPromptingPassword)
            if temporary {
                XCTAssertFalse(store.devices.contains { $0.id == device.id })
                XCTAssertNil(store.getPassword(for: device))
            } else {
                XCTAssertEqual(store.devices.first { $0.id == device.id }?.username, "qa-account")
                XCTAssertEqual(store.devices.first { $0.id == device.id }?.authMethod, .macAccount)
                let saved = try! XCTUnwrap(store.device(withID: device.id))
                XCTAssertEqual(store.getPassword(for: saved), "test-secret")
                XCTAssertNil(store.getPassword(for: device), "The prior account snapshot cannot read the newly saved account credential")
                store.deleteDevice(device)
            }
            subscription.cancel()
        }
    }

    func testBonjourRepairKeepsAccountAndCredentialAndPreservesManualHosts() {
        let store = makeStore()
        let old = RemoteDevice(name: "工作 Mac", host: "工作-Mac.local.", authMethod: .macAccount, username: "qa-account")
        let manual = RemoteDevice(name: "工作 Mac", host: "192.0.2.20")
        store.addDevice(old, password: "test-secret")
        store.addDevice(manual)
        let discovered = DiscoveredMac(name: old.name, host: "real-host-2.local.", port: 5990)
        XCTAssertTrue(store.repairLegacyBonjourHosts(using: [discovered]))
        let repaired = store.devices.first { $0.id == old.id }
        XCTAssertEqual(repaired?.host, discovered.host)
        XCTAssertEqual(repaired?.port, 5990)
        XCTAssertEqual(repaired?.username, old.username)
        XCTAssertEqual(repaired?.authMethod, .macAccount)
        XCTAssertEqual(store.getPassword(for: repaired!), "test-secret")
        XCTAssertNil(store.getPassword(for: old), "A stale address snapshot must not read the repaired endpoint credential")
        XCTAssertEqual(store.devices.first { $0.id == manual.id }?.host, manual.host)
        XCTAssertFalse(store.repairLegacyBonjourHosts(using: [discovered]))
        store.loadDevices()
        XCTAssertEqual(store.devices.first { $0.id == old.id }?.host, discovered.host)
        store.deleteDevice(old)
    }

    @MainActor
    func testTemporarySessionDoesNotCacheDesktopThumbnail() throws {
        let device = RemoteDevice(name: "Temporary thumbnail QA", host: "qa.invalid")
        let thumbnails = try ThumbnailStore.makeTemporary()
        let session = TestSession.make(device: device, password: nil, isTemporary: true,
                                      deviceStore: makeStore(), thumbnailStore: thumbnails)
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        for _ in 0..<61 { session.client.onFrameUpdated?() }
        let drained = expectation(description: "Allow any asynchronous thumbnail write to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(session.hasReceivedFirstFrame, "Incoming frame callbacks must have run")
        session.endSession()
        XCTAssertNil(thumbnails.getThumbnail(for: device.id), "A temporary desktop must not become a persistent preview")
    }

    @MainActor
    func testTemporarySessionDoesNotPersistDeviceOrRetriedPassword() throws {
        let store = makeStore()
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let request = try XCTUnwrap(ConnectionRequest(host: "qa.invalid", password: "temporary-only"))
        let session = try vm.prepareQuickSession(request, saveComputer: false)
        XCTAssertTrue(session.isTemporary)
        XCTAssertFalse(session.canRememberPassword)
        session.submitPassword("retry-only", rememberInKeychain: true)
        XCTAssertEqual(session.client.password, "retry-only", "Retry must update the active client, not only Keychain")
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(tempDefaults.data(forKey: DeviceStore.storageKey))
        XCTAssertNil(store.getPassword(for: request.device), "Temporary retry must not create an orphan credential")
    }

    @MainActor
    func testSavedQuickSessionPersistsDeviceAndAllowsPasswordRetry() throws {
        let store = makeStore()
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let vm = DeviceListViewModel(store: store, bonjourService: discovery)
        let request = try XCTUnwrap(ConnectionRequest(host: "qa.invalid", username: "qa-user", password: "initial-only"))
        defer { store.deleteDevice(request.device) }
        let session = try vm.prepareQuickSession(request, saveComputer: true)
        XCTAssertTrue(session.canRememberPassword)
        XCTAssertFalse(session.isTemporary)
        XCTAssertEqual(store.devices.first?.id, request.device.id)
        XCTAssertNil(store.devices.first?.lastConnected)
        XCTAssertEqual(store.getPassword(for: request.device), "initial-only")
        session.submitPassword("retry-only", rememberInKeychain: true)
        XCTAssertEqual(store.getPassword(for: request.device), "retry-only")
    }

    @MainActor
    func testConnectionAttemptDoesNotRecordSuccess() {
        let store = makeStore()
        let device = RemoteDevice(name: "Unverified Mac", host: "invalid.example")
        store.addDevice(device)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let viewModel = DeviceListViewModel(store: store, bonjourService: discovery)
        viewModel.connect(to: device)
        XCTAssertEqual(viewModel.activeSessionDevice?.id, device.id)
        XCTAssertNil(store.devices.first?.lastConnected, "Opening a session is not a successful connection")
    }

    func testAddAndRetrieveDevice() {
        let store = makeStore()
        let device = RemoteDevice(
            name: "Living Room Mac",
            host: "100.80.1.20",
            port: 5900,
            deviceType: .mac
        )

        store.addDevice(device, password: "testPassword123")
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.name, "Living Room Mac")

        // Password retrieval
        let retrievedPwd = store.getPassword(for: device)
        XCTAssertEqual(retrievedPwd, "testPassword123")
        store.deleteDevice(device)
    }

    func testDeleteDevice() {
        let store = makeStore()
        let device = RemoteDevice(name: "Test Mac", host: "100.80.1.30")
        store.addDevice(device, password: "secret")
        XCTAssertEqual(store.devices.count, 1)

        store.deleteDevice(device)
        XCTAssertEqual(store.devices.count, 0)
    }

    func testMergeTailscaleNodes() {
        let store = makeStore()

        let initialDevice = RemoteDevice(
            name: "My Work Mac",
            host: "100.80.10.5",
            isOnline: false
        )
        store.addDevice(initialDevice, password: "preservedPassword")

        // Tailscale returns updated status for the same IP
        let tsNode = TailscaleDevice(
            id: "node_abc",
            name: "work-mac.ts.net",
            hostname: "Work Mac Updated",
            addresses: ["100.80.10.5"],
            os: "macOS",
            connectedToControl: true
        )

        store.mergeTailscaleDevices([tsNode])

        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.devices.first?.name, "Work Mac Updated")
        XCTAssertTrue(store.devices.first?.isOnline ?? false)

        // Password should still be preserved
        let pwd = store.getPassword(for: store.devices.first!)
        XCTAssertEqual(pwd, "preservedPassword")
        store.deleteDevice(store.devices.first!)
    }

    func testMigratesLegacyDeviceListOnce() throws {
        let legacySuite = "test.aetherscreens.legacy-defaults.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }

        let legacyDevice = RemoteDevice(name: "Old Mac", host: "100.80.1.40")
        legacyDefaults.set(try JSONEncoder().encode([legacyDevice]), forKey: DeviceStore.legacyStorageKey)

        let store = makeStore(legacySources: [legacyDefaults])
        XCTAssertEqual(store.devices.map(\.id), [legacyDevice.id])
        XCTAssertNotNil(tempDefaults.data(forKey: DeviceStore.storageKey))
        // Legacy data stays for any old build still installed
        XCTAssertNotNil(legacyDefaults.data(forKey: DeviceStore.legacyStorageKey))

        // Once the current key exists, legacy data is not read again
        store.deleteDevice(legacyDevice)
        XCTAssertTrue(makeStore(legacySources: [legacyDefaults]).devices.isEmpty)
    }

    func testMigratesLegacyKeychainPasswordOnRead() {
        let device = RemoteDevice(name: "Old Mac", host: "100.80.1.41")
        let key = device.id.uuidString
        XCTAssertTrue(legacyKeychain.savePassword("legacySecret", forKey: key))

        let store = makeStore()
        store.addDevice(device)
        XCTAssertEqual(store.getPassword(for: device), "legacySecret")

        // Moved to the current service and removed from the legacy one
        let legacyReader = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil,
                                         backend: keychainBackend)
        XCTAssertNil(legacyReader.loadPassword(forKey: key))
        let currentReader = KeychainStore(serviceName: currentServiceName, legacyServiceName: nil,
                                          backend: keychainBackend)
        XCTAssertEqual(currentReader.loadPassword(forKey: key), "legacySecret")

        store.deleteDevice(device)
    }
}

private final class ShortcutSnapshotPasswordSpy: DevicePasswordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func savePassword(_ password: String, forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; calls += 1; return true
    }
    func loadPassword(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }; calls += 1; return nil
    }
    func deletePassword(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; calls += 1; return true
    }
}

private final class ShortcutSnapshotSSHSpy: SSHSecretBackend {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
    func read(account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }; calls += 1; return nil
    }
    func write(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }; calls += 1
    }
    func insert(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }; calls += 1
    }
    func delete(account: String) throws {
        lock.lock(); defer { lock.unlock() }; calls += 1
    }
}
