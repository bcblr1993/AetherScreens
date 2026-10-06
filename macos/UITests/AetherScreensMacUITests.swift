import XCTest

/// Runs against the explicitly selected app on the authorized test Mac.
@MainActor
final class AetherScreensMacUITests: XCTestCase {
    func testEnglishQuickConnectValidation() throws { try checkQuickConnect(language: "en") }
    func testChineseQuickConnectValidation() throws { try checkQuickConnect(language: "zh-Hans") }

    func testReceivedNativeMacInput() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let path = try XCTUnwrap(env["AETHERSCREENS_MAC_QA_APP_PATH"])
        let port = try XCTUnwrap(env["AETHERSCREENS_MAC_QA_RFB_PORT"])
        let inspection = try XCTUnwrap(env["AETHERSCREENS_MAC_QA_HTTP_PORT"])
        let base = "http://127.0.0.1:" + inspection
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-com.aethernative.aetherscreens.language", "en"]
        app.launch()
        defer { app.terminate() }
        let quick = app.buttons["Quick Connect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 15))
        quick.click()
        let host = app.sheets.textFields.element(boundBy: 0)
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.click(); host.typeText("127.0.0.1")
        let portField = app.sheets.textFields.element(boundBy: 1)
        portField.click(); portField.typeKey("a", modifierFlags: .command)
        portField.typeText(port)
        app.buttons["Connect"].click()
        let input = app.descendants(matching: .any)["Remote desktop input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        func fixture(_ path: String) throws -> Data {
            let completed = expectation(description: "Controlled Mac fixture response")
            let response = MacFixtureResponse()
            let task = URLSession.shared.dataTask(with: try XCTUnwrap(URL(string: base + path))) { data, http, error in
                if let error { response.set(.failure(error)) }
                else if let data, (http as? HTTPURLResponse)?.statusCode == 200 { response.set(.success(data)) }
                else { response.set(.failure(URLError(.badServerResponse))) }
                completed.fulfill()
            }
            task.resume()
            defer { task.cancel() }
            wait(for: [completed], timeout: 3)
            return try XCTUnwrap(response.get()).get()
        }
        func reset() throws { _ = try fixture("/reset") }
        func received(_ predicate: ([[String: Any]]) -> Bool) throws -> [[String: Any]] {
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            var events: [[String: Any]] = []
            repeat {
                events = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("/events")) as? [[String: Any]])
                if predicate(events) { return events }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            } while ProcessInfo.processInfo.systemUptime < deadline
            XCTAssertTrue(predicate(events), "Expected native input must reach the fixture")
            return events
        }
        func attach(_ events: [[String: Any]], name: String) throws {
            let packets = XCTAttachment(data: try JSONSerialization.data(withJSONObject: events), uniformTypeIdentifier: "public.json")
            packets.name = name
            packets.lifetime = .keepAlways
            add(packets)
        }
        let center = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        try reset()
        center.click()
        var events = try received { $0.contains { $0["mask"] as? Int == 1 } && $0.last { $0["type"] as? String == "pointer" }?["mask"] as? Int == 0 }
        XCTAssertEqual(events.filter { $0["mask"] as? Int == 1 }.count, 1)
        try attach(events, name: "Received native Mac click")
        try reset()
        center.rightClick()
        events = try received { $0.contains { $0["mask"] as? Int == 4 } && $0.last { $0["type"] as? String == "pointer" }?["mask"] as? Int == 0 }
        XCTAssertTrue(events.contains { $0["mask"] as? Int == 4 })
        try attach(events, name: "Received native Mac right click")
        try reset()
        center.click(forDuration: 0.2, thenDragTo:
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
        events = try received { $0.filter { $0["mask"] as? Int == 1 }.count > 1 && $0.last { $0["type"] as? String == "pointer" }?["mask"] as? Int == 0 }
        let held = events.filter { $0["mask"] as? Int == 1 }
        XCTAssertGreaterThan(held.count, 1)
        XCTAssertNotEqual(held.first?["x"] as? Int, held.last?["x"] as? Int)
        try attach(events, name: "Received native Mac drag")
        try reset()
        app.typeText("qa")
        events = try received {
            $0.contains { $0["key"] as? Int == 113 && $0["down"] as? Int == 0 } &&
            $0.contains { $0["key"] as? Int == 97 && $0["down"] as? Int == 0 }
        }
        XCTAssertTrue(events.contains { $0["key"] as? Int == 113 && $0["down"] as? Int == 1 })
        XCTAssertTrue(events.contains { $0["key"] as? Int == 97 && $0["down"] as? Int == 0 })
        try attach(events, name: "Received native Mac keyboard")
        try reset()
        input.scroll(byDeltaX: 0, deltaY: -20)
        events = try received { $0.contains { ($0["mask"] as? Int ?? 0) & 0x78 != 0 } }
        XCTAssertTrue(events.contains { ($0["mask"] as? Int ?? 0) & 0x78 != 0 })
        try attach(events, name: "Received native Mac scroll")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Controlled Mac input canvas"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        // macOS 27 grouped Forms expose the field caption as a separate static
        // text element rather than the editable field's accessibility label.
        let host = app.sheets.textFields.element(boundBy: 0)
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        let connect = app.buttons[chinese ? "连接" : "Connect"]
        XCTAssertFalse(connect.isEnabled)
        host.click()
        host.typeText("127.0.0.1")
        XCTAssertTrue(connect.isEnabled)
        let port = app.sheets.textFields.element(boundBy: 1)
        XCTAssertTrue(port.exists)
        port.click()
        port.typeKey("a", modifierFlags: .command)
        port.typeText("70000")
        XCTAssertFalse(connect.isEnabled, "An out-of-range port must disable connection")
        port.typeKey("a", modifierFlags: .command)
        port.typeText("5900")
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
