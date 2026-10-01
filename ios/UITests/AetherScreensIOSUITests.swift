import XCTest

final class AetherScreensIOSUITests: XCTestCase {
    func testReceivedNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "en") }
    func testReceivedChineseNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "zh-Hans") }
    func testControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "en") }
    func testChineseControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "zh-Hans") }

    func testControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "en") }
    func testChineseControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "zh-Hans") }

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
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields[label("Port", "端口")]
        port.tap(); port.typeKey("a", modifierFlags: .command); port.typeText("5999")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
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

    private func verifyControlledDisplaySelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields[label("Port", "端口")]
        port.tap(); port.typeKey("a", modifierFlags: .command); port.typeText("6000")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Session Options", "会话选项")].tap()
        XCTAssertTrue(app.buttons[label("Display 1", "显示器 1")].waitForExistence(timeout: 3))
        app.buttons[label("Display 2", "显示器 2")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let selected = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(selected["x"])), 528, accuracy: 5, "Visible crop and input must use the selected monitor's width and origin")
        XCTAssertEqual(Double(try XCTUnwrap(selected["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Controlled Selected Right Display " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("All Displays", "全部显示器")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let full = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(full["x"])), 416, accuracy: 5)
        attachScreenshot(app, name: "Controlled Full Desktop " + language)
        // The framebuffer and its pixels stay unchanged: the monitor menu must
        // refresh from the layout publication itself, rather than another frame.
        _ = try gestureFixtureData(path: "three-displays")
        app.buttons[label("Session Options", "会话选项")].tap()
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
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields[label("Port", "端口")]
        port.tap(); port.typeKey("a", modifierFlags: .command); port.typeText("5999")
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
        let pan = app.buttons[label("Pan View", "移动视图")]
        XCTAssertTrue(pan.waitForExistence(timeout: 3), "Zoomed iOS sessions must expose local viewport navigation")
        guard pan.exists else { return }
        pan.tap()
        XCTAssertTrue(app.staticTexts[label("Pan · 127.0.0.1", "移动视图 · 127.0.0.1")].exists)
        try resetGestureFixture()
        center.press(forDuration: 0.05, thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        center.tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Local panning and taps must not send remote input")
        attachScreenshot(app, name: "Controlled Local Pan " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
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
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields[label("Port", "端口")]
        port.tap(); port.typeKey("a", modifierFlags: .command); port.typeText("5999")
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
        app.buttons["esc"].tap()
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
        host.tap(); host.typeText("127.0.0.1")
        let port = app.textFields[label("Port", "端口")]
        port.tap(); port.typeKey("a", modifierFlags: .command); port.typeText("5999")
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.label, label("Remote desktop canvas", "远程桌面画布"))
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

        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        frame.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Observe must suppress actual received input")
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
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
        let received = expectation(description: "Gesture fixture response")
        let response = GestureFixtureResponse()
        let task = URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:8768/" + path)!) { data, http, error in
            if let error { response.set(.failure(error)) }
            else if let data, (http as? HTTPURLResponse)?.statusCode == 200 { response.set(.success(data)) }
            else { response.set(.failure(URLError(.badServerResponse))) }
            received.fulfill()
        }
        task.resume()
        wait(for: [received], timeout: 3)
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

private final class GestureFixtureResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    func set(_ value: Result<Data, Error>) { lock.lock(); result = value; lock.unlock() }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return result }
}
