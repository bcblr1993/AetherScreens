import XCTest
import Foundation
import CryptoKit
import Security

/// Runs against a separately identified QA app in the macOS VM.
@MainActor
final class AetherScreensMacUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        addUIInterruptionMonitor(withDescription: "QA application local-network permission") { alert in
            let description = alert.debugDescription
            // macOS truncates the permission headline in AX snapshots. Match
            // our app name and its exact local-network purpose instead.
            let purpose = description.contains("发现附近的电脑并连接其共享屏幕。") ||
                description.contains("Discover nearby Macs with Screen Sharing enabled.")
            guard description.contains("AetherScreens") && purpose else { return false }
            for title in ["允许", "Allow"] {
                let button = alert.buttons.matching(NSPredicate(format:
                    "label == %@ OR title == %@ OR value == %@", title, title, title)).firstMatch
                if button.exists { button.click(); return true }
            }
            return false
        }
    }
    func testEnglishQuickConnectValidation() throws { try checkQuickConnect(language: "en") }
    func testChineseQuickConnectValidation() throws { try checkQuickConnect(language: "zh-Hans") }
    func testEnglishControlledSession() throws { try checkControlledSession(language: "en") }
    func testChineseControlledSession() throws { try checkControlledSession(language: "zh-Hans") }
    func testEnglishSSHTrustEditor() throws { try checkSSHTrustEditor(language: "en") }
    func testChineseSSHTrustEditor() throws { try checkSSHTrustEditor(language: "zh-Hans") }

    private func checkSSHTrustEditor(language: String) throws {
        continueAfterFailure = false
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_QA_APP_PATH"])
        let bundle = try XCTUnwrap(Bundle(url: URL(fileURLWithPath: path)))
        let domain = try XCTUnwrap(bundle.bundleIdentifier)
        XCTAssertTrue(domain.hasSuffix(".vmqa"))
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let storageKey = "com.aethernative.aetherscreens.devices.list"
        let previous = defaults.data(forKey: storageKey)
        let host = "127.0.0.1"
        let port = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_SSH_QA_PORT"])
        let fingerprint = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_SSH_QA_FINGERPRINT"])
        let account = "host:" + Data(host.utf8).base64EncodedString() + ":" + port
        let service = "com.aethernative.aetherscreens.ssh"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account]
        var before = query; before[kSecReturnAttributes as String] = true
        var existing: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(before as CFDictionary, &existing), errSecItemNotFound,
                       "Do not replace an existing trusted server")
        // A failed earlier run may retain its synthetic row. Each invocation
        // must identify only the computer it just saved, including its endpoint.
        let name = "SSH Trust QA " + language + " " + UUID().uuidString.prefix(8)
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        var approvedFixtureIdentity = false
        addTeardownBlock { @MainActor in
            // Only this invocation's initially absent, reviewed fixture identity
            // may be cleaned. The owning app can remove its file-Keychain item
            // without asking another executable for access to its contents.
            if approvedFixtureIdentity && app.state != .notRunning {
                let confirm = app.buttons["ssh-confirm-forget-trust"]
                let forget = app.buttons["ssh-forget-trust"]
                if !confirm.exists && forget.exists && forget.isHittable { forget.click() }
                if confirm.exists { confirm.click() }
            }
            app.terminate()
            if let previous { defaults.set(previous, forKey: storageKey) }
            else { defaults.removeObject(forKey: storageKey) }
            let removed = SecItemDelete(query as CFDictionary)
            XCTAssertTrue(removed == errSecSuccess || removed == errSecItemNotFound,
                          "The owned fixture pin must be cleaned; Keychain status: \(removed)")
            var remaining = query
            remaining[kSecReturnAttributes as String] = true
            var remainingResult: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(remaining as CFDictionary, &remainingResult), errSecItemNotFound,
                           "The owned fixture pin must actually be absent after cleanup")
        }
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        app.launch()
        let addComputer = app.buttons.matching(identifier: language == "en" ? "Add Computer" : "添加电脑").firstMatch
        XCTAssertTrue(addComputer.waitForExistence(timeout: 10))
        addComputer.click()
        let nameField = app.textFields["connection-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click(); nameField.typeText(name)
        let hostField = app.textFields["connection-host"]
        hostField.click(); hostField.typeText(host)
        let rfbPort = app.textFields["connection-port"]
        rfbPort.click(); rfbPort.typeKey("a", modifierFlags: .command); rfbPort.typeText("5999")
        app.descendants(matching: .any).matching(identifier: "ssh-enabled").firstMatch.click()
        let sshUsername = app.textFields["ssh-username"]
        sshUsername.click(); sshUsername.typeText("qa-fixture")
        let sshPort = app.textFields["ssh-port"]
        sshPort.click(); sshPort.typeKey("a", modifierFlags: .command); sshPort.typeText(port)
        let sshPassword = app.secureTextFields["ssh-password"]
        try scrollFormControlIntoView(sshPassword, in: app)
        sshPassword.click(); sshPassword.typeText("synthetic-fixture-only")
        app.buttons[language == "en" ? "Save" : "保存"].click()
        let card = app.buttons[language == "en" ? "Connect to " + name : "连接到 " + name]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.click()
        let review = app.staticTexts["ssh-host-fingerprint"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let reviewAttributes = XCTAttachment(string: review.debugDescription)
        reviewAttributes.name = "SSH fingerprint native attributes " + language
        reviewAttributes.lifetime = .keepAlways; add(reviewAttributes)
        XCTAssertEqual(review.value as? String ?? review.label, fingerprint)
        app.buttons["ssh-trust-remember"].click()
        approvedFixtureIdentity = true
        let frame = app.descendants(matching: .any).matching(identifier: "remote-desktop-frame").firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10), "Approved SSH tunnel must carry an actual RFB frame")
        app.buttons[language == "en" ? "Disconnect" : "断开连接"].click()
        XCTAssertTrue(frame.waitForNonExistence(timeout: 5))
        card.rightClick()
        app.menuItems[language == "en" ? "Edit Computer..." : "编辑电脑…"].click()
        let saved = app.staticTexts["ssh-saved-fingerprint"]
        try scrollFormControlIntoView(saved, in: app)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String ?? saved.label, fingerprint)
        let forget = app.buttons["ssh-forget-trust"]
        try scrollFormControlIntoView(forget, in: app)
        XCTAssertTrue(forget.exists)
        forget.click()
        let alert = app.sheets.containing(.button, identifier: "ssh-confirm-forget-trust")
            .matching(NSPredicate(format: "label IN %@", ["警告", "Alert"])).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons[language == "en" ? "Cancel" : "取消"].click()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
        try scrollFormControlIntoView(saved, in: app)
        XCTAssertTrue(saved.exists, "Cancelling must retain the reviewed fingerprint")
        var retained = query; retained[kSecReturnAttributes as String] = true
        var retainedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(retained as CFDictionary, &retainedResult), errSecSuccess,
                       "Cancelling must retain the actual trusted Keychain identity")
        try scrollFormControlIntoView(forget, in: app)
        forget.click()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Mac Forget SSH Trust " + language; screenshot.lifetime = .keepAlways; add(screenshot)
        alert.buttons["ssh-confirm-forget-trust"].click()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 5))
        var read = query; read[kSecReturnData as String] = true
        read[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(read as CFDictionary, &result), errSecItemNotFound,
                       "The actual reviewed Keychain pin must be removed")
        app.buttons[language == "en" ? "Cancel" : "取消"].click()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.rightClick()
        try clickVisibleMenuItem(language == "en" ? "Delete" : "删除", in: app)
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "The synthetic saved computer must be cleaned")
    }

    private func clickVisibleMenuItem(_ title: String, in app: XCUIApplication) throws {
        // AppKit exposes identically named items from closed menus as well.
        // Require the single actionable item in the currently open menu.
        let visible = app.menuItems.matching(identifier: title).allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(visible.count, 1, "The open menu must expose exactly one actionable item: " + title)
        try XCTUnwrap(visible.first).click()
    }

    private func scrollFormControlIntoView(_ control: XCUIElement, in app: XCUIApplication) throws {
        let form = app.sheets.firstMatch.scrollViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        for _ in 0..<12 {
            let viewport = form.frame.insetBy(dx: 2, dy: 8)
            if control.exists {
                let frame = control.frame
                if !frame.isEmpty && viewport.contains(frame) && control.isHittable {
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Visible form control " + control.identifier
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                    return
                }
                form.scroll(byDeltaX: 0, deltaY: frame.minY < viewport.minY ? 180 : -180)
            } else {
                form.scroll(byDeltaX: 0, deltaY: -180)
            }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Form control visibility failure " + control.identifier
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("The form control must be fully inside the scroll viewport before interacting: " + control.identifier)
    }

    private func checkControlledSession(language: String) throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_CONTROLLED_QA"] == "1" else {
            throw XCTSkip("Requires the controlled Mac RFB fixture")
        }
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_QA_APP_PATH"])
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        app.launch()
        defer { app.terminate() }
        func label(_ english: String, _ chinese: String) -> String { language == "zh-Hans" ? chinese : english }
        func element(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        let quick = app.buttons[label("Quick Connect", "快速连接")]
        XCTAssertTrue(quick.waitForExistence(timeout: 15))
        quick.click()
        let host = app.textFields["connection-host"]
        host.click(); host.typeText("127.0.0.1")
        let port = app.textFields["connection-port"]
        port.click(); port.typeKey("a", modifierFlags: .command); port.typeText("5999")
        _ = try fixtureData("reset")
        app.buttons[label("Connect", "连接")].click()
        let frame = element("remote-desktop-frame")
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let initial = try waitForEvents { $0.contains { $0["type"] as? String == "ready" } }
        let connection = try XCTUnwrap(initial.last { $0["type"] as? String == "ready" }?["connection"] as? Int)

        _ = try fixtureData("reset")
        frame.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let pointerEvents = try waitForEvents { events in
            let pointers = events.filter { $0["type"] as? String == "pointer" }
            return pointers.contains { $0["mask"] as? Int == 1 } && pointers.last?["mask"] as? Int == 0
        }
        attachEvents(pointerEvents, name: "Mac Native Click " + language)
        element(label("Show Keyboard", "显示键盘")).click()
        let tab = app.buttons["tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        XCTAssertTrue(tab.isHittable, "Keyboard controls must have a visible native hit region")
        let keyboardScreenshot = XCTAttachment(screenshot: app.screenshot())
        keyboardScreenshot.name = "Mac Keyboard Toolbar " + language
        keyboardScreenshot.lifetime = .keepAlways
        add(keyboardScreenshot)
        _ = try fixtureData("reset")
        tab.click()
        let keys = try waitForEvents { $0.filter { $0["type"] as? String == "key" }.count == 2 }
            .filter { $0["type"] as? String == "key" }
        XCTAssertEqual(keys.compactMap { $0["key"] as? Int }, [65289, 65289])
        XCTAssertEqual(keys.compactMap { $0["down"] as? Int }, [1, 0])

        element(label("Session Options", "会话选项")).click()
        let observe = element(label("Observe Only", "仅观看"))
        XCTAssertTrue(observe.waitForExistence(timeout: 3)); observe.click()
        let showKeyboard = element(label("Show Keyboard", "显示键盘"))
        XCTAssertTrue(showKeyboard.waitForExistence(timeout: 3))
        XCTAssertFalse(showKeyboard.isEnabled)
        XCTAssertFalse(tab.exists, "Observe must dismiss the input toolbar")
        _ = try fixtureData("reset")
        frame.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        showKeyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(try events().filter { ["key", "pointer"].contains($0["type"] as? String ?? "") }.isEmpty,
                      "Observe must suppress actual native pointer and toolbar delivery")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Mac Observe Toolbar " + language; screenshot.lifetime = .keepAlways; add(screenshot)
        element(label("Session Options", "会话选项")).click()
        element(label("Observe Only", "仅观看")).click()
        XCTAssertTrue(showKeyboard.isEnabled)
        showKeyboard.click()
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        _ = try fixtureData("reset")
        element(label("Session Options", "会话选项")).click()
        let reconnect = element("session-reconnect")
        XCTAssertTrue(reconnect.waitForExistence(timeout: 3)); reconnect.click()
        let recovered = try waitForEvents { $0.contains { $0["type"] as? String == "ready" && $0["connection"] as? Int != connection } }
        attachEvents(recovered, name: "Mac New Reconnect Socket " + language)
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        _ = try fixtureData("reset")
        tab.click()
        let freshKeys = try waitForEvents { $0.filter { $0["type"] as? String == "key" }.count == 2 }
            .filter { $0["type"] as? String == "key" }
        XCTAssertEqual(freshKeys.compactMap { $0["key"] as? Int }, [65289, 65289])
        XCTAssertEqual(freshKeys.compactMap { $0["down"] as? Int }, [1, 0])
        XCTAssertTrue(freshKeys.allSatisfy { $0["connection"] as? Int != connection })
        element(label("Disconnect", "断开连接")).click()
        XCTAssertTrue(frame.waitForNonExistence(timeout: 5))
    }

    private func fixtureData(_ endpoint: String) throws -> Data {
        let response = MacFixtureResponse()
        let completed = expectation(description: "Controlled Mac fixture response")
        let task = URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8768/" + endpoint)!) { data, http, error in
            if let error { response.set(.failure(error)) }
            else if let data, (http as? HTTPURLResponse)?.statusCode == 200 { response.set(.success(data)) }
            else { response.set(.failure(URLError(.badServerResponse))) }
            completed.fulfill()
        }
        task.resume(); defer { task.cancel() }
        let result = XCTWaiter.wait(for: [completed], timeout: 3)
        XCTAssertEqual(result, .completed)
        guard result == .completed else { throw URLError(.timedOut) }
        return try XCTUnwrap(response.get()).get()
    }

    private func events() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData("events")) as? [[String: Any]])
    }

    private func waitForEvents(_ predicate: ([[String: Any]]) -> Bool) throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(3)
        var received = try events()
        while !predicate(received), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            received = try events()
        }
        if !predicate(received) { attachEvents(received, name: "Mac Received Events At Failed Assertion") }
        XCTAssertTrue(predicate(received), "Expected native Mac events must reach the fixture")
        return received
    }

    private func attachEvents(_ events: [[String: Any]], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: events, options: [.sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func checkQuickConnect(language: String) throws {
        continueAfterFailure = false
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_QA_APP_PATH"])
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        app.launch()
        defer { app.terminate() }
        let chinese = language == "zh-Hans"
        let quick = app.buttons[chinese ? "快速连接" : "Quick Connect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 15))
        quick.click()
        let host = app.textFields["connection-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        let connect = app.buttons[chinese ? "连接" : "Connect"]
        XCTAssertFalse(connect.isEnabled)
        host.click()
        host.typeText("127.0.0.1")
        XCTAssertTrue(connect.isEnabled)
        let port = app.textFields["connection-port"]
        XCTAssertTrue(port.exists)
        port.click()
        port.typeKey("a", modifierFlags: .command)
        port.typeText("70000")
        XCTAssertFalse(connect.isEnabled, "An out-of-range port must disable connection")
        port.typeKey("a", modifierFlags: .command)
        port.typeText("5900")
        XCTAssertTrue(connect.isEnabled)
        let sshToggle = app.descendants(matching: .any).matching(identifier: "ssh-enabled").firstMatch
        XCTAssertTrue(sshToggle.exists)
        sshToggle.click()
        XCTAssertFalse(connect.isEnabled, "SSH must require its own account and credential")
        let sshUsername = app.textFields["ssh-username"]
        XCTAssertTrue(sshUsername.waitForExistence(timeout: 3))
        sshUsername.click(); sshUsername.typeText("synthetic-qa")
        XCTAssertFalse(connect.isEnabled)
        let sshPassword = app.secureTextFields["ssh-password"]
        XCTAssertTrue(sshPassword.exists)
        sshPassword.click(); sshPassword.typeText("synthetic-ui-only")
        XCTAssertTrue(connect.isEnabled)
        let sshPort = app.textFields["ssh-port"]
        sshPort.click(); sshPort.typeKey("a", modifierFlags: .command); sshPort.typeText("65536")
        XCTAssertFalse(connect.isEnabled)
        sshPort.typeKey("a", modifierFlags: .command); sshPort.typeText("22")
        XCTAssertTrue(connect.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "VM Quick Connect " + language
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons[chinese ? "取消" : "Cancel"].click()
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        XCTAssertFalse(host.exists)
    }
}

private final class MacFixtureResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    func set(_ value: Result<Data, Error>) { lock.lock(); result = value; lock.unlock() }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return result }
}
