import XCTest
import Combine
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
        session.endSession()
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
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
                XCTAssertEqual(store.getPassword(for: device), "test-secret")
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
        let session = vm.prepareQuickSession(request, saveComputer: false)
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
        let session = vm.prepareQuickSession(request, saveComputer: true)
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
        XCTAssertEqual(store.getPassword(for: device), "legacySecret")

        // Moved to the current service and removed from the legacy one
        let legacyReader = KeychainStore(serviceName: legacyServiceName, legacyServiceName: nil)
        XCTAssertNil(legacyReader.loadPassword(forKey: key))
        let currentReader = KeychainStore(serviceName: currentServiceName, legacyServiceName: nil)
        XCTAssertEqual(currentReader.loadPassword(forKey: key), "legacySecret")

        store.deleteDevice(device)
    }
}
