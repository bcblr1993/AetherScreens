import XCTest
import UIKit

final class AetherScreensIOSUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        // A missing fixture response/frame invalidates later packet assertions
        // in that case. Preserve the first failure instead of continuing input.
        continueAfterFailure = false
    }

    func testControlledScreenBoundaryGestures() throws { try verifyScreenBoundaryGestures(language: "en") }
    func testChineseControlledScreenBoundaryGestures() throws { try verifyScreenBoundaryGestures(language: "zh-Hans") }

    private func verifyScreenBoundaryGestures(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the controlled RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language, boundaryDiagnostics: true)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        // Keep the shortcuts toolbar visible while testing the bottom edge.
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let window = app.windows.firstMatch
        let edges: [(CGVector, CGVector, Int, Int)] = [
            (CGVector(dx: 0.005, dy: 0.5), CGVector(dx: 0.3, dy: 0.5), 0, 180),
            (CGVector(dx: 0.995, dy: 0.5), CGVector(dx: 0.7, dy: 0.5), 639, 180),
            // Start beside the camera cutout, on the actual touchable top edge.
            // The remote destination remains the midpoint of the remote edge.
            (CGVector(dx: 0.25, dy: 0.005), CGVector(dx: 0.25, dy: 0.25), 320, 0),
            (CGVector(dx: 0.5, dy: 0.995), CGVector(dx: 0.5, dy: 0.75), 320, 359)]
        for (start, end, x, y) in edges {
            try resetGestureFixture()
            window.coordinate(withNormalizedOffset: start).press(forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: end), withVelocity: .slow, thenHoldForDuration: 0.1)
            _ = try waitForGesturePointers { $0.last?["x"] == x && $0.last?["y"] == y && $0.last?["mask"] == 0 }
        }
        try attachGesturePackets(try gesturePointers(), name: "Received Bottom Edge Over Toolbar " + language)
        attachScreenshot(app, name: "Screen Edge Toolbar " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        XCTAssertTrue(app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")].waitForExistence(timeout: 5))
        try resetGestureFixture()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(try gesturePointers().isEmpty, "A sheet above the session must suppress window-level remote edge input")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5)).press(forDuration: 0.05,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(try gesturePointers().isEmpty)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledToolbarRepeatAndIndividualKeys() throws { try verifyToolbarRepeatAndIndividualKeys(language: "en") }
    func testChineseControlledToolbarRepeatAndIndividualKeys() throws { try verifyToolbarRepeatAndIndividualKeys(language: "zh-Hans") }

    private func verifyToolbarRepeatAndIndividualKeys(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let toolbar = app.scrollViews["keyboard-toolbar-scroll"]
        func reveal(_ button: XCUIElement) {
            revealToolbarButton(button, in: toolbar)
        }
        let tab = app.buttons["tab"]
        reveal(tab)
        try resetGestureFixture()
        tab.press(forDuration: 0.9)
        let repeated = try waitForFixtureEvents { events in
            let keys = events.filter { $0["type"] as? String == "key" && $0["key"] as? Int == 65289 }
            return keys.filter { $0["down"] as? Int == 1 }.count >= 2 && keys.last?["down"] as? Int == 0
        }
        let keyCount = repeated.filter { $0["type"] as? String == "key" }.count
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(try fixtureEvents().filter { $0["type"] as? String == "key" }.count, keyCount)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        XCTAssertTrue(app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")].waitForExistence(timeout: 5))
        let f12 = app.switches["keyboard-visible-F12"]
        for _ in 0..<15 { if f12.exists && f12.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(f12.value as? String, "0")
        // A labeled Toggle's accessibility bounds include the empty space
        // between its label and switch. Target the switch, beside the sort buttons.
        let switchBounds = XCTAttachment(string: "F12 toggle frame: \(f12.frame)")
        switchBounds.name = "F12 Visibility Control Bounds"
        switchBounds.lifetime = .keepAlways
        add(switchBounds)
        f12.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(f12.value as? String, "1", "The F12 visibility setting must change before returning to the toolbar")
        attachScreenshot(app, name: "Individual F12 Settings " + language)
        app.buttons[label("Done", "完成")].tap()
        let key = app.buttons["F12"]
        reveal(key)
        try resetGestureFixture()
        key.tap()
        let received = try waitForFixtureEvents { events in
            let keys = events.filter { $0["type"] as? String == "key" }
            return keys.count == 2 && keys.last?["down"] as? Int == 0
        }
        XCTAssertEqual(received.filter { $0["type"] as? String == "key" }.compactMap { $0["key"] as? Int }, [65481, 65481])
        attachScreenshot(app, name: "Individual F12 Toolbar " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledDictationPreview() throws { try verifyControlledDictationPreview(language: "en") }
    func testChineseControlledDictationPreview() throws { try verifyControlledDictationPreview(language: "zh-Hans") }

    private func verifyControlledDictationPreview(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let dictation = app.buttons["session-dictation"]
        let toolbar = app.scrollViews["keyboard-toolbar-scroll"]
        revealToolbarButton(dictation, in: toolbar)
        try resetGestureFixture()
        dictation.tap()
        XCTAssertTrue(app.buttons["dictation-start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dictation-send"].isEnabled)
        attachScreenshot(app, name: "Dictation Preview " + language)
        // Merely opening/cancelling must neither request microphone access nor
        // send text. Actual audio permission and recognition have a separate gate.
        app.buttons[label("Cancel", "取消")].tap()
        XCTAssertFalse(try fixtureEvents().contains { $0["type"] as? String == "key" })
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        // Observe hides the entire keyboard toolbar; querying isEnabled on a
        // removed action raises an XCTest snapshot error rather than false.
        XCTAssertFalse(app.scrollViews["keyboard-toolbar-scroll"].exists)
        XCTAssertFalse(dictation.exists)
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledDisconnectActions() throws { try verifyControlledDisconnectActions(language: "en") }
    func testChineseControlledDisconnectActions() throws { try verifyControlledDisconnectActions(language: "zh-Hans") }

    private func verifyControlledDisconnectActions(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        let name = "QA Disconnect " + language
        let computer = app.buttons[label("Connect to " + name, "连接到 " + name)].firstMatch
        if !computer.exists {
            app.buttons[label("Add Computer", "添加电脑")].tap()
            let field = app.textFields[label("Name (e.g. Studio Mac)", "名称（如 工作室 Mac）")]
            field.tap(); field.typeText(name)
            let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
            host.tap(); host.typeText(gestureFixtureHost)
            replacePort(app.textFields[label("Port", "端口")], with: gestureDisplayFixturePort)
            app.buttons[label("Save", "保存")].tap()
        }
        func configure(_ en: String, _ zh: String) {
            scrollComputerIntoView(computer, in: app)
            computer.press(forDuration: 1)
            app.buttons[label("Edit Computer...", "编辑电脑…")].tap()
            XCTAssertTrue(app.navigationBars[label("Edit Computer", "编辑电脑")].waitForExistence(timeout: 5))
            let picker = app.buttons["disconnect-action-picker"]
            for _ in 0..<5 {
                if picker.exists && picker.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(picker.isHittable)
            picker.tap()
            app.buttons[label(en, zh)].tap()
            attachScreenshot(app, name: "Disconnect Settings " + en + " " + language)
            app.buttons[label("Save", "保存")].tap()
        }
        func open() {
            scrollComputerIntoView(computer, in: app)
            computer.tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        }
        func closeAndRead() throws -> [[String: Any]] {
            try resetGestureFixture()
            app.buttons[label("Disconnect", "断开连接")].tap()
            XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
            let packets = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "disconnected" } }
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: packets, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "Received Disconnect Action " + language
            attachment.lifetime = .keepAlways
            add(attachment)
            return packets
        }
        configure("Lock Screen", "锁定屏幕")
        app.terminate(); app.launch()
        open()
        var packets = try closeAndRead()
        XCTAssertEqual(packets.filter { $0["type"] as? String == "key" }.compactMap { $0["key"] as? Int },
                       [65507, 65515, 113, 113, 65515, 65507])
        configure("Log Out Remote User", "退出登录远程用户")
        open()
        packets = try closeAndRead()
        XCTAssertEqual(packets.filter { $0["type"] as? String == "key" }.compactMap { $0["key"] as? Int },
                       [65513, 65505, 65515, 113, 113, 65515, 65505, 65513])
        configure("Bottom Right", "右下角")
        open()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-displays"].tap()
        app.buttons[label("Display 2", "显示器 2")].tap()
        packets = try closeAndRead()
        XCTAssertEqual(packets.filter { $0["type"] as? String == "pointer" }.map { [$0["x"] as? Int ?? -1, $0["y"] as? Int ?? -1] },
                       [[480, 180], [639, 359]])
        configure("Lock Screen", "锁定屏幕")
        open()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        packets = try closeAndRead()
        XCTAssertFalse(packets.contains { ["key", "pointer"].contains($0["type"] as? String ?? "") })
        // Editing a retained connection must take effect on its existing socket.
        configure("Lock Screen", "锁定屏幕")
        open()
        let beforeEdit = try fixtureEvents()
        let originalConnection = try XCTUnwrap(beforeEdit.last { $0["type"] as? String == "ready" }?["connection"] as? Int)
        let connectionCount = beforeEdit.filter { $0["type"] as? String == "ready" }.count
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-return-to-library"].tap()
        configure("Disconnect Only", "仅断开连接")
        app.buttons["open-sessions"].tap()
        let retained = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-session-")).firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 5))
        retained.tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(try fixtureEvents().filter { $0["type"] as? String == "ready" }.count, connectionCount)
        packets = try closeAndRead()
        XCTAssertFalse(packets.contains { ["key", "pointer"].contains($0["type"] as? String ?? "") })
        XCTAssertEqual(packets.first { $0["type"] as? String == "disconnected" }?["connection"] as? Int, originalConnection)
    }

    func testControlledHotCorners() throws { try verifyControlledHotCorners(language: "en") }
    func testChineseControlledHotCorners() throws { try verifyControlledHotCorners(language: "zh-Hans") }

    private func verifyControlledHotCorners(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureDisplayFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))

        func trigger(_ en: String, _ zh: String, x: Int, y: Int, screenshot: Bool = false) throws {
            try resetGestureFixture()
            app.buttons[label("Session Options", "会话选项")].tap()
            let menu = app.buttons["session-hot-corners"]
            XCTAssertTrue(menu.waitForExistence(timeout: 3))
            XCTAssertTrue(menu.isEnabled)
            menu.tap()
            let corner = app.buttons[label(en, zh)]
            XCTAssertTrue(corner.waitForExistence(timeout: 3))
            if screenshot { attachScreenshot(app, name: "Hot Corners Menu " + language) }
            corner.tap()
            let packets = try waitForGesturePointers { $0.count >= 2 && $0.last?["x"] == x && $0.last?["y"] == y }
            XCTAssertTrue(packets.allSatisfy { $0["mask"] == 0 }, "A corner action must not click or drag")
            XCTAssertEqual(packets.count, 2)
            XCTAssertEqual(packets.last?["x"], x)
            XCTAssertEqual(packets.last?["y"], y)
            try attachGesturePackets(packets, name: "Received Hot Corner " + en + " " + language)
        }

        try trigger("Top Left", "左上角", x: 0, y: 0, screenshot: true)
        try trigger("Top Right", "右上角", x: 639, y: 0)
        try trigger("Bottom Left", "左下角", x: 0, y: 359)
        try trigger("Bottom Right", "右下角", x: 639, y: 359)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-displays"].tap()
        app.buttons[label("Display 2", "显示器 2")].tap()
        try trigger("Top Left", "左上角", x: 320, y: 0)
        try trigger("Bottom Right", "右下角", x: 639, y: 359)
        // Repeating the same corner must leave and re-enter it.
        try trigger("Bottom Right", "右下角", x: 639, y: 359)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        app.buttons[label("Session Options", "会话选项")].tap()
        let disabledMenu = app.buttons["session-hot-corners"]
        XCTAssertTrue(disabledMenu.waitForExistence(timeout: 3))
        XCTAssertFalse(disabledMenu.isEnabled)
        attachScreenshot(app, name: "Observe Hot Corners Disabled " + language)
        app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(try gesturePointers().isEmpty)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testControlledAppleClipboard() throws { try verifyControlledAppleClipboard(language: "en") }
    func testChineseControlledAppleClipboard() throws { try verifyControlledAppleClipboard(language: "zh-Hans") }

    func testControlledSharedClipboard() throws { try verifyControlledSharedClipboard(language: "en") }
    func testChineseControlledSharedClipboard() throws { try verifyControlledSharedClipboard(language: "zh-Hans") }

    private func verifyControlledSharedClipboard(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the Apple clipboard fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        try resetGestureFixture()
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-download" } }
        func openClipboard() {
            app.buttons[label("Session Options", "会话选项")].tap()
            let menu = app.buttons["session-clipboard-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
        }
        openClipboard()
        attachScreenshot(app, name: "Shared Clipboard Menu " + language)
        app.buttons["session-shared-clipboard"].tap()
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-monitor" && $0["enabled"] as? Bool == false } }
        try resetGestureFixture()
        _ = try gestureFixtureData(path: "clipboard-change")
        let stoppedEvents = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-change" } }
        XCTAssertFalse(stoppedEvents.contains { ["clipboard-notification", "clipboard-download"].contains($0["type"] as? String ?? "") })
        openClipboard()
        app.buttons["session-send-clipboard"].tap()
        var events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-upload" } }
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-upload" }?["text"] as? String, "VM clipboard 中文🙂𠮷", "Sharing off must preserve the local clipboard")
        XCTAssertFalse(events.contains { ["key", "clipboard-paste"].contains($0["type"] as? String ?? "") })
        try resetGestureFixture()
        _ = try gestureFixtureData(path: "clipboard-change")
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-change" } }
        openClipboard()
        app.buttons["session-get-clipboard"].tap()
        let fetchedEvents = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-download" } }
        XCTAssertFalse(fetchedEvents.contains { $0["type"] as? String == "clipboard-monitor" && $0["enabled"] as? Bool == true }, "Manual Get must not subscribe again")
        openClipboard()
        app.buttons["session-send-clipboard"].tap()
        events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-upload" } }
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-upload" }?["text"] as? String, "VM remote copy 第二段🙂𠮷")
        XCTAssertFalse(events.contains { ["key", "clipboard-paste"].contains($0["type"] as? String ?? "") })
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        openClipboard()
        XCTAssertFalse(app.buttons["session-send-clipboard"].isEnabled)
        XCTAssertTrue(app.buttons["session-get-clipboard"].isEnabled)
        attachScreenshot(app, name: "Shared Clipboard Observe " + language)
        let packets = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        packets.name = "Shared Clipboard Packets " + language
        add(packets)
    }

    private func verifyControlledAppleClipboard(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the Apple clipboard fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        try resetGestureFixture()
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-download" } }
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let paste = app.buttons[label("Paste Clipboard", "粘贴剪贴板")]
        let toolbar = app.scrollViews["keyboard-toolbar-scroll"]
        func revealPaste() {
            for _ in 0..<6 {
                if paste.exists && toolbar.frame.contains(CGPoint(x: paste.frame.midX, y: paste.frame.midY)) && paste.isHittable { break }
                toolbar.swipeLeft()
            }
            XCTAssertTrue(paste.isHittable)
        }
        revealPaste()
        paste.tap()
        var events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-paste" } }
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-upload" }?["text"] as? String, "VM clipboard 中文🙂𠮷")
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-paste" }?["text"] as? String, "VM clipboard 中文🙂𠮷")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-return-to-library"].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        try resetGestureFixture()
        _ = try gestureFixtureData(path: "clipboard-change")
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-change" && $0["text"] as? String == "VM remote copy 第二段🙂𠮷" } }
        app.buttons["open-sessions"].tap()
        app.buttons["open-session-1"].tap()
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        let refreshed = try waitForFixtureEvents {
            $0.contains { $0["type"] as? String == "clipboard-download" && $0["text"] as? String == "VM remote copy 第二段🙂𠮷" }
        }
        XCTAssertFalse(refreshed.contains { $0["type"] as? String == "ready" }, "Selection must reuse the existing connection")
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        revealPaste()
        paste.tap()
        events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-paste" } }
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-upload" }?["text"] as? String, "VM remote copy 第二段🙂𠮷")
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-paste" }?["text"] as? String, "VM remote copy 第二段🙂𠮷")
        try resetGestureFixture()
        _ = try gestureFixtureData(path: "clipboard-too-large")
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-download" && $0["oversized"] as? Bool == true } }
        paste.tap()
        let alert = app.alerts[label("Unable to Paste", "无法粘贴")]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts[label("Clipboard text is too large. Copy a smaller selection and try again.", "剪贴板文本过长，请缩小复制范围后重试。")].exists)
        let rejectedEvents = try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
        XCTAssertFalse(rejectedEvents.contains { ["key", "clipboard-upload", "clipboard-paste"].contains($0["type"] as? String ?? "") }, "Rejected paste must not fall back to key injection")
        attachScreenshot(app, name: "Clipboard Too Large " + language)
        alert.buttons[label("Close", "关闭")].tap()
        try resetGestureFixture()
        _ = try gestureFixtureData(path: "clipboard-change")
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-download" && $0["text"] as? String == "VM remote copy 第二段🙂𠮷" } }
        paste.tap()
        events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "clipboard-paste" } }
        XCTAssertEqual(events.last { $0["type"] as? String == "clipboard-paste" }?["text"] as? String, "VM remote copy 第二段🙂𠮷")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        XCTAssertFalse(paste.exists, "Observe hides the input toolbar")
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        attachScreenshot(app, name: "Apple Clipboard Observe " + language)
        let packets = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        packets.name = "Received Apple Clipboard " + language
        packets.lifetime = .keepAlways
        add(packets)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledMobileSessionSelection() throws { try verifyMobileSessionSelection(language: "en") }
    func testChineseControlledMobileSessionSelection() throws { try verifyMobileSessionSelection(language: "zh-Hans") }

    private func verifyMobileSessionSelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        try resetGestureFixture()
        func connect() {
            app.buttons[label("Quick Connect", "快速连接")].tap()
            let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
            host.tap(); host.typeText(gestureFixtureHost)
            let port = app.textFields[label("Port", "端口")]
            replacePort(port, with: gestureFixturePort)
            app.buttons[label("Connect", "连接")].tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        }
        func library() {
            app.buttons[label("Session Options", "会话选项")].tap()
            app.buttons["session-return-to-library"].tap()
            XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        }
        func select(_ number: Int) {
            app.buttons["open-sessions"].tap()
            attachScreenshot(app, name: "Open Sessions \(number) " + language)
            app.buttons["open-session-\(number)"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 5))
        }
        func events() throws -> [[String: Any]] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
        }
        connect()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        library()
        connect()
        let ready = try events().filter { $0["type"] as? String == "ready" }
        XCTAssertEqual(ready.count, 2)
        let firstID = try XCTUnwrap(ready.first?["connection"] as? Int)
        let secondID = try XCTUnwrap(ready.last?["connection"] as? Int)
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }
        XCTAssertTrue(try events().filter { $0["type"] as? String == "pointer" && $0["mask"] as? Int == 1 }
            .allSatisfy { $0["connection"] as? Int == secondID })
        library()
        select(1)
        let previousPointers = try gesturePointers().count
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        XCTAssertEqual(try gesturePointers().count, previousPointers, "Restored Observe session must still suppress control")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.count > previousPointers }
        XCTAssertEqual(try events().last(where: { $0["type"] as? String == "pointer" })?["connection"] as? Int, firstID)
        XCTAssertEqual(try events().filter { $0["type"] as? String == "ready" }.count, 2, "Switching must reuse both live sockets")
        XCTAssertTrue(try events().filter { $0["type"] as? String == "disconnected" }.isEmpty)
        attachScreenshot(app, name: "Restored Mobile Session " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        select(2)
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.count > previousPointers + 2 }
        XCTAssertEqual(try events().last(where: { $0["type"] as? String == "pointer" })?["connection"] as? Int, secondID)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-sessions"].isEnabled)
        attachScreenshot(app, name: "Closed Mobile Sessions " + language)
    }

    func testReceivedNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "en") }
    func testReceivedChineseNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "zh-Hans") }
    func testControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "en") }
    func testChineseControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "zh-Hans") }

    func testControlledLandscapeKeyboard() throws { try verifyLandscapeKeyboard(language: "en") }
    func testChineseControlledLandscapeKeyboard() throws { try verifyLandscapeKeyboard(language: "zh-Hans") }

    private func verifyLandscapeKeyboard(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        let desktop = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(desktop.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].isHittable)
        let rotatedScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        rotatedScreen.name = "Full Device Landscape Before Keyboard " + language
        rotatedScreen.lifetime = .keepAlways
        add(rotatedScreen)
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let toolbar = app.scrollViews["keyboard-toolbar-scroll"]
        let type = app.buttons[label("Type", "输入")]
        revealToolbarButton(type, in: toolbar)
        type.tap()
        let field = app.textFields["remote-text-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Type must focus and open the software keyboard")
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertLessThanOrEqual(desktop.frame.maxY, field.frame.minY + 1, "The desktop must reserve space for text entry")
        try resetGestureFixture()
        let text = language == "zh-Hans" ? "中文" : "qa123"
        field.typeText(text)
        app.buttons[label("Send", "发送")].tap()
        let expected = text.unicodeScalars.map { Int($0.value < 256 ? $0.value : 0x01000000 | $0.value) }
        let events = try waitForFixtureEvents { events in
            events.filter { $0["type"] as? String == "key" && $0["down"] as? Int == 1 }.count >= expected.count
        }
        XCTAssertEqual(events.filter { $0["type"] as? String == "key" && $0["down"] as? Int == 1 }.compactMap { $0["key"] as? Int }, expected)
        XCTAssertEqual(field.value as? String, label("Type or paste text to send to Mac...", "输入或粘贴要发送到 Mac 的文本…"))
        attachScreenshot(app, name: "Landscape Software Keyboard " + language)
        let fullScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fullScreen.name = "Full Device Landscape Software Keyboard " + language
        fullScreen.lifetime = .keepAlways
        add(fullScreen)
        app.buttons["remote-text-close"].tap()
        XCTAssertFalse(field.exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 5))
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "en") }
    func testChineseControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "zh-Hans") }

    func testControlledSoftwareKeyboardReturn() throws { try verifySoftwareKeyboardReturn(language: "en") }
    func testChineseControlledSoftwareKeyboardReturn() throws { try verifySoftwareKeyboardReturn(language: "zh-Hans") }

    func testControlledConnectionPasswordReturn() throws { try verifyConnectionPasswordReturn(language: "en") }
    func testChineseControlledConnectionPasswordReturn() throws { try verifyConnectionPasswordReturn(language: "zh-Hans") }

    private func verifyConnectionPasswordReturn(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let password = app.secureTextFields.firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 3))
        password.tap(); password.typeText("synthetic-fixture-only\n")
        XCTAssertTrue(app.textFields["connection-host"].exists, "Invalid forms must stay open after Return")
        XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled)
        let host = app.textFields["connection-host"]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields["connection-port"], with: gestureFixturePort)
        try resetGestureFixture()
        password.tap(); password.typeText("\n")
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10),
                      "Return in a valid password field must start the connection")
        let events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "ready" } }
        XCTAssertEqual(events.filter { $0["type"] as? String == "ready" }.count, 1)
        attachScreenshot(app, name: "Connection Started With Password Return " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifySoftwareKeyboardReturn(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields["connection-host"]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields["connection-port"], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        revealToolbarButton(app.buttons[label("Type", "输入")], in: app.scrollViews["keyboard-toolbar-scroll"])
        app.buttons[label("Type", "输入")].tap()
        let field = app.textFields["remote-text-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let text = language == "zh-Hans" ? "中文" : "qa123"
        let textKeys = text.unicodeScalars.map { Int($0.value < 256 ? $0.value : 0x01000000 | $0.value) }
        func assertKeys(_ expected: [Int]) throws {
            let events = try waitForFixtureEvents { events in
                events.filter { $0["type"] as? String == "key" }.count >= expected.count * 2
            }.filter { $0["type"] as? String == "key" }
            XCTAssertEqual(events.compactMap { $0["key"] as? Int }, expected.flatMap { [$0, $0] })
            XCTAssertEqual(events.compactMap { $0["down"] as? Int }, expected.flatMap { _ in [1, 0] })
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = app.windows.firstMatch.frame
                return orientation == .portrait ? frame.height > frame.width : frame.width > frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            try resetGestureFixture()
            field.typeText(text + "\n")
            try assertKeys(textKeys + [0xFF0D])
            XCTAssertEqual(field.value as? String, label("Type or paste text to send to Mac...", "输入或粘贴要发送到 Mac 的文本…"))
            try resetGestureFixture()
            field.tap()
            field.typeText("\n")
            try assertKeys([0xFF0D])
            try resetGestureFixture()
            field.tap()
            field.typeText(text)
            app.buttons[label("Send", "发送")].tap()
            try assertKeys(textKeys)
            attachScreenshot(app, name: "Software Keyboard Return \(orientation.rawValue) " + language)
        }
        app.buttons["remote-text-close"].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledRelativePointerViewportFollow() throws { try verifyRelativePointerViewportFollow(language: "en") }
    func testChineseControlledRelativePointerViewportFollow() throws { try verifyRelativePointerViewportFollow(language: "zh-Hans") }

    private func verifyRelativePointerViewportFollow(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the controlled RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        func selectMode(_ en: String, _ zh: String) {
            app.buttons[label("Input Mode", "输入模式")].tap()
            app.buttons[label(en, zh)].tap()
        }
        // Probe the same physical point using received absolute coordinates.
        // A relative cursor reaching the desktop edge must change this mapping
        // by revealing the viewport, without toggling Pan View or sending clicks.
        func centerRemoteX() throws -> Int {
            try resetGestureFixture()
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let packets = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
            return try XCTUnwrap(packets.first { $0["mask"] == 1 }?["x"])
        }
        selectMode("Touch", "触控")
        input.pinch(withScale: 2, velocity: 1)
        let initial = try centerRemoteX()
        func moveToEdge(right: Bool) throws {
            selectMode("Trackpad", "触控板")
            try resetGestureFixture()
            for _ in 0..<6 {
                input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
                    thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.8 : 0.2, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0)
            }
            let edgeX = right ? 639 : 0
            let packets = try waitForGesturePointers { $0.last?["x"] == edgeX && $0.last?["mask"] == 0 }
            try attachGesturePackets(packets, name: "Received Relative Pointer " + (right ? "Right " : "Left ") + language)
            let received = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
            received.name = "Relative pointer fixture connections " + (right ? "Right " : "Left ") + language
            received.lifetime = .keepAlways
            add(received)
            attachScreenshot(app, name: "Zoomed Pointer Follow " + (right ? "Right " : "Left ") + language)
            XCTAssertTrue(packets.allSatisfy { $0["mask"] == 0 }, "Pointer following must not synthesize clicks or held buttons")
            selectMode("Touch", "触控")
        }
        try moveToEdge(right: true)
        let right = try centerRemoteX()
        XCTAssertGreaterThan(right, initial + 40, "Moving the relative pointer right must reveal the zoomed desktop's right edge")
        try moveToEdge(right: false)
        let left = try centerRemoteX()
        XCTAssertLessThan(left, initial - 40, "Moving the relative pointer left must reveal the zoomed desktop's left edge")
        XCTAssertGreaterThan(right - left, 100, "Both directions must actually change the viewport mapping")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledDisplaySelection() throws { try verifyControlledDisplaySelection(language: "en") }
    func testChineseControlledDisplaySelection() throws { try verifyControlledDisplaySelection(language: "zh-Hans") }

    func testControlledFullscreenGestures() throws { try verifyControlledFullscreenGestures(language: "en") }
    func testChineseControlledFullscreenGestures() throws { try verifyControlledFullscreenGestures(language: "zh-Hans") }

    private func verifyControlledFullscreenGestures(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let normalOptionsY = app.buttons[label("Session Options", "会话选项")].frame.minY
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        let fullscreenReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.value as? String == label("Full Screen", "全屏")
        }, object: nil)
        guard XCTWaiter.wait(for: [fullscreenReady], timeout: 3) == .completed else {
            XCTFail("One two-finger double-tap must enter fullscreen")
            return
        }
        XCTAssertEqual(input.value as? String, label("Full Screen", "全屏"))
        XCTAssertFalse(app.buttons[label("Session Options", "会话选项")].exists)
        XCTAssertFalse(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        XCTAssertTrue(try gesturePointers().isEmpty, "Fullscreen must not deliver a right click")
        attachScreenshot(app, name: "Controlled Fullscreen " + language)
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        XCTAssertTrue(try gesturePointers().isEmpty)
        attachScreenshot(app, name: "Controlled Fullscreen Restored " + language)
        // Repeated native gestures catch layout publication races; each gesture
        // must succeed once, without corrective taps or remote pointer packets.
        for _ in 0..<3 {
            input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
            let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                input.value as? String == label("Full Screen", "全屏")
            }, object: nil)
            guard XCTWaiter.wait(for: [entered], timeout: 3) == .completed else {
                XCTFail("Repeated fullscreen entry must succeed on one gesture")
                return
            }
            XCTAssertFalse(app.buttons[label("Session Options", "会话选项")].exists)
            input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
            XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
            XCTAssertTrue(try gesturePointers().isEmpty)
        }
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        let observeFullscreenReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.value as? String == label("Full Screen", "全屏")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observeFullscreenReady], timeout: 3), .completed)
        _ = try gestureFixtureData(path: "drop")
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].exists, "A failed fullscreen session must expose recovery and disconnect controls")
        // iOS 27 does not expose the system status bar in this app's XCTest
        // hierarchy. Verify recovery restores the normal safe-area placement,
        // then retain its rendered screenshot for status-bar inspection.
        let recoveryLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(app.buttons[label("Session Options", "会话选项")].frame.minY - normalOptionsY) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recoveryLayout], timeout: 3), .completed,
                       "Recovery restores the same top-control position as normal mode")
        attachScreenshot(app, name: "Controlled Fullscreen Connection Lost " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Reconnect", "重新连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, label("Full Screen", "全屏"), "Reconnect preserves the fullscreen preference")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
        XCTAssertTrue(try gesturePointers().isEmpty, "Observe fullscreen remains a local action")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledAppleNativeDisplaySelection() throws { try verifyControlledAppleNativeDisplaySelection(language: "en") }
    func testChineseControlledAppleNativeDisplaySelection() throws { try verifyControlledAppleNativeDisplaySelection(language: "zh-Hans") }

    func testControlledAppleImageCompression() throws { try verifyControlledAppleImageCompression(language: "en") }
    func testChineseControlledAppleImageCompression() throws { try verifyControlledAppleImageCompression(language: "zh-Hans") }

    private func verifyControlledAppleImageCompression(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the native Apple display fixture in macos27") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { _ = try? gestureFixtureData(path: "native-scaling-release") }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_NATIVE_DISPLAY_PORT"] ?? "6002")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let selector = app.buttons["session-display-selector"]
        selector.tap(); app.buttons[label("Display 2", "显示器 2")].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", label("Display 2", "显示器 2")), object: selector)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)

        func choose(_ en: String, _ zh: String) {
            app.buttons[label("Session Options", "会话选项")].tap()
            let menu = app.buttons["session-image-compression"]
            XCTAssertTrue(menu.waitForExistence(timeout: 3))
            XCTAssertTrue(menu.isEnabled)
            menu.tap(); app.buttons[label(en, zh)].tap()
        }
        func waitForFullFrame(width: Int, height: Int) throws {
            let deadline = Date().addingTimeInterval(6)
            var found = false
            repeat {
                let events = try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
                XCTAssertFalse(events.contains { $0["type"] as? String == "protocol-error" })
                found = events.contains { $0["type"] as? String == "frame" && $0["full"] as? Bool == true &&
                    $0["width"] as? Int == width && $0["height"] as? Int == height }
                if !found { Thread.sleep(forTimeInterval: 0.025) }
            } while !found && Date() < deadline
            XCTAssertTrue(found, "The requested framebuffer must contain fresh pixels")
            let inputReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: selector)
            XCTAssertEqual(XCTWaiter.wait(for: [inputReady], timeout: 3), .completed)
            XCTAssertEqual(selector.value as? String, label("Display 2", "显示器 2"))
        }

        try resetGestureFixture()
        _ = try gestureFixtureData(path: "native-scaling-hold")
        choose("Always", "始终")
        let pending = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: selector)
        XCTAssertEqual(XCTWaiter.wait(for: [pending], timeout: 3), .completed,
                       "Display selection must wait for the resolution change")
        _ = try gestureFixtureData(path: "native-scaling-release")
        try waitForFullFrame(width: 160, height: 180)
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let pointers = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let click = try XCTUnwrap(pointers.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(click["x"])), 208, accuracy: 5)
        XCTAssertEqual(Double(try XCTUnwrap(click["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Native Half Resolution Display 2 " + language)

        try resetGestureFixture()
        choose("Never", "从不")
        try waitForFullFrame(width: 320, height: 360)
        attachScreenshot(app, name: "Native Full Resolution Display 2 " + language)
        try resetGestureFixture()
        choose("Only for Remote Connections", "仅远程连接")
        app.buttons[label("Session Options", "会话选项")].tap()
        let menu = app.buttons["session-image-compression"]
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        XCTAssertEqual(menu.label, label("Image Compression: Only for Remote Connections", "图像压缩：仅远程连接"),
                       "The native menu must show its current policy in the visible title")
        let events = try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
        XCTAssertFalse(events.contains { $0["type"] as? String == "native-scaling-request" },
                       "The LAN fixture must retain full resolution")
        menu.tap(); app.buttons[label("Only for Remote Connections", "仅远程连接")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledAppleNativeDisplaySelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the native Apple display fixture in macos27") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_NATIVE_DISPLAY_PORT"] ?? "6002")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let selector = app.buttons["session-display-selector"]
        for (choice, wireID, expectedX) in [(label("Display 2", "显示器 2"), 20, 208),
                                           (label("All Displays", "全部显示器"), -1, 416),
                                           (label("Display 1", "显示器 1"), 10, 208)] {
            try resetGestureFixture()
            selector.tap()
            XCTAssertTrue(app.buttons[label("Display 1", "显示器 1")].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons[label("Display 2", "显示器 2")].exists)
            app.buttons[choice].tap()
            let confirmed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", choice), object: selector)
            XCTAssertEqual(XCTWaiter.wait(for: [confirmed], timeout: 5), .completed)
            let frameDeadline = Date().addingTimeInterval(3)
            var events = try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
            while !events.contains(where: { $0["type"] as? String == "frame" && $0["full"] as? Bool == true && $0["width"] as? Int == (wireID == -1 ? 640 : 320) }), Date() < frameDeadline {
                Thread.sleep(forTimeInterval: 0.025)
                events = try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
            }
            XCTAssertTrue(events.contains { event in
                guard event["type"] as? String == "native-layout" else { return false }
                return wireID == -1 ? event["selected"] is NSNull : event["selected"] as? Int == wireID
            })
            XCTAssertTrue(events.contains { $0["type"] as? String == "frame" && $0["full"] as? Bool == true && $0["width"] as? Int == (wireID == -1 ? 640 : 320) })
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
            let pointers = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
            let click = try XCTUnwrap(pointers.first { $0["mask"] == 1 })
            XCTAssertEqual(Double(try XCTUnwrap(click["x"])), Double(expectedX), accuracy: 5, "Native selection must use the selected framebuffer's zero origin")
            XCTAssertEqual(Double(try XCTUnwrap(click["y"])), 180, accuracy: 5)
            attachScreenshot(app, name: "Native Apple " + choice + " " + language)
        }
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledDisplaySelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureDisplayFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons["session-display-selector"].tap()
        XCTAssertTrue(app.buttons[label("Display 1", "显示器 1")].waitForExistence(timeout: 3))
        app.buttons[label("Display 2", "显示器 2")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let selected = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(selected["x"])), 528, accuracy: 5, "Visible crop and input must use the selected monitor's width and origin")
        XCTAssertEqual(Double(try XCTUnwrap(selected["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Controlled Selected Right Display " + language)
        app.buttons["session-display-selector"].tap()
        app.buttons[label("All Displays", "全部显示器")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let full = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(full["x"])), 416, accuracy: 5)
        attachScreenshot(app, name: "Controlled Full Desktop " + language)
        app.buttons["session-display-selector"].tap()
        app.buttons[label("Display 1", "显示器 1")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let first = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(first["x"])), 208, accuracy: 5, "Display 1 must restore the first monitor's origin")
        XCTAssertEqual(Double(try XCTUnwrap(first["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Controlled Selected Left Display " + language)
        // The framebuffer and its pixels stay unchanged: the monitor menu must
        // refresh from the layout publication itself, rather than another frame.
        _ = try gestureFixtureData(path: "three-displays")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-displays"].tap()
        XCTAssertTrue(app.buttons[label("Display 3", "显示器 3")].waitForExistence(timeout: 3))
        app.buttons[label("Display 3", "显示器 3")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let changed = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(changed["x"])), 565, accuracy: 5)
        attachScreenshot(app, name: "Controlled Live Layout Change " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledViewportNavigation(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        input.pinch(withScale: 1.5, velocity: 1)
        let center = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        try resetGestureFixture()
        center.tap()
        let before = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-view-menu"].tap()
        let pan = app.buttons[label("Pan View", "移动视图")]
        XCTAssertTrue(pan.waitForExistence(timeout: 3), "Zoomed iOS sessions must expose local viewport navigation")
        guard pan.exists else { return }
        pan.tap()
        attachScreenshot(app, name: "Controlled Local Pan Enabled " + language)
        XCTAssertTrue(pan.waitForNonExistence(timeout: 3), "Choosing local navigation must dismiss the session menu")
        XCTAssertTrue(app.staticTexts[label("Pan · " + gestureFixtureHost, "移动视图 · " + gestureFixtureHost)].waitForExistence(timeout: 3))
        try resetGestureFixture()
        center.press(forDuration: 0.05, thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        center.tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Local panning and taps must not send remote input")
        attachScreenshot(app, name: "Controlled Local Pan " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-view-menu"].tap()
        app.buttons[label("Pan View", "移动视图")].tap()
        center.tap()
        let after = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertLessThan(after, before - 20, "Local panning must actually move the displayed remote viewport")
        try attachGesturePackets(try gesturePointers(), name: "Received Touch After Local Pan " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3), "Observe must retain local navigation")
        try resetGestureFixture()
        input.pinch(withScale: 1.3, velocity: 1)
        center.press(forDuration: 0.4, thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        center.tap()
        XCTAssertTrue(try gesturePointers().isEmpty)
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        attachScreenshot(app, name: "Controlled Observe Navigation " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        center.tap()
        let observed = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertGreaterThan(observed, after + 30, "Observe navigation must move the viewport while suppressing remote input")
        try attachGesturePackets(try gesturePointers(), name: "Received Touch After Observe Navigation " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-view-menu"].tap()
        app.buttons[label("Fit to Window", "适应窗口")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let fitted = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertEqual(Double(fitted), 416, accuracy: 5, "Fit must reset both zoom and viewport offset")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledConnectionRecovery(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        try resetGestureFixture()
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let oldConnection = try lastFixtureConnection()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        input.pinch(withScale: 1.5, velocity: 1)
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let shift = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Shift")).firstMatch
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        shift.tap()
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "key" && $0["key"] as? Int == 65505 && $0["down"] as? Int == 1 } }
        _ = try gestureFixtureData(path: "drop")
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Controlled Remote Connection Lost " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Reconnect", "重新连接")].tap()
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let newConnection = try lastFixtureConnection()
        XCTAssertNotEqual(newConnection, oldConnection, "Recovery must establish a new TCP session")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "pointer" && $0["connection"] as? Int == newConnection && $0["mask"] as? Int == 1 } }
        let click = try XCTUnwrap(events.first { $0["type"] as? String == "pointer" && $0["connection"] as? Int == newConnection && $0["mask"] as? Int == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(click["x"] as? Int)), 384, accuracy: 5, "Recovery must preserve zoom and touch mode")
        shift.tap()
        let escape = app.buttons["esc"]
        let keyboardScroll = app.scrollViews["keyboard-toolbar-scroll"]
        var scrollGeometry: [String] = []
        for _ in 0..<3 {
            let bounds = keyboardScroll.frame
            let keyFrame = escape.frame
            scrollGeometry.append("viewport=\(bounds); esc=\(keyFrame)")
            let center = CGPoint(x: keyFrame.midX, y: keyFrame.midY)
            if !keyFrame.isEmpty && bounds.contains(center) { break }
            // CGRect.contains excludes its maximum edge. In Chinese the Esc
            // midpoint can equal maxX exactly, so reveal it with a leftward drag.
            // An empty clipped frame also needs a leftward drag in this default
            // toolbar, where Esc follows Shift.
            let direction: CGFloat = keyFrame.isEmpty ? -1 : (center.x >= bounds.maxX ? -1 : 1)
            let distance = keyFrame.isEmpty ? bounds.width * 0.35 : min(bounds.width * 0.4, max(40, abs(center.x - bounds.midX)))
            let startX: CGFloat = direction < 0 ? 0.8 : 0.2
            let start = keyboardScroll.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            let end = keyboardScroll.coordinate(withNormalizedOffset: CGVector(dx: startX + direction * distance / bounds.width, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let geometry = XCTAttachment(string: scrollGeometry.joined(separator: "\n"))
        geometry.name = "Recovery Toolbar Scroll Geometry " + language
        geometry.lifetime = .keepAlways
        add(geometry)
        XCTAssertTrue(keyboardScroll.frame.contains(CGPoint(x: escape.frame.midX, y: escape.frame.midY)))
        XCTAssertTrue(escape.isHittable)
        escape.tap()
        _ = try waitForFixtureEvents { events in
            let fresh = events.filter { $0["connection"] as? Int == newConnection && $0["type"] as? String == "key" }
            return fresh.contains { $0["key"] as? Int == 65505 && $0["down"] as? Int == 1 } && fresh.contains { $0["key"] as? Int == 65505 && $0["down"] as? Int == 0 }
        }
        let packets = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        packets.name = "Received New Session Input " + language
        packets.lifetime = .keepAlways
        add(packets)
        attachScreenshot(app, name: "Controlled Remote Reconnected " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    private func lastFixtureConnection() throws -> Int {
        let events = try fixtureEvents()
        return try XCTUnwrap(events.last { $0["type"] as? String == "ready" }?["connection"] as? Int)
    }

    private func fixtureEvents() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
    }

    private func waitForFixtureEvents(_ predicate: ([[String: Any]]) -> Bool) throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(3)
        var events = try fixtureEvents()
        while !predicate(events), Date() < deadline { Thread.sleep(forTimeInterval: 0.025); events = try fixtureEvents() }
        if !predicate(events) {
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: events, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "Received Fixture Events At Failed Assertion"
            attachment.lifetime = .keepAlways
            add(attachment)
            attachScreenshot(XCUIApplication(), name: "Fixture Assertion Failure UI")
        }
        XCTAssertTrue(predicate(events), "Expected received packets must reach the new session")
        return events
    }

    private func verifyReceivedNativeGestures(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the loopback gesture RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.label, label("Remote desktop canvas", "远程桌面画布"))
        let fittedCanvasHeight = input.frame.height
        XCTAssertGreaterThan(fittedCanvasHeight, 0)
        let center = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        try resetGestureFixture()
        center.tap()
        var events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 1)
        try attachGesturePackets(events, name: "Received Single Click")
        try resetGestureFixture()
        center.doubleTap()
        events = try waitForGesturePointers { $0.filter { $0["mask"] == 1 }.count >= 2 && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 2, "Double tap must deliver two clicks without triggering zoom")
        try attachGesturePackets(events, name: "Received Double Click")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 1, numberOfTouches: 2)
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 4 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 4 }.count, 1)
        try attachGesturePackets(events, name: "Received Two Finger Right Click")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 2 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 2 }.count, 1)
        try attachGesturePackets(events, name: "Received Three Finger Middle Click")
        try resetGestureFixture()
        let end = input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        center.press(forDuration: 0.4, thenDragTo: end)
        events = try waitForGesturePointers { $0.filter { $0["mask"] == 1 }.count > 1 && $0.last?["mask"] == 0 }
        XCTAssertGreaterThan(Set(events.filter { $0["mask"] == 1 }.compactMap { $0["x"] }).count, 1, "The server must receive movement while the button remains held")
        try attachGesturePackets(events, name: "Received Held Button Drag")

        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let point = input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        try resetGestureFixture()
        point.tap()
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let beforeZoom = try XCTUnwrap(events.first { $0["mask"] == 1 }?["x"])
        XCTAssertEqual(Double(beforeZoom), 416, accuracy: 4)
        try attachGesturePackets(events, name: "Received Direct Touch Before Zoom")
        input.pinch(withScale: 1.5, velocity: 1)
        try resetGestureFixture()
        point.tap()
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let afterZoom = try XCTUnwrap(events.first { $0["mask"] == 1 }?["x"])
        XCTAssertLessThan(afterZoom, beforeZoom - 10, "Pinch must change direct-touch mapping to the enlarged canvas")
        try attachGesturePackets(events, name: "Received Direct Touch After Zoom")
        attachScreenshot(app, name: "Received Gesture Desktop After Pinch")

        // The reported phone regression uses the trackpad cursor after zoom,
        // which is a different path from direct-touch coordinate conversion.
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Trackpad", "触控板")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 1, "Zoomed trackpad must deliver exactly one mouse-down and release")
        try attachGesturePackets(events, name: "Received Trackpad Single Click After Zoom")

        // Stay in Trackpad throughout the same pinch-out/pinch-in sequence
        // reported on the phone. Validate the visible zoom as well as the wire
        // pair, so unchanged zoom or a local-only arrow cannot satisfy the test.
        let pressedPosition = try XCTUnwrap(events.first { $0["mask"] == 1 })
        var releasedPosition = pressedPosition
        releasedPosition["mask"] = 0
        for cycle in 1...2 {
            for enlarged in [false, true] {
                try resetGestureFixture()
                input.pinch(withScale: enlarged ? 1.5 : 0.5, velocity: enlarged ? 1 : -1)
                if enlarged {
                    XCTAssertGreaterThan(input.frame.height, fittedCanvasHeight + 16, "Trackpad pinch-in must enlarge the visible desktop")
                } else {
                    XCTAssertEqual(input.frame.height, fittedCanvasHeight, accuracy: 4, "Trackpad pinch-out must restore the fitted desktop")
                }
                input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
                XCTAssertEqual(events, [pressedPosition, releasedPosition], "Each pinch-cycle tap must preserve the cursor and emit exactly one click without wheel or other button events")
                try attachGesturePackets(events, name: "Received Trackpad Pinch " + (enlarged ? "In " : "Out ") + "Cycle \(cycle) " + language)
            }
        }
        attachScreenshot(app, name: "Trackpad After Repeated Pinch " + language)

        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        frame.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Observe must suppress actual received input")
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    private func replacePort(_ field: XCUIElement, with value: String) {
        // Numeric fields may ignore Command+A, and tapping a short value can
        // put the caret before its first digit. Move through the existing text
        // before deleting so replacing "0" cannot accidentally append to it.
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        for _ in current {
            field.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "The validated fixture port must be entered before connecting")
    }

    private var gestureFixtureHost: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_HOST"] ?? "127.0.0.1"
    }

    private var gestureFixturePort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_RFB_PORT"] ?? "5999"
    }

    private var gestureDisplayFixturePort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DISPLAY_PORT"] ?? "6000"
    }

    private var gestureInspectionPort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_HTTP_PORT"] ?? "8768"
    }

    private func gesturePointers() throws -> [[String: Int]] {
        let value = try JSONSerialization.jsonObject(with: gestureFixtureData(path: "events"))
        return try XCTUnwrap(value as? [[String: Any]]).filter { $0["type"] as? String == "pointer" }.map {
            ["mask": $0["mask"] as? Int ?? -1, "x": $0["x"] as? Int ?? -1, "y": $0["y"] as? Int ?? -1]
        }
    }

    private func resetGestureFixture() throws {
        _ = try gestureFixtureData(path: "reset")
    }

    private func gestureFixtureData(path: String) throws -> Data {
        let began = ProcessInfo.processInfo.systemUptime
        let received = expectation(description: "Gesture fixture response")
        let response = GestureFixtureResponse()
        let task = URLSession.shared.dataTask(with: URL(string: "http://" + gestureFixtureHost + ":" + gestureInspectionPort + "/" + path)!) { data, http, error in
            if let error { response.set(.failure(error)) }
            else if let data, (http as? HTTPURLResponse)?.statusCode == 200 { response.set(.success(data)) }
            else { response.set(.failure(URLError(.badServerResponse))) }
            received.fulfill()
        }
        task.resume()
        defer { task.cancel() }
        // Collect diagnostics before recording a failure: continueAfterFailure
        // is false, so XCTestCase.wait would otherwise abort before attachment.
        let outcome = XCTWaiter.wait(for: [received], timeout: 3)
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        if outcome != .completed || elapsed > 1 || response.get() == nil {
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
                "path": path, "elapsedSeconds": elapsed, "responsePresent": response.get() != nil,
                "waitOutcome": outcome.rawValue
            ], options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "Slow controlled fixture response"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(outcome, .completed, "Controlled fixture must respond within the unchanged three-second deadline")
        guard outcome == .completed else { throw URLError(.timedOut) }
        return try XCTUnwrap(response.get()).get()
    }

    private func attachGesturePackets(_ packets: [[String: Int]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: packets, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForGesturePointers(_ predicate: ([[String: Int]]) -> Bool) throws -> [[String: Int]] {
        let deadline = Date().addingTimeInterval(3)
        var events = try gesturePointers()
        while !predicate(events), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
            events = try gesturePointers()
        }
        if !predicate(events) {
            try attachGesturePackets(events, name: "Received Pointer Packets At Failed Gesture Assertion")
            let canvas = XCUIApplication().descendants(matching: .any)["remote-desktop-input"].firstMatch
            if canvas.exists, let diagnostics = canvas.value as? String {
                let attachment = XCTAttachment(string: diagnostics)
                attachment.name = "Native Boundary Recognition Diagnostics"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCTAssertTrue(predicate(events), "Expected gesture packets must reach the fixture")
        return events
    }

    func testConnectionLinkPreservesQuickConnectDraft() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_URL_ROUTING_QA"] == "1" else {
            throw XCTSkip("Requires an external simulator URL delivery")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Quick Connect"].tap()
        let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText("draft-qa.invalid")
        print("AETHERSCREENS_URL_QA_READY")
        // The driver delivers a system URL while this form remains open.
        let deliveryWindow = expectation(description: "System URL delivery window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { deliveryWindow.fulfill() }
        wait(for: [deliveryWindow], timeout: 20)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmation = springboard.alerts.firstMatch
        if confirmation.exists {
            XCTAssertTrue(confirmation.label.contains("AetherScreens"))
            let open = confirmation.buttons["Open"].exists ? confirmation.buttons["Open"] : confirmation.buttons["打开"]
            XCTAssertTrue(open.exists)
            open.tap()
        }
        XCTAssertTrue(app.navigationBars["Quick Connect"].exists)
        XCTAssertEqual(host.value as? String, "draft-qa.invalid")
        attachScreenshot(app, name: "Connection Link Preserves Draft")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Observe · Link QA"].exists)
        XCTAssertFalse(app.buttons["Show Keyboard"].isEnabled)
        attachScreenshot(app, name: "Connection Link Observe Session")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Quick Connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Connect to Link QA"].exists)
    }

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
        if let port = ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_ONLY_PORT"] {
            replacePort(app.textFields[label("Port", "端口")], with: port)
        }
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

    func testIPadPencilGestureSettings() throws { try verifyIPadPencilGestureSettings(language: "en") }
    func testChineseIPadPencilGestureSettings() throws { try verifyIPadPencilGestureSettings(language: "zh-Hans") }

    private func verifyIPadPencilGestureSettings(language: String) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires an iPad simulator or device") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        let quick = app.buttons[label("Quick Connect", "快速连接")]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText("pencil-settings-qa.invalid")
        app.buttons[label("Connect", "连接")].tap()
        let options = app.buttons[label("Session Options", "会话选项")]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        func openSettings() {
            options.tap()
            app.buttons["session-customize-keyboard"].tap()
            XCTAssertTrue(app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")].waitForExistence(timeout: 5))
        }
        func reveal(_ picker: XCUIElement) {
            let window = app.windows.firstMatch
            for _ in 0..<10 {
                if picker.exists && window.frame.insetBy(dx: 0, dy: 100).contains(picker.frame) && picker.isHittable { return }
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(picker.exists && picker.isHittable, "Pencil setting must be reachable")
        }
        openSettings()
        let doubleTap = app.buttons["pencil-double-tap-action"]
        let squeeze = app.buttons["pencil-squeeze-action"]
        reveal(doubleTap)
        XCTAssertTrue(doubleTap.label.contains(label("None", "无")))
        doubleTap.tap()
        app.buttons[label("Secondary Click", "右键单击")].tap()
        XCTAssertTrue(doubleTap.label.contains(label("Secondary Click", "右键单击")))
        reveal(squeeze)
        squeeze.tap()
        app.buttons[label("Toggle Toolbar Visibility", "显示／隐藏工具栏")].tap()
        XCTAssertTrue(squeeze.label.contains(label("Toggle Toolbar Visibility", "显示／隐藏工具栏")))
        attachScreenshot(app, name: "iPad Pencil Settings " + language)
        app.buttons[label("Done", "完成")].tap()
        XCTAssertTrue(options.isHittable)
        openSettings()
        reveal(doubleTap)
        XCTAssertTrue(doubleTap.label.contains(label("Secondary Click", "右键单击")), "Reopening settings must retain the double-tap mapping")
        reveal(squeeze)
        XCTAssertTrue(squeeze.label.contains(label("Toggle Toolbar Visibility", "显示／隐藏工具栏")), "Reopening settings must retain squeeze mapping")
        squeeze.tap(); app.buttons[label("None", "无")].tap()
        reveal(doubleTap)
        doubleTap.tap(); app.buttons[label("None", "无")].tap()
        attachScreenshot(app, name: "iPad Pencil Settings Restored " + language)
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
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
        func revealSwitch(_ element: XCUIElement) {
            let window = app.windows.firstMatch
            for _ in 0..<12 {
                let viewport = window.frame.insetBy(dx: 0, dy: 110)
                if element.exists {
                    let thumb = CGPoint(x: element.frame.minX + element.frame.width * 0.9, y: element.frame.midY)
                    if viewport.contains(thumb) && element.isHittable { return }
                    let downward = thumb.y < viewport.minY
                    window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.4 : 0.7)).press(forDuration: 0.05,
                        thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: downward ? 0.65 : 0.45)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
                } else { app.swipeUp() }
            }
            XCTAssertTrue(element.exists && element.isHittable)
        }
        let swap = app.switches["hardware-swap-command-control"]
        revealSwitch(swap)
        XCTAssertEqual(swap.value as? String, "0")
        swap.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(swap.value as? String, "1")
        let alternate = app.switches["hardware-command-backslash"]
        revealSwitch(alternate)
        XCTAssertEqual(alternate.value as? String, "0")
        let beforeTap = "frame=\(alternate.frame); hittable=\(alternate.isHittable); value=\(String(describing: alternate.value))\n\(alternate.debugDescription)"
        // The labeled SwiftUI toggle exposes a native switch inside its row.
        // Target that control directly instead of estimating its position from
        // the row width, which includes the localized label and empty space.
        XCTAssertEqual(alternate.switches.count, 1)
        let nativeSwitch = alternate.switches.firstMatch
        XCTAssertTrue(nativeSwitch.isHittable)
        nativeSwitch.tap()
        // Snapshot the first value before collecting diagnostics, preserving the
        // original assertion timing when the native toggle does not respond.
        let valueAfterTap = alternate.value as? String
        let switchState = XCTAttachment(string: "before: \(beforeTap)\nafter: frame=\(alternate.frame); value=\(String(describing: valueAfterTap))\n\(alternate.debugDescription)")
        switchState.name = "Hardware Command Backslash Switch State " + language
        switchState.lifetime = .keepAlways
        add(switchState)
        XCTAssertEqual(valueAfterTap, "1")
        let command = app.switches["keyboard-visible-Cmd"]
        revealSwitch(command)
        XCTAssertTrue(command.exists)
        attachScreenshot(app, name: "Cmd Visibility Switch Ready " + language)
        command.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(command.value as? String, "0")
        attachScreenshot(app, name: "Narrow Keyboard Customization")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cmd")).count, 0)
        let sessionOptions = app.buttons[label("Session Options", "会话选项")]
        let keyboardToolbar = app.scrollViews["keyboard-toolbar-scroll"]
        XCTAssertTrue(sessionOptions.exists && sessionOptions.isHittable)
        XCTAssertTrue(keyboardToolbar.exists)
        XCTAssertFalse(keyboardToolbar.frame.intersects(sessionOptions.frame),
                       "Top keyboard toolbar must leave session controls visible and tappable")
        attachScreenshot(app, name: "Customized Keyboard Session")
        sessionOptions.tap()
        app.buttons["session-customize-keyboard"].tap()
        if !reopenedToolbar.waitForExistence(timeout: 5) {
            let menuItem = app.buttons["session-customize-keyboard"]
            if menuItem.exists && menuItem.isHittable { menuItem.tap() }
        }
        XCTAssertTrue(reopenedToolbar.waitForExistence(timeout: 5))
        revealSwitch(swap)
        XCTAssertEqual(swap.value as? String, "1")
        revealSwitch(alternate)
        XCTAssertEqual(alternate.value as? String, "1")
        revealSwitch(command)
        XCTAssertEqual(command.value as? String, "0")
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
        app.textFields["端口"].tap()
        XCTAssertEqual(app.buttons["connection-dismiss-keyboard"].label, "完成")
        dismissConnectionKeyboard(in: app)
        attachScreenshot(app, name: "Chinese Quick Connect")
        app.buttons["取消"].tap()
        app.buttons["更多操作"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["app-language"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Switching language must preserve the open settings sheet")
        XCTAssertTrue(app.staticTexts["Saved Computers"].waitForExistence(timeout: 5),
                      "The open storage section must follow the manual language selection")
        let storage = app.buttons["library-storage"]
        XCTAssertTrue(storage.waitForExistence(timeout: 5))
        XCTAssertEqual(storage.value as? String, "On This Device")
        XCTAssertTrue(app.staticTexts["Saved computers stay on this device."].exists)
        XCTAssertFalse(app.staticTexts["已保存的电脑"].exists)
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
        app.buttons["More Actions"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved Computers"].exists)
        XCTAssertEqual(app.buttons["library-storage"].value as? String, "On This Device")
        app.buttons["Done"].tap()
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
        verifyQuickConnectValidationAndTemporarySession(language: "en")
    }

    func testChineseQuickConnectValidationAndTemporarySession() {
        verifyQuickConnectValidationAndTemporarySession(language: "zh-Hans")
    }

    private func verifyQuickConnectValidationAndTemporarySession(language: String) {
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        let temporaryHost = "quick-qa-\(UUID().uuidString.prefix(8).lowercased()).invalid"
        let savedComputer = app.buttons[label("Connect to \(temporaryHost)", "连接到 \(temporaryHost)")]
        XCTAssertFalse(savedComputer.exists)
        let quick = app.buttons[label("Quick Connect", "快速连接")]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        XCTAssertTrue(app.navigationBars[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        let connect = app.buttons[label("Connect", "连接")]
        XCTAssertFalse(connect.isEnabled)
        let name = app.textFields["connection-name"]
        XCTAssertFalse(name.exists)
        let address = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        address.tap()
        address.typeText(temporaryHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: "0")
        XCTAssertFalse(connect.isEnabled)
        replacePort(port, with: "5900")
        XCTAssertTrue(connect.isEnabled)
        let account = app.textFields[label("Username (Mac account, optional)", "用户名（Mac 账户，可选）")]
        account.tap()
        account.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields[label("Mac Account Password", "Mac 账户密码")].exists)
        dismissConnectionKeyboard(in: app)
        app.swipeUp()
        let save = app.switches[label("Save Computer", "保存电脑")]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.value as? String, "0")
        attachScreenshot(app, name: "Quick Connect Save Toggle Ready " + language)
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(save.value as? String, "1")
        app.swipeDown()
        let nameExistsAfterScroll = name.exists
        let nameSnapshot = XCTAttachment(string: "Name exists: \(nameExistsAfterScroll)\n" + app.debugDescription)
        nameSnapshot.name = "Quick Connect Name Field After Save " + language
        nameSnapshot.lifetime = .keepAlways
        add(nameSnapshot)
        XCTAssertTrue(nameExistsAfterScroll)
        XCTAssertEqual(name.label, label("Name (e.g. Studio Mac)", "名称（如 工作室 Mac）"))
        app.swipeUp()
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(save.value as? String, "0")
        XCTAssertFalse(name.exists)
        attachScreenshot(app, name: "Quick Connect " + language)
        connect.tap()
        XCTAssertTrue(app.buttons[label("Disconnect", "断开连接")].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 30))
        attachScreenshot(app, name: "Temporary Connection Error " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertFalse(savedComputer.exists)
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
        dismissConnectionKeyboard(in: app)
        attachScreenshot(app, name: "Add Computer")
        app.buttons["Cancel"].tap()

        app.buttons["More Actions"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
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
        let editPort = app.textFields["Port"]
        editPort.tap()
        dismissConnectionKeyboard(in: app)
        XCTAssertEqual(editPort.value as? String, "5999")
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
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10),
                      "A failed connection must not count as a received desktop")
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

    private func dismissConnectionKeyboard(in app: XCUIApplication) {
        let done = app.buttons["connection-dismiss-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Connection Keyboard Dismiss Button")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
                      "Done must dismiss the keyboard before operating the form")
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

    func testSavedComputerStorageAndRecovery() throws { try verifySavedComputerStorage(language: "en") }
    func testChineseSavedComputerStorageAndRecovery() throws { try verifySavedComputerStorage(language: "zh-Hans") }

    private func verifySavedComputerStorage(language: String) throws {
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        XCTAssertTrue(app.buttons[label("More Actions", "更多操作")].waitForExistence(timeout: 10))
        app.buttons[label("More Actions", "更多操作")].tap()
        app.buttons[label("Settings", "设置")].tap()
        XCTAssertTrue(app.navigationBars[label("Settings", "设置")].waitForExistence(timeout: 5))
        let storage = app.buttons["library-storage"]
        XCTAssertTrue(storage.waitForExistence(timeout: 5))
        storage.tap()
        app.buttons[label("On This Device", "本机")].tap()
        XCTAssertEqual(storage.value as? String, label("On This Device", "本机"))
        XCTAssertFalse(app.buttons["library-sync-now"].exists)
        attachScreenshot(app, name: "Local Storage " + language)
        storage.tap()
        app.buttons["iCloud"].tap()
        let unavailable = label("iCloud synchronization is unavailable in this build.", "当前版本暂不支持 iCloud 同步。")
        XCTAssertTrue(app.staticTexts[unavailable].waitForExistence(timeout: 5))
        XCTAssertEqual(storage.value as? String, "iCloud")
        let retry = app.buttons["library-sync-now"]
        XCTAssertTrue(retry.exists && retry.isEnabled)
        XCTAssertEqual(retry.label, label("Retry Sync", "重试同步"))
        retry.tap()
        XCTAssertTrue(app.staticTexts[unavailable].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Unavailable Cloud Storage " + language)
        storage.tap()
        app.buttons[label("On This Device", "本机")].tap()
        XCTAssertFalse(app.buttons["library-sync-now"].exists)
        app.buttons[label("Done", "完成")].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons[label("More Actions", "更多操作")].waitForExistence(timeout: 10))
        app.buttons[label("More Actions", "更多操作")].tap()
        app.buttons[label("Settings", "设置")].tap()
        XCTAssertTrue(storage.waitForExistence(timeout: 5))
        XCTAssertEqual(storage.value as? String, label("On This Device", "本机"))
        XCTAssertFalse(app.buttons["library-sync-now"].exists)
        attachScreenshot(app, name: "Restored Local Storage " + language)
        app.buttons[label("Done", "完成")].tap()
    }

    private func makeApp(language: String = "en", boundaryDiagnostics: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        if boundaryDiagnostics && ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" {
            app.launchEnvironment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] = "1"
        }
        if ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" &&
           ProcessInfo.processInfo.environment["AETHERSCREENS_INPUT_DIAGNOSTICS_QA"] == "1" {
            app.launchEnvironment["AETHERSCREENS_INPUT_DIAGNOSTICS"] = "1"
        }
        return app
    }

    private func revealToolbarButton(_ button: XCUIElement, in toolbar: XCUIElement) {
        for _ in 0..<20 {
            let viewport = toolbar.frame
            if button.exists {
                let frame = button.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                // Offscreen isHittable can raise an XCTest error. Full swipes
                // also overshoot narrow controls, oscillating past the target.
                if viewport.insetBy(dx: 12, dy: 0).contains(center), button.isHittable { return }
                let distance = frame.midX - viewport.midX
                let fraction = max(-0.35, min(0.35, distance / max(1, viewport.width)))
                toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
                    thenDragTo: toolbar.coordinate(withNormalizedOffset: CGVector(dx: 0.5 - fraction, dy: 0.5)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                toolbar.swipeLeft(velocity: .slow)
            }
        }
        XCTAssertTrue(button.exists, "Toolbar action must exist")
        XCTAssertTrue(toolbar.frame.contains(CGPoint(x: button.frame.midX, y: button.frame.midY)), "Toolbar action must scroll into view")
        XCTAssertTrue(button.isHittable, "Visible toolbar action must remain tappable")
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
            replacePort(port, with: "5999")
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
        // On the current simulator, app.screenshot() crops landscape pixels
        // using portrait bounds. Preserve the actual device composition.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class GestureFixtureResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    func set(_ value: Result<Data, Error>) { lock.lock(); result = value; lock.unlock() }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return result }
}
