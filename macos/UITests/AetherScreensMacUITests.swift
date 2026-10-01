import XCTest

/// Runs against a separately identified QA app in the macOS VM.
@MainActor
final class AetherScreensMacUITests: XCTestCase {
    func testEnglishQuickConnectValidation() throws { try checkQuickConnect(language: "en") }
    func testChineseQuickConnectValidation() throws { try checkQuickConnect(language: "zh-Hans") }

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
        let host = app.textFields[chinese ? "IP 地址 / 主机名（如 100.80.1.25）" : "Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        let connect = app.buttons[chinese ? "连接" : "Connect"]
        XCTAssertFalse(connect.isEnabled)
        host.click()
        host.typeText("127.0.0.1")
        XCTAssertTrue(connect.isEnabled)
        let port = app.textFields[chinese ? "端口" : "Port"]
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
