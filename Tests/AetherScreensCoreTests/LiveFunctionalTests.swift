import XCTest

@testable import AetherScreensCore

final class LiveFunctionalTests: XCTestCase {
    func testLivePointerDeliveryToControlledFixture() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_LIVE_HOST"], let password = env["AETHERSCREENS_LIVE_PASSWORD"],
              let x = env["AETHERSCREENS_QA_CLICK_X"].flatMap(UInt16.init),
              let y = env["AETHERSCREENS_QA_CLICK_Y"].flatMap(UInt16.init) else {
            throw XCTSkip("Requires explicit live credentials and controlled fixture coordinates")
        }
        let frame = expectation(description: "Real frame received")
        frame.assertForOverFulfill = false
        let account = try XCTUnwrap(env["AETHERSCREENS_QA_SSH_USER"], "Specify the fixture SSH account")
        let client = RFBClient(host: host, password: password, username: env["AETHERSCREENS_LIVE_USERNAME"])
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
        let delivered = expectation(description: "Allow remote fixture to record input")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { delivered.fulfill() }
        wait(for: [delivered], timeout: 3)
        let after = try fixtureEvents(host: host, account: account)
        XCTAssertGreaterThan(after.filter { $0["type"] as? String == "click" }.count,
                             before.filter { $0["type"] as? String == "click" }.count,
                             "The controlled remote page must observe the actual click")
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
            let key = env["AETHERSCREENS_QA_UNICODE_STYLE"] == "x11" ? 0x01000000 | scalar.value : scalar.value
            client.sendKeyEvent(down: true, keySym: key)
            client.sendKeyEvent(down: false, keySym: key)
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
            client.sendCutText(testText)
            let clipboardReady = expectation(description: "Remote clipboard set")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { clipboardReady.fulfill() }
            wait(for: [clipboardReady], timeout: 2)
            client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
            client.sendKeyEvent(down: true, keySym: UInt32(118))
            client.sendKeyEvent(down: false, keySym: UInt32(118))
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
            let pasted = expectation(description: "Remote paste received")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pasted.fulfill() }
            wait(for: [pasted], timeout: 2)
            let events = try fixtureEvents(host: host, account: account)
            let paste = events.last { $0["type"] as? String == "paste" }
            XCTAssertEqual((paste?["data"] as? [String: Any])?["value"] as? String, testText)
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

    private func fixtureEvents(host: String, account: String) throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "\(account)@\(host)",
                             "curl -m 5 -fsS http://127.0.0.1:8766/events"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LiveFixture", code: Int(process.terminationStatus))
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
}
