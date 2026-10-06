import XCTest
import Security
import AetherScreensSSH
#if os(macOS)
import AppKit
#endif

@testable import AetherScreensCore

final class LiveFunctionalTests: XCTestCase {
    #if os(macOS)
    /// Compatibility only: no input, remote writes, clipboard contents in logs,
    /// Keychain migration, or permission prompts. Stop semantics need a separate
    /// controlled remote-copy acceptance scenario.
    func testLiveAppleClipboardMonitoringAndManualFetchCompatibility() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_CLIPBOARD_COMPATIBILITY"] == "1",
              env["AETHERSCREENS_QA_USE_SAVED_CREDENTIALS"] == "1",
              let host = env["AETHERSCREENS_LIVE_HOST"] else {
            throw XCTSkip("Requires an explicit Apple target, clipboard compatibility opt-in, and AETHERSCREENS_QA_USE_SAVED_CREDENTIALS=1")
        }
        let defaults = UserDefaults(suiteName: "com.aethernative.aetherscreens")
        guard let data = defaults?.data(forKey: DeviceStore.storageKey),
              let devices = try? JSONDecoder().decode([RemoteDevice].self, from: data),
              let device = devices.first(where: { $0.host == host && $0.authMethod == .macAccount }),
              let password = noninteractiveSavedPassword(for: device), !password.isEmpty else {
            throw XCTSkip("The target needs an existing saved account credential accessible without a Keychain prompt")
        }
        let client = RFBClient(host: device.host, port: device.port, password: password,
                               username: device.username, automaticClipboard: false,
                               automaticFramebufferUpdates: env["AETHERSCREENS_QA_APPLE_PUSH_FRAMES"] == "1")
        defer { client.disconnect() }
        client.setInputEnabled(false)
        let connected = expectation(description: "Saved account authenticates")
        connected.assertForOverFulfill = false
        let initialFrame = expectation(description: "Initial real framebuffer")
        initialFrame.assertForOverFulfill = false
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onFrameUpdated = { initialFrame.fulfill() }
        client.connect()
        wait(for: [connected, initialFrame], timeout: 30)
        guard client.state == .connected, client.supportsAppleClipboard else {
            XCTFail("The target must remain connected with Apple clipboard support")
            return
        }
        XCTAssertEqual(client.usesAutomaticFramebufferUpdates, env["AETHERSCREENS_QA_APPLE_PUSH_FRAMES"] == "1")
        client.setAutomaticClipboardMonitoring(true)
        client.setAutomaticClipboardMonitoring(false)
        client.setAutomaticClipboardMonitoring(false)
        let fetched = expectation(description: "Manual fetch receives an Apple archive while monitoring is off")
        fetched.assertForOverFulfill = false
        client.onClipboardFlavorsReceived = { _ in fetched.fulfill() }
        XCTAssertTrue(client.requestRemoteClipboard())
        wait(for: [fetched], timeout: 15)
        let continuedFrame = expectation(description: "Full frame still arrives after subscription and fetch commands")
        continuedFrame.assertForOverFulfill = false
        client.onFrameUpdated = { continuedFrame.fulfill() }
        client.requestUpdate(incremental: false)
        wait(for: [continuedFrame], timeout: 15)
        XCTAssertEqual(client.state, .connected)
        if let helperPath = env["AETHERSCREENS_QA_REMOTE_CLIPBOARD_FIXTURE"] {
            try verifyRemoteClipboardStop(client: client, device: device, helperPath: helperPath)
        }
    }

    private func verifyRemoteClipboardStop(client: RFBClient, device: RemoteDevice, helperPath: String) throws {
        guard helperPath.range(of: #"^/tmp/aetherscreens-clipboard\.[A-Za-z0-9]+/fixture\.swift$"#,
                               options: .regularExpression) != nil,
              let username = device.username, !username.isEmpty else {
            XCTFail("The controlled clipboard helper must be in a dedicated temporary directory")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5",
                             "\(username)@\(device.host)", "/usr/bin/swift \(helperPath)"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let ready = expectation(description: "Remote clipboard is snapshotted in memory")
        let restored = expectation(description: "Remote clipboard is restored")
        let offCopyChanged = expectation(description: "Remote off-state copy has completed before the quiet window")
        let richEnabled = ProcessInfo.processInfo.environment["AETHERSCREENS_QA_RICH_CLIPBOARD"] == "1"
        let richCopyChanged = richEnabled ? expectation(description: "Remote rich clipboard sample is ready") : nil
        let uploadReady = richEnabled ? expectation(description: "Remote verifier is ready for this test's upload") : nil
        let uploadReported = richEnabled ? expectation(description: "Remote verifier reports the upload result") : nil
        ready.assertForOverFulfill = false
        restored.assertForOverFulfill = false
        let statuses = ClipboardFixtureStatusReader()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            // The helper emits status tokens only; never clipboard bytes.
            for status in statuses.consume(data) {
                if status == "READY" { ready.fulfill() }
                if status == "RESTORED" { restored.fulfill() }
                if status == "CHANGED 2" { offCopyChanged.fulfill() }
                if status == "CHANGED 3" { richCopyChanged?.fulfill() }
                if status == "UPLOAD_READY" { uploadReady?.fulfill() }
                if status == "UPLOAD_VERIFIED" || status == "UPLOAD_REJECTED" { uploadReported?.fulfill() }
                if status.hasPrefix("UPLOAD_TYPES ") || status.hasPrefix("UPLOAD_ITEMS ") || status.hasPrefix("SOURCE_TYPES ") { print(status) }
            }
        }
        try process.run()
        defer {
            if process.isRunning { try? input.fileHandleForWriting.write(contentsOf: Data("END\n".utf8)) }
            try? input.fileHandleForWriting.close()
            output.fileHandleForReading.readabilityHandler = nil
        }
        wait(for: [ready], timeout: 30)
        guard process.isRunning else { XCTFail("Remote clipboard helper exited before acceptance"); return }
        let token = "AetherScreens-QA-" + UUID().uuidString
        let initialStatusCount = clipboardChangeStatusCount()
        let automatic = expectation(description: "Monitoring receives controlled remote copy")
        automatic.assertForOverFulfill = false
        client.onClipboardFlavorsReceived = { flavors in
            if ApplePasteboard.text(in: flavors) == token + "-on" { automatic.fulfill() }
        }
        client.setAutomaticClipboardMonitoring(true)
        let monitorSettled = expectation(description: "Agent has time to establish its pasteboard observer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { monitorSettled.fulfill() }
        wait(for: [monitorSettled], timeout: 2)
        try input.fileHandleForWriting.write(contentsOf: Data("SET \(token)-on\n".utf8))
        wait(for: [automatic], timeout: 10)
        XCTAssertGreaterThan(clipboardChangeStatusCount(), initialStatusCount,
                             "The real server must send a clipboard-change status while subscribed")
        client.setAutomaticClipboardMonitoring(false)
        let barrier = expectation(description: "Server processes commands through a full update")
        barrier.assertForOverFulfill = false
        client.onFrameUpdated = { barrier.fulfill() }
        client.requestUpdate(incremental: false)
        wait(for: [barrier], timeout: 10)
        let stoppedStatusCount = clipboardChangeStatusCount()
        let unexpected = expectation(description: "Stopped monitoring must not fetch a fresh remote copy")
        unexpected.isInverted = true
        client.onClipboardFlavorsReceived = { flavors in
            if ApplePasteboard.text(in: flavors) == token + "-off" { unexpected.fulfill() }
        }
        try input.fileHandleForWriting.write(contentsOf: Data("SET \(token)-off\n".utf8))
        wait(for: [offCopyChanged], timeout: 5)
        wait(for: [unexpected], timeout: 3)
        XCTAssertEqual(clipboardChangeStatusCount(), stoppedStatusCount,
                       "Stop must suppress the server notification, not just its resulting local fetch")
        let manual = expectation(description: "Manual Get returns the off-state remote copy")
        manual.assertForOverFulfill = false
        client.onClipboardFlavorsReceived = { flavors in
            if ApplePasteboard.text(in: flavors) == token + "-off" { manual.fulfill() }
        }
        XCTAssertTrue(client.requestRemoteClipboard())
        wait(for: [manual], timeout: 10)
        if let richCopyChanged, let uploadReady, let uploadReported {
            let metadataBaseline = AppLogger.shared.exportLogs().components(separatedBy: "\n").filter {
                $0.contains("Apple pasteboard metadata:")
            }.count
            defer {
                for metadata in AppLogger.shared.exportLogs().components(separatedBy: "\n").filter({
                    $0.contains("Apple pasteboard metadata:")
                }).dropFirst(metadataBaseline) {
                    print(metadata)
                }
            }
            let downloadSample = richClipboardSample(token + "-download")
            try input.fileHandleForWriting.write(contentsOf: Data("SET_RICH \(token)-download\n".utf8))
            wait(for: [richCopyChanged], timeout: 5)
            let downloaded = expectation(description: "Real Apple archive preserves native remote rich flavors")
            downloaded.assertForOverFulfill = false
            client.onClipboardFlavorsReceived = { flavors in
                print("RICH_DOWNLOAD_TYPES " + flavors.map { flavor in
                    let known = downloadSample.contains { $0.type == flavor.type } ? flavor.type : "other"
                    return "\(known)=\(flavor.data.count)"
                }.joined(separator: ","))
                XCTAssertTrue(ApplePasteboard.text(in: flavors) == token + "-download",
                              "Rich download must carry the controlled text marker")
                for expected in downloadSample {
                    XCTAssertTrue(flavors.contains { $0.type == expected.type && $0.data == expected.data },
                                  "Remote download must preserve \(expected.type) bytes")
                }
                let png = flavors.first { $0.type == "public.png" }?.data
                XCTAssertNotNil(png.flatMap(NSImage.init(data:)), "Transferred PNG must decode as a native image")
                downloaded.fulfill()
            }
            XCTAssertTrue(client.requestRemoteClipboard())
            wait(for: [downloaded], timeout: 10)
            let uploadSample = richClipboardSample(token + "-upload")
            try input.fileHandleForWriting.write(contentsOf: Data("EXPECT_UPLOAD \(token)-upload\n".utf8))
            wait(for: [uploadReady], timeout: 5)
            client.setInputEnabled(true)
            XCTAssertTrue(client.sendClipboardFlavors(uploadSample))
            client.setInputEnabled(false)
            wait(for: [uploadReported], timeout: 12)
            XCTAssertTrue(statuses.hasReceived("UPLOAD_VERIFIED"),
                          "Native remote pasteboard must contain all uploaded rich flavors and a decodable PNG")
            let roundtrip = expectation(description: "Uploaded native rich content can be fetched back intact")
            roundtrip.assertForOverFulfill = false
            client.onClipboardFlavorsReceived = { flavors in
                XCTAssertTrue(ApplePasteboard.text(in: flavors) == token + "-upload",
                              "Rich roundtrip must carry the controlled upload marker")
                for expected in uploadSample {
                    XCTAssertTrue(flavors.contains { $0.type == expected.type && $0.data == expected.data },
                                  "Upload roundtrip must preserve \(expected.type) bytes")
                }
                roundtrip.fulfill()
            }
            XCTAssertTrue(client.requestRemoteClipboard())
            wait(for: [roundtrip], timeout: 10)
        }
        try input.fileHandleForWriting.write(contentsOf: Data("END\n".utf8))
        wait(for: [restored], timeout: 10)
        XCTAssertEqual(client.state, .connected)
    }

    private func richClipboardSample(_ marker: String) -> [RFBClipboardFlavor] {
        [
            .init(type: "public.utf8-plain-text", data: Data(marker.utf8)),
            .init(type: "public.url", data: Data("https://example.com/\(marker)".utf8)),
            .init(type: "public.rtf", data: Data("{\\rtf1\\ansi \(marker)}".utf8)),
            .init(type: "public.html", data: Data("<p>\(marker)</p>".utf8)),
            .init(type: "public.png", data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMIqDjxHwAFPAKQ8H9qXAAAAABJRU5ErkJggg==")!)
        ]
    }

    private func clipboardChangeStatusCount() -> Int {
        // exportLogs takes the logger lock. Only count fixed protocol metadata;
        // neither clipboard bytes nor the diagnostic buffer are printed.
        AppLogger.shared.exportLogs().components(separatedBy: "\n").filter {
            $0.contains("Apple status: flags=1, command=2")
        }.count
    }

    private final class ClipboardFixtureStatusReader: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private var received = Set<String>()
        func hasReceived(_ status: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return received.contains(status)
        }
        func consume(_ data: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: 10) {
                lines.append(String(decoding: pending[..<end], as: UTF8.self))
                pending.removeSubrange(...end)
            }
            received.formUnion(lines)
            return lines
        }
    }

    private func noninteractiveSavedPassword(for device: RemoteDevice) -> String? {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_USE_SAVED_CREDENTIALS"] == "1" else { return nil }
        for service in [KeychainStore.defaultServiceName, KeychainStore.legacyServiceName] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: device.id.uuidString,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
            ]
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let password = String(data: data, encoding: .utf8) {
                return password
            }
        }
        return nil
    }
    #endif

    private final class ReadonlyRetryPasswordStore: DevicePasswordStore, @unchecked Sendable {
        private let lock = NSLock()
        private var writes = 0
        var writeCount: Int {
            lock.lock(); defer { lock.unlock() }
            return writes
        }
        func savePassword(_ password: String, forKey key: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            writes += 1
            return false
        }
        func loadPassword(forKey key: String) -> String? { nil }
        func deletePassword(forKey key: String) -> Bool { false }
    }

    @MainActor
    func testLiveFailedPasswordCanBeCorrectedInTemporarySession() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_PASSWORD_RETRY"] == "1",
              let host = env["AETHERSCREENS_LIVE_HOST"],
              let username = env["AETHERSCREENS_LIVE_USERNAME"] else {
            throw XCTSkip("Requires explicit opt-in for one failed live account authentication and retry")
        }
        var credential = env["AETHERSCREENS_LIVE_PASSWORD"]
        #if os(macOS)
        // The explicit live target can use an existing noninteractive account
        // credential without passing its password through process environment.
        if credential == nil, env["AETHERSCREENS_QA_USE_SAVED_CREDENTIALS"] == "1",
           let data = UserDefaults(suiteName: "com.aethernative.aetherscreens")?.data(forKey: DeviceStore.storageKey),
           let devices = try? JSONDecoder().decode([RemoteDevice].self, from: data),
           let saved = devices.first(where: {
               $0.host == host && $0.authMethod == .macAccount && $0.username == username
           }) {
            credential = noninteractiveSavedPassword(for: saved)
        }
        #endif
        guard let password = credential, !password.isEmpty, password.utf8.count < 50 else {
            throw XCTSkip("Requires an existing accessible saved account credential or a supplied test credential")
        }
        let suite = "com.aethernative.aetherscreens.readonly-retry-qa." + UUID().uuidString
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { isolatedDefaults.removePersistentDomain(forName: suite) }
        let passwordStore = ReadonlyRetryPasswordStore()
        let isolatedDevices = TestStorage.make(userDefaults: isolatedDefaults, passwordStore: passwordStore,
                                          sshKeychain: TestStorage.sshKeychain())
        let device = RemoteDevice(name: "Temporary retry QA", host: host, authMethod: .macAccount,
                                  username: username, disconnectAction: .disconnectOnly, sharedClipboard: false)
        let session = TestSession.make(device: device, password: password + "-qa-invalid", isTemporary: true,
                                       deviceStore: isolatedDevices, keyboardStore: KeyboardToolbarStore(defaults: isolatedDefaults))
        session.isObserveOnly = true
        defer { session.endSession() }
        let rejected = expectation(description: "Initial account password rejected")
        rejected.assertForOverFulfill = false
        session.client.onStateChanged = { state in if case .failed = state { rejected.fulfill() } }
        session.startSession()
        wait(for: [rejected], timeout: 30)
        guard case .failed = session.client.state else {
            XCTFail("Initial password must fail before checking correction")
            return
        }
        let connected = expectation(description: "Corrected password authenticates")
        connected.assertForOverFulfill = false
        let frame = expectation(description: "Corrected session receives a real desktop")
        frame.assertForOverFulfill = false
        session.client.onStateChanged = { state in if state == .connected { connected.fulfill() } }
        session.client.onFrameUpdated = { frame.fulfill() }
        session.submitPassword(password, rememberInKeychain: true)
        wait(for: [connected, frame], timeout: 30)
        XCTAssertEqual(session.client.state, .connected)
        XCTAssertGreaterThan(session.client.framebuffer.width, 0)
        XCTAssertEqual(passwordStore.writeCount, 0, "Temporary retry must never invoke credential persistence")
        for service in [KeychainStore.defaultServiceName, KeychainStore.legacyServiceName] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: device.id.uuidString,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnAttributes as String: true,
                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
            ]
            var item: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecItemNotFound,
                           "Correcting a temporary session must not save a current or legacy credential")
        }
    }

    func testLivePointerDeliveryToControlledFixture() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_LIVE_HOST"],
              let x = env["AETHERSCREENS_QA_CLICK_X"].flatMap(UInt16.init),
              let y = env["AETHERSCREENS_QA_CLICK_Y"].flatMap(UInt16.init) else {
            throw XCTSkip("Requires an explicit live target and controlled fixture coordinates")
        }
        var savedDevice: RemoteDevice?
        if env["AETHERSCREENS_QA_USE_SAVED_CREDENTIALS"] == "1",
           let data = UserDefaults(suiteName: "com.aethernative.aetherscreens")?.data(forKey: DeviceStore.storageKey),
           let devices = try? JSONDecoder().decode([RemoteDevice].self, from: data) {
            savedDevice = devices.first { $0.host == host }
        }
        guard let password = env["AETHERSCREENS_LIVE_PASSWORD"] ?? savedDevice.flatMap(noninteractiveSavedPassword),
              !password.isEmpty else {
            throw XCTSkip("Requires a supplied credential or this application's saved credential for the explicit target")
        }
        let frame = expectation(description: "Real frame received")
        frame.assertForOverFulfill = false
        let account = try XCTUnwrap(env["AETHERSCREENS_QA_SSH_USER"], "Specify the fixture SSH account")
        // Check that the controlled page is available before opening an input session.
        let page = try XCTUnwrap(try fixtureJSON(host: host, account: account, path: "page-state") as? [String: Any],
                                "The controlled page must report its live state")
        let pageData = try XCTUnwrap(page["data"] as? [String: Any])
        let pageTime = try XCTUnwrap(page["serverTime"] as? Double)
        guard pageData["focused"] as? Bool == true,
              pageData["visible"] as? Bool == true,
              abs(Date().timeIntervalSince1970 - pageTime) < 10 else {
            XCTFail("The controlled page must be visible, focused and reporting fresh state before input")
            return
        }
        _ = try fixtureEvents(host: host, account: account)
        let client = RFBClient(host: host, password: password, username: env["AETHERSCREENS_LIVE_USERNAME"] ?? savedDevice?.username)
        defer {
            client.disconnect()
            for entry in AppLogger.shared.entries where entry.message.hasPrefix("Apple status:") || entry.message.hasPrefix("Apple pasteboard metadata:") {
                print(entry.message)
            }
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.onStateChanged = { state in if case .failed = state { frame.fulfill() } }
        client.connect()
        wait(for: [frame], timeout: 30)
        guard client.state == .connected else {
            XCTFail("Live connection failed: \(client.state)")
            client.disconnect()
            return
        }
        print("Fixture framebuffer: \(client.framebuffer.width)x\(client.framebuffer.height)")
        let settled = expectation(description: "Initial desktop update completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { settled.fulfill() }
        wait(for: [settled], timeout: 6)
        let before = try fixtureEvents(host: host, account: account)
        client.sendPointerEvent(buttonMask: .left, x: x, y: y)
        client.sendPointerEvent(buttonMask: [], x: x, y: y)
        let initialClicks = before.filter { $0["type"] as? String == "click" }.count
        let after = try waitForFixtureEvents(host: host, account: account) { events in
            events.filter { $0["type"] as? String == "click" }.count > initialClicks
        }
        guard after.filter({ $0["type"] as? String == "click" }).count > initialClicks else {
            XCTFail("The controlled remote page must observe the actual click before further input")
            return
        }
        if env["AETHERSCREENS_QA_OBSERVE"] == "1" {
            client.sendKeyEvent(down: true, keySym: MacKeyMap.shiftLeft)
            client.setInputEnabled(false)
            let baseline = try fixtureEvents(host: host, account: account)
            let observingFrames = expectation(description: "Observe mode continues receiving frames")
            observingFrames.assertForOverFulfill = false
            client.onFrameUpdated = { observingFrames.fulfill() }
            client.sendText("must not arrive")
            client.sendCutText("must not arrive")
            client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
            client.sendPointerEvent(buttonMask: .left, x: x, y: y)
            client.sendPointerEvent(buttonMask: [], x: x, y: y)
            client.sendPointerEvent(buttonMask: .scrollDown, x: x, y: y)
            wait(for: [observingFrames], timeout: 5)
            let suppressed = expectation(description: "Delayed input remains suppressed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { suppressed.fulfill() }
            wait(for: [suppressed], timeout: 2)
            let observed = try fixtureEvents(host: host, account: account)
            XCTAssertEqual(observed.count, baseline.count, "Observe mode must produce no remote fixture input")
            client.setInputEnabled(true)
            if let scrollX = env["AETHERSCREENS_QA_SCROLL_X"].flatMap(UInt16.init),
               let scrollY = env["AETHERSCREENS_QA_SCROLL_Y"].flatMap(UInt16.init) {
                client.sendPointerEvent(buttonMask: .scrollUp, x: scrollX, y: scrollY)
                client.sendPointerEvent(buttonMask: .scrollDown, x: scrollX, y: scrollY)
                client.setInputEnabled(false)
                client.setInputEnabled(true)
                let staleWheel = expectation(description: "Old wheel tasks stay cancelled after control resumes")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { staleWheel.fulfill() }
                wait(for: [staleWheel], timeout: 2)
                let cancelled = try fixtureEvents(host: host, account: account)
                XCTAssertEqual(cancelled.filter { $0["type"] as? String == "scroll" }.count,
                               observed.filter { $0["type"] as? String == "scroll" }.count)
            }
            client.sendPointerEvent(buttonMask: .left, x: x, y: y)
            client.sendPointerEvent(buttonMask: [], x: x, y: y)
            let resumed = expectation(description: "Control resumes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { resumed.fulfill() }
            wait(for: [resumed], timeout: 2)
            let resumedEvents = try fixtureEvents(host: host, account: account)
            XCTAssertGreaterThan(resumedEvents.filter { $0["type"] as? String == "click" }.count,
                                 observed.filter { $0["type"] as? String == "click" }.count)
        }
        if env["AETHERSCREENS_QA_LATENCY"] == "1" {
            // A fixture click changes the otherwise static background. Moving animation
            // elsewhere cannot satisfy this specific input-to-frame response check.
            func backgroundPixel() -> [UInt8] {
                var pixel: [UInt8] = []
                client.framebuffer.withPixelBytes { bytes, width, height in
                    guard width > 3500, height > 2000 else { return }
                    let offset = (2000 * width + 3500) * 4
                    pixel = Array(bytes[offset..<(offset + 3)])
                }
                return pixel
            }
            var samples: [Double] = []
            for _ in 0..<10 {
                let original = backgroundPixel()
                XCTAssertEqual(original.count, 3)
                let start = ProcessInfo.processInfo.systemUptime
                client.sendPointerEvent(buttonMask: .left, x: x, y: y)
                client.sendPointerEvent(buttonMask: [], x: x, y: y)
                while backgroundPixel() == original && ProcessInfo.processInfo.systemUptime - start < 2 {
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
                }
                XCTAssertNotEqual(backgroundPixel(), original, "The click-specific background change must return")
                samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            let sorted = samples.sorted()
            print("Input-to-decoded-frame milliseconds: median=\(sorted[5]), p95/max=\(sorted[9]), samples=\(samples)")
        }
        if let text = env["AETHERSCREENS_QA_TYPE_TEXT"] {
            client.sendPointerEvent(buttonMask: .left, x: 720, y: 804)
            client.sendPointerEvent(buttonMask: [], x: 720, y: 804)
            client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
            client.sendKeyEvent(down: true, keySym: 0x61)
            client.sendKeyEvent(down: false, keySym: 0x61)
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
            let selectionReady = expectation(description: "Remote selection ready")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { selectionReady.fulfill() }
            wait(for: [selectionReady], timeout: 2)
            client.sendText(text)
            let typed = expectation(description: "Committed remote text received")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { typed.fulfill() }
            wait(for: [typed], timeout: 2)
            let events = try fixtureEvents(host: host, account: account)
            let value = (events.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String
            XCTAssertEqual(value, text)
        }
        if env["AETHERSCREENS_QA_UNICODE_KEY"] == "1" {
            let sample = env["AETHERSCREENS_QA_UNICODE_SAMPLE"] ?? "中"
            let scalar = try XCTUnwrap(sample.unicodeScalars.first)
            let prior = try fixtureEvents(host: host, account: account)
            let priorValue = (prior.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String ?? ""
            client.sendPointerEvent(buttonMask: .left, x: 720, y: 804)
            client.sendPointerEvent(buttonMask: [], x: 720, y: 804)
            let keys: [UInt32]
            switch env["AETHERSCREENS_QA_UNICODE_STYLE"] {
            case "x11": keys = [0x01000000 | scalar.value]
            case "utf16": keys = String(scalar).utf16.map { 0x01000000 | UInt32($0) }
            default: keys = [scalar.value]
            }
            for key in keys {
                client.sendKeyEvent(down: true, keySym: key)
                client.sendKeyEvent(down: false, keySym: key)
            }
            let inserted = expectation(description: "Unicode key delivery")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { inserted.fulfill() }
            wait(for: [inserted], timeout: 2)
            let events = try fixtureEvents(host: host, account: account)
            let value = (events.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String ?? ""
            XCTAssertEqual(value.filter { String($0) == sample }.count,
                           priorValue.filter { String($0) == sample }.count + 1,
                           "A fresh Unicode input must be observed, not an existing value")
        }
        if env["AETHERSCREENS_QA_UNICODE"] == "1" {
            client.sendPointerEvent(buttonMask: .left, x: 720, y: 804)
            client.sendPointerEvent(buttonMask: [], x: 720, y: 804)
            let testText = env["AETHERSCREENS_QA_CLIPBOARD_TEXT"] ?? "中文 QA"
            let priorPastes = try fixtureEvents(host: host, account: account).filter { $0["type"] as? String == "paste" }.count
            let applePaste = env["AETHERSCREENS_QA_APPLE_PASTEBOARD"] == "1"
            let queued = applePaste ? client.sendClipboardAndPaste(testText) : client.sendCutText(testText)
            guard queued else {
                XCTFail("The server's negotiated clipboard encoding cannot send the requested text")
                return
            }
            if !applePaste {
                let clipboardReady = expectation(description: "Remote clipboard set")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { clipboardReady.fulfill() }
                wait(for: [clipboardReady], timeout: 2)
                client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
                client.sendKeyEvent(down: true, keySym: UInt32(118))
                client.sendKeyEvent(down: false, keySym: UInt32(118))
                client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
            }
            let events = try waitForFixtureEvents(host: host, account: account) { events in
                events.filter { $0["type"] as? String == "paste" }.count > priorPastes
            }
            XCTAssertGreaterThan(events.filter { $0["type"] as? String == "paste" }.count, priorPastes,
                                 "A fresh remote paste must be observed")
            let paste = events.last { $0["type"] as? String == "paste" }
            XCTAssertEqual((paste?["data"] as? [String: Any])?["value"] as? String, testText)
            if env["AETHERSCREENS_QA_APPLE_PASTEBOARD"] == "1" {
                let receivedClipboard = expectation(description: "Real Apple pasteboard received through the protocol")
                receivedClipboard.assertForOverFulfill = false
                client.onClipboardReceived = { text in
                    // Only acknowledge our synthetic sample; never log other clipboard content.
                    if text == testText { receivedClipboard.fulfill() }
                }
                XCTAssertTrue(client.requestApplePasteboard())
                wait(for: [receivedClipboard], timeout: 8)
                client.onClipboardReceived = nil
                XCTAssertEqual(client.state, .connected)
                let copiedText = testText + " remote copy"
                let changedClipboard = expectation(description: "Remote copy notification fetches new clipboard content")
                changedClipboard.assertForOverFulfill = false
                client.onClipboardReceived = { text in
                    if text == copiedText { changedClipboard.fulfill() }
                }
                client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
                client.sendKeyEvent(down: true, keySym: 97)
                client.sendKeyEvent(down: false, keySym: 97)
                client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                client.sendKeyEvent(down: true, keySym: MacKeyMap.backspace)
                client.sendKeyEvent(down: false, keySym: MacKeyMap.backspace)
                let cleared = try waitForFixtureEvents(host: host, account: account) { events in
                    (events.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String == ""
                }
                guard (cleared.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String == "" else {
                    XCTFail("Remote textarea must be cleared before the copy-notification assertion")
                    client.onClipboardReceived = nil
                    return
                }
                client.sendText(copiedText)
                let typed = try waitForFixtureEvents(host: host, account: account) { events in
                    (events.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String == copiedText
                }
                guard (typed.last { $0["type"] as? String == "input" }?["data"] as? [String: Any])?["value"] as? String == copiedText else {
                    XCTFail("The new remote copy sample must be received exactly before copying")
                    client.onClipboardReceived = nil
                    return
                }
                let priorCopies = try fixtureEvents(host: host, account: account).filter { $0["type"] as? String == "copy" }.count
                for key in [UInt32(97), UInt32(99)] {
                    client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
                    client.sendKeyEvent(down: true, keySym: key)
                    client.sendKeyEvent(down: false, keySym: key)
                    client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
                    if key == 97 { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)) }
                }
                let copied = try waitForFixtureEvents(host: host, account: account) { events in
                    events.filter { $0["type"] as? String == "copy" }.count > priorCopies
                }
                guard (copied.last { $0["type"] as? String == "copy" }?["data"] as? [String: Any])?["value"] as? String == copiedText else {
                    XCTFail("Actual browser copy event must contain the exact new test sample")
                    client.onClipboardReceived = nil
                    return
                }
                if env["AETHERSCREENS_QA_APPLE_COPY_REFETCH"] == "1" {
                    // Diagnostic only: an explicit fetch must not be reported as automatic synchronization.
                    XCTAssertTrue(client.requestApplePasteboard())
                }
                wait(for: [changedClipboard], timeout: 8)
                client.onClipboardReceived = nil
                XCTAssertEqual(client.state, .connected)
            }
        }
        if let scrollX = env["AETHERSCREENS_QA_SCROLL_X"].flatMap(UInt16.init),
           let scrollY = env["AETHERSCREENS_QA_SCROLL_Y"].flatMap(UInt16.init) {
            for _ in 0..<12 {
                client.sendPointerEvent(buttonMask: .scrollDown, x: scrollX, y: scrollY)
                client.sendPointerEvent(buttonMask: [], x: scrollX, y: scrollY)
            }
            let scrolled = expectation(description: "Allow remote wheel delivery")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { scrolled.fulfill() }
            wait(for: [scrolled], timeout: 3)
            let events = try fixtureEvents(host: host, account: account)
            XCTAssertGreaterThan(events.filter { $0["type"] as? String == "scroll" }.count,
                                 after.filter { $0["type"] as? String == "scroll" }.count,
                                 "The controlled remote page must observe actual scrolling")
        }
        client.disconnect()
    }

    private func waitForFixtureEvents(host: String, account: String,
                                      until received: ([[String: Any]]) -> Bool) throws -> [[String: Any]] {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var events = try fixtureEvents(host: host, account: account)
        while !received(events) && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            events = try fixtureEvents(host: host, account: account)
        }
        return events
    }

    private func fixtureEvents(host: String, account: String) throws -> [[String: Any]] {
        try XCTUnwrap(try fixtureJSON(host: host, account: account, path: "events") as? [[String: Any]])
    }

    private func fixtureJSON(host: String, account: String, path: String) throws -> Any {
        precondition(path == "events" || path == "page-state")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "\(account)@\(host)",
                             "curl -m 5 -fsS http://127.0.0.1:8766/\(path)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LiveFixture", code: Int(process.terminationStatus))
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
