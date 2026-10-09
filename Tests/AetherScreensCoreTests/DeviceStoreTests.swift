import XCTest
import Combine
import Security
@testable import AetherScreensCore

final class DeviceStoreTests: XCTestCase {

    var tempDefaults: UserDefaults!
    var suiteName: String!
    var keychain: KeychainStore!
    var legacyKeychain: KeychainStore!
    var legacyServiceName: String!
    var currentServiceName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aetherscreens.\(UUID().uuidString)"
        tempDefaults = UserDefaults(suiteName: suiteName)!
        legacyServiceName = "test.aetherscreens.legacy.\(UUID().uuidString)"
        currentServiceName = "test.aetherscreens.credentials.\(UUID().uuidString)"
        keychain = KeychainStore(serviceName: currentServiceName,
                                 legacyServiceName: legacyServiceName)
        legacyKeychain = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil)
    }

    override func tearDown() {
        tempDefaults.removePersistentDomain(forName: suiteName)
        tempDefaults = nil
        keychain = nil
        legacyKeychain = nil
        super.tearDown()
    }

    private func makeStore(legacySources: [UserDefaults] = []) -> DeviceStore {
        DeviceStore(userDefaults: tempDefaults, legacySources: legacySources, keychain: keychain)
    }

    @MainActor
    func testTailscaleSyncRejectsReentryAndCancelledRequestsBeforeValidation() async {
        let model = DeviceListViewModel(store: makeStore())
        model.errorMessage = "Existing notice"
        model.isSyncingTailscale = true
        await model.syncTailscale()
        XCTAssertTrue(model.isSyncingTailscale, "A second request must not clear the first request's busy state")
        XCTAssertEqual(model.errorMessage, "Existing notice")
        model.isSyncingTailscale = false
        let task = Task { @MainActor in await model.syncTailscale() }
        task.cancel()
        await task.value
        XCTAssertFalse(model.isSyncingTailscale)
        XCTAssertEqual(model.errorMessage, "Existing notice")
    }

    @MainActor
    func testEndingSessionRejectsAlreadyQueuedFrameAndConnectionNotifications() {
        let store = makeStore()
        let device = RemoteDevice(name: "Ended callback QA", host: "qa.invalid")
        store.addDevice(device)
        let session = SessionViewModel(device: device, password: nil, deviceStore: store)
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
        let session = SessionViewModel(device: RemoteDevice(name: "Ended prompt QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
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
        let session = SessionViewModel(device: RemoteDevice(name: "Held input QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
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
        let session = SessionViewModel(device: RemoteDevice(name: "Display layout QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
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
        let session = SessionViewModel(device: RemoteDevice(name: "Frame state QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
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
        let session = SessionViewModel(device: RemoteDevice(name: "Streaming QA", host: "qa.invalid"), password: nil, isTemporary: true, deviceStore: makeStore())
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
            let session = SessionViewModel(device: device, password: nil, isTemporary: temporary, deviceStore: store)
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
                XCTAssertNil(store.getPassword(for: device), "Prior account configuration cannot retrieve the rebound password")
                XCTAssertEqual(store.getPassword(for: try XCTUnwrap(store.devices.first { $0.id == device.id })), "test-secret")
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
        XCTAssertEqual(store.getPassword(for: old), "test-secret")
        XCTAssertEqual(store.devices.first { $0.id == manual.id }?.host, manual.host)
        XCTAssertFalse(store.repairLegacyBonjourHosts(using: [discovered]))
        store.loadDevices()
        XCTAssertEqual(store.devices.first { $0.id == old.id }?.host, discovered.host)
        store.deleteDevice(old)
    }

    @MainActor
    func testTemporarySessionDoesNotCacheDesktopThumbnail() {
        let device = RemoteDevice(name: "Temporary thumbnail QA", host: "qa.invalid")
        let session = SessionViewModel(device: device, password: nil, isTemporary: true, deviceStore: makeStore())
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        for _ in 0..<61 { session.client.onFrameUpdated?() }
        let drained = expectation(description: "Allow any asynchronous thumbnail write to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(session.hasReceivedFirstFrame, "Incoming frame callbacks must have run")
        session.endSession()
        XCTAssertNil(ThumbnailStore.shared.getThumbnail(for: device.id), "A temporary desktop must not become a persistent preview")
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
    func testEndingSessionWithoutAFramePreservesPreviousDesktopPreview() throws {
        let device = RemoteDevice(name: "Unreceived frame QA", host: "qa.invalid")
        let session = SessionViewModel(device: device, password: nil, deviceStore: makeStore())
        defer { ThumbnailStore.shared.removeThumbnail(for: device.id) }
        session.client.framebuffer.resize(newWidth: 8, newHeight: 8)
        let previous = try XCTUnwrap(session.client.framebuffer.makeCGImage())
        ThumbnailStore.shared.saveThumbnail(previous, for: device.id)
        session.client.framebuffer.resize(newWidth: 2, newHeight: 2)
        XCTAssertFalse(session.hasReceivedFirstFrame)
        session.endSession()
        let drained = expectation(description: "Allow asynchronous snapshot work to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(ThumbnailStore.shared.getThumbnail(for: device.id)?.width, 8)
        XCTAssertEqual(ThumbnailStore.shared.getThumbnail(for: device.id)?.height, 8)
    }

    @MainActor
    func testLibraryModelIsReleasedWhileDiscoveryServiceRemainsAlive() {
        let store = makeStore()
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        weak var released: DeviceListViewModel?
        autoreleasepool {
            let model = DeviceListViewModel(store: store, bonjourService: discovery)
            released = model
            XCTAssertNotNil(released)
        }
        XCTAssertNil(released, "Discovery subscriptions must not keep a closed library alive")
        withExtendedLifetime(discovery) {}
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

    func testDeletingComputerRemovesOnlyItsDisplayQualityPreference() {
        let store = makeStore()
        let first = RemoteDevice(name: "First", host: "first.invalid")
        let second = RemoteDevice(name: "Second", host: "second.invalid")
        store.addDevice(first)
        store.addDevice(second)
        let quality = DisplayQualityStore(defaults: tempDefaults)
        quality.save(.rgb565, for: first.id)
        quality.save(.rgb565, for: second.id)
        let disconnect = DisconnectActionStore(defaults: tempDefaults)
        disconnect.save(.lockScreen, for: first.id)
        disconnect.save(.topRight, for: second.id)
        store.deleteDevice(first)
        XCTAssertEqual(quality.load(for: first.id), .fullColor)
        XCTAssertEqual(quality.load(for: second.id), .rgb565)
        XCTAssertEqual(disconnect.load(for: first.id, type: .mac), .none)
        XCTAssertEqual(disconnect.load(for: second.id, type: .mac), .topRight)
        XCTAssertEqual(store.devices.map(\.id), [second.id])
        store.deleteDevice(second)
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

    @MainActor
    func testLibrarySearchTrimsPastedWhitespaceAndPreservesDeviceOrder() {
        let store = makeStore()
        let first = RemoteDevice(name: "工作 Mac", host: "100.64.0.3")
        let second = RemoteDevice(name: "Studio", host: "192.168.50.226")
        store.addDevice(first)
        store.addDevice(second)
        let discovery = BonjourDiscoveryService()
        defer { discovery.stopDiscovery() }
        let model = DeviceListViewModel(store: store, bonjourService: discovery)
        let originalIDs = model.devices.map(\.id)
        model.searchText = " \nmac\t "
        XCTAssertEqual(model.filteredDevices.map(\.id), [first.id])
        model.searchText = " 192.168.50.226\n"
        XCTAssertEqual(model.filteredDevices.map(\.id), [second.id])
        model.searchText = "\t\n "
        XCTAssertEqual(model.filteredDevices.map(\.id), originalIDs)
        let nearby = DiscoveredMac(name: "Nearby Studio", host: "192.168.50.10")
        model.discoveredNearbyMacs = [nearby]
        model.searchText = "  studio\n"
        XCTAssertEqual(model.filteredNearbyMacs, [nearby])
        model.searchText = " 192.168.50.10 "
        XCTAssertEqual(model.filteredNearbyMacs, [nearby])
        model.searchText = "\t\n"
        XCTAssertEqual(model.filteredNearbyMacs, [nearby])
        XCTAssertTrue(model.normalizedSearchQuery.isEmpty)
        model.searchText = "does-not-exist"
        XCTAssertTrue(model.filteredNearbyMacs.isEmpty)
        XCTAssertEqual(model.discoveredNearbyMacs, [nearby])
        XCTAssertTrue(model.filteredDevices.isEmpty)
        XCTAssertEqual(model.devices.map(\.id), originalIDs)
    }

    func testDevicePasswordRemainsUsableWhenLegacyMigrationCannotPersist() {
        let device = RemoteDevice(name: "Migration denied QA", host: "qa.invalid")
        let payload = Data("synthetic-migration-password".utf8)
        var attemptedWrites = 0
        var deletedKeys: [String] = []
        let isolatedKeychain = KeychainStore(serviceName: "current-qa", legacyServiceName: "legacy-qa",
            readOverride: { service, key in
                service == "legacy-qa" && key == device.id.uuidString ? payload : nil
            },
            deleteOverride: { service, key in
                deletedKeys.append(service + ":" + key)
                return 0
            },
            writeOverride: { _, service, key in
                XCTAssertEqual(service, "current-qa")
                XCTAssertEqual(key, device.id.uuidString)
                attemptedWrites += 1
                return false
            })
        let store = DeviceStore(userDefaults: tempDefaults, keychain: isolatedKeychain)
        store.addDevice(device)
        XCTAssertEqual(store.getPassword(for: device), "synthetic-migration-password")
        XCTAssertEqual(store.getPassword(for: device), "synthetic-migration-password")
        XCTAssertEqual(attemptedWrites, 1)
        XCTAssertTrue(deletedKeys.isEmpty)
        XCTAssertEqual(store.devices.map(\.id), [device.id])
    }

    func testMigratesLegacyKeychainPasswordOnRead() throws {
        #if os(macOS)
        let fixture = try IsolatedMigrationKeychain()
        defer {
            do { try fixture.close() }
            catch { XCTFail("Could not remove owned migration Keychain: \(error)") }
        }
        keychain = fixture.store(service: currentServiceName, legacy: legacyServiceName)
        legacyKeychain = fixture.store(service: legacyServiceName)
        #endif
        let device = RemoteDevice(name: "Old Mac", host: "100.80.1.41")
        let key = device.id.uuidString
        XCTAssertTrue(legacyKeychain.savePassword("legacySecret", forKey: key))

        let store = makeStore()
        store.addDevice(device)
        XCTAssertEqual(store.getPassword(for: device), "legacySecret")

        // Moved to the current service and removed from the legacy one
        #if os(macOS)
        let legacyReader = fixture.store(service: legacyServiceName)
        let currentReader = fixture.store(service: currentServiceName)
        #else
        let legacyReader = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil)
        let currentReader = KeychainStore(serviceName: currentServiceName, legacyServiceName: nil)
        #endif
        XCTAssertNil(legacyReader.loadPassword(forKey: key))
        XCTAssertEqual(currentReader.loadPassword(forKey: key), "legacySecret")

        store.deleteDevice(device)
    }
}

#if os(macOS)
/// Real Security storage without depending on an unlocked login Keychain.
private final class IsolatedMigrationKeychain {
    private let root: URL
    private let keychain: SecKeychain
    private struct Failure: Error { let status: OSStatus }

    init() throws {
        let ownedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("migration-keychain-qa-" + UUID().uuidString)
        root = ownedRoot
        try FileManager.default.createDirectory(at: ownedRoot, withIntermediateDirectories: false)
        var created: SecKeychain?
        let password = Array(UUID().uuidString.utf8)
        let status = password.withUnsafeBytes {
            SecKeychainCreate(ownedRoot.appendingPathComponent("fixture.keychain").path,
                              UInt32(password.count), $0.baseAddress, false, nil, &created)
        }
        guard status == errSecSuccess, let created else {
            try? FileManager.default.removeItem(at: root)
            throw Failure(status: status)
        }
        keychain = created
    }

    func store(service: String, legacy: String? = nil) -> KeychainStore {
        KeychainStore(serviceName: service, legacyServiceName: legacy,
            readOverride: { [self] service, account in
                var query = self.query(service: service, account: account)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return status == errSecSuccess ? result as? Data : nil
            }, deleteOverride: { [self] service, account in
                SecItemDelete(query(service: service, account: account) as CFDictionary)
            }, writeOverride: { [self] data, service, account in
                let attributes = [kSecValueData as String: data]
                return KeychainStore.upsert(update: {
                    SecItemUpdate(query(service: service, account: account) as CFDictionary, attributes as CFDictionary)
                }, add: {
                    let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service, kSecAttrAccount as String: account,
                        kSecValueData as String: data, kSecUseKeychain as String: keychain,
                        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
                    return SecItemAdd(add as CFDictionary, nil)
                }) == errSecSuccess
            })
    }

    private func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecMatchSearchList as String: [keychain]]
    }

    func close() throws {
        let status = SecKeychainDelete(keychain)
        guard status == errSecSuccess else { throw Failure(status: status) }
        try FileManager.default.removeItem(at: root)
    }
}
#endif
