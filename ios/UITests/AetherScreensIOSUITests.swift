import XCTest

final class AetherScreensIOSUITests: XCTestCase {
    func testEnglishMacAccountPrompt() throws { try verifyMacAccountPrompt(language: "en") }
    func testChineseMacAccountPrompt() throws { try verifyMacAccountPrompt(language: "zh-Hans") }

    private func verifyMacAccountPrompt(language: String) throws {
        guard let targetHost = ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_ONLY_HOST"] else {
            throw XCTSkip("Requires an explicitly selected Mac-only authentication server")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap()
        host.typeText(targetHost)
        app.buttons[label("Connect", "连接")].tap()
        let username = app.textFields[label("Mac Account Username", "Mac 账户用户名")]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled)
        username.tap()
        username.typeText("qa-placeholder")
        let password = app.secureTextFields[label("Mac Account Password", "Mac 账户密码")]
        password.tap()
        password.typeText("qa-placeholder")
        XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
        attachScreenshot(app, name: "Mac Account Prompt " + language)
        // Verify the prompt without submitting dummy credentials to the Mac.
        app.buttons[label("Cancel", "取消")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testKeyboardCustomizationOnNarrowSession() {
        verifyKeyboardCustomization(language: "en")
    }

    func testChineseKeyboardCustomizationOnNarrowSession() {
        verifyKeyboardCustomization(language: "zh-Hans")
    }

    private func verifyKeyboardCustomization(language: String) {
        let chinese = language == "zh-Hans"
        func label(_ en: String, _ zh: String) -> String { chinese ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 10))
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap()
        host.typeText("toolbar-qa.invalid")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.buttons[label("Disconnect", "断开连接")].waitForExistence(timeout: 10))
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        let reopenedToolbar = app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")]
        if !reopenedToolbar.waitForExistence(timeout: 5) {
            // A transient system banner can consume the menu tap on hardware.
            // Retry only while the original menu item is still visible.
            let menuItem = app.buttons["session-customize-keyboard"]
            if menuItem.exists && menuItem.isHittable { menuItem.tap() }
        }
        XCTAssertTrue(reopenedToolbar.waitForExistence(timeout: 5))
        let position = app.buttons["keyboard-position"]
        XCTAssertTrue(position.exists)
        position.tap()
        app.buttons[label("Top", "顶部")].tap()
        XCTAssertTrue(app.buttons[label("Done", "完成")].exists, "Moving the toolbar must preserve its settings sheet")
        app.buttons["keyboard-size"].tap()
        app.buttons[label("Small", "小")].tap()
        let command = app.switches["keyboard-visible-Cmd"]
        XCTAssertTrue(command.exists)
        command.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(command.value as? String, "0")
        attachScreenshot(app, name: "Narrow Keyboard Customization")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cmd")).count, 0)
        attachScreenshot(app, name: "Customized Keyboard Session")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        if !reopenedToolbar.waitForExistence(timeout: 5) {
            let menuItem = app.buttons["session-customize-keyboard"]
            if menuItem.exists && menuItem.isHittable { menuItem.tap() }
        }
        XCTAssertTrue(reopenedToolbar.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["keyboard-visible-Cmd"].value as? String, "0")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testChineseEnglishSwitchAndPersistence() {
        let app = makeApp(language: "zh-Hans")
        app.launch()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["添加电脑"].exists)
        XCTAssertTrue(app.navigationBars["AetherScreens"].staticTexts["AetherScreens"].exists)
        attachScreenshot(app, name: "Chinese Dashboard")
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.buttons["同步 Tailscale 设备"].exists)
        app.buttons["诊断日志"].tap()
        XCTAssertTrue(app.navigationBars["诊断日志"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        app.buttons["快速连接"].tap()
        XCTAssertTrue(app.navigationBars["快速连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["用户名（Mac 账户，可选）"].exists)
        XCTAssertTrue(app.secureTextFields["VNC 密码（可选）"].exists)
        XCTAssertFalse(app.buttons["连接"].isEnabled)
        attachScreenshot(app, name: "Chinese Quick Connect")
        app.buttons["取消"].tap()
        app.buttons["更多操作"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["Tailscale 设置"].waitForExistence(timeout: 5))
        app.buttons["app-language"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Tailscale Settings"].waitForExistence(timeout: 5), "Switching language must preserve the open settings sheet")
        attachScreenshot(app, name: "English Settings After Switch")
        app.buttons["Done"].tap()
        app.buttons["Quick Connect"].tap()
        XCTAssertTrue(app.navigationBars["Quick Connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Username (Mac account, optional)"].exists)
        attachScreenshot(app, name: "English Quick Connect After Switch")
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Quick Connect"].waitForExistence(timeout: 10), "Manual selection must survive relaunch")
    }

    func testChineseTemporaryConnectionErrorAndRecovery() {
        let app = makeApp(language: "zh-Hans")
        app.launch()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        app.buttons["快速连接"].tap()
        let host = app.textFields["IP 地址 / 主机名（如 100.80.1.25）"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText("localized-qa.invalid")
        let account = app.textFields["用户名（Mac 账户，可选）"]
        account.tap()
        account.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac 账户密码"].exists)
        app.buttons["连接"].tap()
        XCTAssertTrue(app.buttons["断开连接"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["重试连接"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["连接失败"].exists)
        attachScreenshot(app, name: "Chinese Temporary Connection Error")
        app.buttons["重试连接"].tap()
        XCTAssertTrue(app.buttons["重试连接"].waitForExistence(timeout: 30))
        app.buttons["断开连接"].tap()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["连接到 localized-qa.invalid"].exists)
    }

    func testQuickConnectValidationAndTemporarySession() {
        let app = makeApp()
        app.launch()
        let quick = app.buttons["Quick Connect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        XCTAssertTrue(app.navigationBars["Quick Connect"].waitForExistence(timeout: 5))
        let connect = app.buttons["Connect"]
        XCTAssertFalse(connect.isEnabled)
        let name = app.textFields["Name (e.g. Studio Mac)"]
        XCTAssertFalse(name.exists)
        let address = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        address.tap()
        address.typeText("quick-qa.invalid")
        let port = app.textFields["Port"]
        port.tap()
        port.typeKey("a", modifierFlags: .command)
        port.typeText("0")
        XCTAssertEqual(port.value as? String, "0")
        XCTAssertFalse(connect.isEnabled)
        port.typeKey("a", modifierFlags: .command)
        port.typeText("5900")
        XCTAssertEqual(port.value as? String, "5900")
        XCTAssertTrue(connect.isEnabled)
        let account = app.textFields["Username (Mac account, optional)"]
        account.tap()
        account.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac Account Password"].exists)
        app.swipeUp()
        let save = app.switches["Save Computer"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.value as? String, "0")
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(save.value as? String, "1")
        app.swipeDown()
        XCTAssertTrue(name.exists)
        app.swipeUp()
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertFalse(name.exists)
        attachScreenshot(app, name: "Quick Connect")
        connect.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry Connection"].waitForExistence(timeout: 30))
        attachScreenshot(app, name: "Temporary Connection Error")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Connect to quick-qa.invalid"].exists)
    }

    func testPrimaryScreensOnIPhone() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["Add Computer"].waitForExistence(timeout: 10))
        app.buttons["Add Computer"].tap()
        XCTAssertTrue(app.navigationBars["Add Computer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Port"].exists)
        let username = app.textFields["Username (Mac account, optional)"]
        XCTAssertTrue(username.exists)
        username.tap()
        username.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac Account Password"].exists)
        XCTAssertFalse(app.secureTextFields["VNC Password (Optional)"].exists)
        attachScreenshot(app, name: "Add Computer")
        app.buttons["Cancel"].tap()

        app.buttons["More Actions"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Tailscale Settings"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Settings")
        app.buttons["Done"].tap()

        app.buttons["More Actions"].tap()
        XCTAssertTrue(app.buttons["Sync Tailscale Devices"].exists)
        app.buttons["Diagnostic Logs"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostic Logs"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Diagnostic Logs")
        app.buttons["Close"].tap()

        let computer = ensureLoopbackComputer(in: app)
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.press(forDuration: 1.0)
        app.buttons["Edit Computer..."].tap()
        XCTAssertTrue(app.navigationBars["Edit Computer"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Edit Computer")
        app.buttons["Cancel"].tap()
    }

    func testSyntheticRemoteSession() {
        let app = makeApp()
        app.launch()
        let computer = ensureLoopbackComputer(in: app)
        if !computer.isHittable { app.swipeUp() }
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 8))
        let loading = app.staticTexts["Loading remote desktop…"]
        XCTAssertTrue(loading.waitForNonExistence(timeout: 10))
        attachScreenshot(app, name: "Synthetic Remote Frame")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
        XCTAssertTrue(app.buttons["Disconnect"].isHittable)
        attachScreenshot(app, name: "Landscape Remote Frame")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.buttons["Hide Keyboard"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Remote Keyboard")
        app.buttons["Disconnect"].tap()
    }

    func testLiveRemoteSession() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_LIVE_HOST"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"] else {
            throw XCTSkip("Set live host and password in the test runner environment")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Add Computer"].tap()
        let name = app.textFields["Name (e.g. Studio Mac)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("QA Live Mac")
        let address = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        address.tap()
        address.typeText(host)
        let username = env["AETHERSCREENS_LIVE_USERNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let username, !username.isEmpty {
            let account = app.textFields["Username (Mac account, optional)"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            account.tap()
            account.typeText(username)
        }
        let secret = app.secureTextFields[(username?.isEmpty == false) ? "Mac Account Password" : "VNC Password (Optional)"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.tap()
        secret.typeText(password)
        app.buttons["Save"].tap()
        let computer = app.buttons["Connect to QA Live Mac"].firstMatch
        XCTAssertTrue(computer.waitForExistence(timeout: 10))
        if !computer.isHittable { app.swipeUp() }
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["Retry Connection"].exists)
        attachScreenshot(app, name: "Live Mac First Frame")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.buttons["Disconnect"].isHittable)
        attachScreenshot(app, name: "Live Mac Landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.buttons["Hide Keyboard"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Live Mac Keyboard")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Add Computer"].waitForExistence(timeout: 10))
    }

    func testPreviouslyConfiguredMacReceivesRealDesktop() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the previously configured physical-device Mac")
        #endif
        guard let name = ProcessInfo.processInfo.environment["AETHERSCREENS_CONFIGURED_MAC_NAME"] else {
            throw XCTSkip("Requires an explicitly selected saved Mac")
        }
        let app = makeApp()
        app.launch()
        let computer = app.buttons["Connect to " + name].firstMatch
        XCTAssertTrue(computer.waitForExistence(timeout: 15))
        scrollComputerIntoView(computer, in: app)
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        let received = frame.waitForExistence(timeout: 45)
        attachScreenshot(app, name: received ? "Physical Mac Real Desktop" : "Physical Mac Connection Failure")
        XCTAssertTrue(received, "Configured Mac must authenticate and deliver a real framebuffer")
        app.buttons["Disconnect"].tap()
    }

    // Enter the credential on the physical device so it never appears in test
    // arguments, typeText activity logs, source code, or result bundle metadata.
    func testPhysicalTargetMacAccountConnection() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires physical-device credential entry for the authorized LAN Mac")
        #endif
        let env = ProcessInfo.processInfo.environment
        guard let targetHost = env["AETHERSCREENS_LIVE_HOST"], let username = env["AETHERSCREENS_LIVE_USERNAME"] else {
            throw XCTSkip("Requires an explicitly selected physical-device Mac and account")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Quick Connect"].tap()
        let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText(targetHost)
        let account = app.textFields["Username (Mac account, optional)"]
        account.tap()
        app.activate()
        account.tap()
        account.typeText(username)
        let secret = app.secureTextFields["Mac Account Password"]
        secret.tap()
        // The user submits after finishing input. Never infer completion from
        // the first password character or read the secure-field contents.
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        let received = frame.waitForExistence(timeout: 300)
        attachScreenshot(app, name: received ? "Target Physical Desktop" : "Target Physical Connection Failure")
        XCTAssertTrue(received, "Target Mac must authenticate and deliver a real framebuffer")
        app.buttons["Disconnect"].tap()
    }

    private func makeApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        return app
    }

    private func ensureLoopbackComputer(in app: XCUIApplication) -> XCUIElement {
        let computer = app.buttons["Connect to QA Loopback"].firstMatch
        if !computer.exists {
            app.buttons["Add Computer"].tap()
            let name = app.textFields["Name (e.g. Studio Mac)"]
            let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
            let port = app.textFields["Port"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("QA Loopback")
            host.tap()
            host.typeText("127.0.0.1")
            port.tap()
            port.typeKey("a", modifierFlags: .command)
            port.typeText("5999")
            XCTAssertEqual(port.value as? String, "5999")
            XCTAssertTrue(app.buttons["Save"].isEnabled)
            app.buttons["Save"].tap()
        }
        scrollComputerIntoView(computer, in: app)
        return computer
    }

    private func scrollComputerIntoView(_ computer: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        // A partially visible card may be hittable while its long-press center
        // sits below the display. Bring the whole card above the safe area first.
        for _ in 0..<5 {
            let frame = computer.frame
            if frame.minY >= window.minY + 120 && frame.maxY <= window.maxY - 60 { break }
            if frame.maxY > window.maxY - 60 { app.swipeUp() }
            else { app.swipeDown() }
        }
        XCTAssertGreaterThanOrEqual(computer.frame.minY, window.minY + 120)
        XCTAssertLessThanOrEqual(computer.frame.maxY, window.maxY - 60)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
