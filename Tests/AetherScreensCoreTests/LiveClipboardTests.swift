import XCTest
@testable import AetherScreensCore

/// Opt-in acceptance against a real Mac. Uses SSH only for clipboard inspection;
/// clipboard delivery under test travels through the normal RFB connection.
final class LiveClipboardTests: XCTestCase {
    func testRealMacBidirectionalUnicodeClipboard() throws { try verifyClipboard(unicode: true) }
    func testRealMacBidirectionalLegacyClipboard() throws { try verifyClipboard(unicode: false) }

    private func verifyClipboard(unicode: Bool) throws {
        let env = ProcessInfo.processInfo.environment
        let usesVNC = env["AETHERSCREENS_LIVE_AUTH"] == "vnc"
        let account = usesVNC ? nil : env["AETHERSCREENS_LIVE_USERNAME"]
        // Explicitly reuse only this same target's saved VNC credential when
        // its password has also been verified for Mac-account authentication.
        let credentialUsesVNC = usesVNC || env["AETHERSCREENS_LIVE_CREDENTIAL_AUTH"] == "vnc"
        guard env["AETHERSCREENS_QA_CLIPBOARD"] == "1",
              let host = env["AETHERSCREENS_LIVE_HOST"],
              usesVNC || account != nil,
              let sshAccount = env["AETHERSCREENS_QA_SSH_USER"],
              !host.hasPrefix("-"), !sshAccount.hasPrefix("-") else {
            throw XCTSkip("Requires explicit real-Mac clipboard QA opt-in and account")
        }
        let devices = UserDefaults(suiteName: "com.aethernative.aetherscreens")?
            .data(forKey: DeviceStore.storageKey)
            .flatMap { try? JSONDecoder().decode([RemoteDevice].self, from: $0) } ?? []
        func matches(_ device: RemoteDevice) -> Bool {
            device.host == host && (credentialUsesVNC ? device.authMethod == .vncPassword : device.username == account)
        }
        let saved = DeviceStore.shared.devices.first(where: matches) ?? devices.first(where: matches)
        guard let password = env["AETHERSCREENS_LIVE_PASSWORD"] ?? saved
            .flatMap({ DeviceStore.shared.getPassword(for: $0) }), !password.isEmpty else {
            throw XCTSkip("Requires supplied credentials or a matching saved Keychain account")
        }
        let client = RFBClient(host: host, password: password, username: account)
        defer { client.disconnect() }
        let frame = expectation(description: "Real desktop received")
        frame.assertForOverFulfill = false
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 30)
        guard client.state == .connected else { XCTFail("Real Mac connection must succeed"); return }
        let token = UUID().uuidString
        let suffix = unicode ? "中文" : "ASCII"
        let fromMac = "AetherScreens-\(token)-Mac \(suffix)\nsecond line"
        let toMac = "AetherScreens-\(token)-client \(suffix)\nsecond line"
        func literal(_ value: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), as: UTF8.self)
        }
        let received = expectation(description: "Mac clipboard reaches RFB client")
        received.assertForOverFulfill = false
        client.onClipboardReceived = { text in
            if text == fromMac { received.fulfill() }
        }
        // Preserve every original pasteboard item's representations in remote RAM.
        // Never print original content. Restore only while QA still owns the board.
        let source = """
        import AppKit
        import Foundation
        let board = NSPasteboard.general
        let original = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        }
        let sent = \(try literal(fromMac))
        let expected = \(try literal(toMac))
        func canonical(_ value: String) -> String {
            value.replacingOccurrences(of: "\\r\\n", with: "\\n").replacingOccurrences(of: "\\r", with: "\\n")
        }
        board.clearContents()
        board.setString(sent, forType: .string)
        let deadline = Date().addingTimeInterval(45)
        var matched = false
        while Date() < deadline {
            if let current = board.string(forType: .string), canonical(current) == canonical(expected) { matched = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if let current = board.string(forType: .string), canonical(current) == canonical(sent) || canonical(current) == canonical(expected) {
            board.clearContents()
            let items = original.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
            print("RESTORED")
        } else { print("CHANGED_BY_OTHER_WRITER") }
        print(matched ? "MATCH" : "NO_MATCH")
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", sshAccount + "@" + host, "/usr/bin/swift -"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(source.utf8))
        try input.fileHandleForWriting.close()
        let inspected = expectation(description: "Remote clipboard inspection completes")
        let observation = ClipboardQAOutput()
        DispatchQueue.global().async {
            observation.store(output.fileHandleForReading.readDataToEndOfFile())
            inspected.fulfill()
        }
        defer { if process.isRunning { process.terminate() } }
        wait(for: [received], timeout: 30)
        XCTAssertEqual(client.state, .connected, "Clipboard test must retain its real server connection")
        XCTAssertTrue(client.sendCutText(toMac), "Clipboard must be accepted by the negotiated transport")
        wait(for: [inspected], timeout: 35)
        let result = observation.text
        XCTAssertTrue(result.split(separator: "\n").contains("MATCH"), "Client clipboard must reach the actual Mac pasteboard")
        let markers = result.split(separator: "\n").filter {
            ["RESTORED", "CHANGED_BY_OTHER_WRITER", "MATCH", "NO_MATCH"].contains(String($0))
        }.joined(separator: ", ")
        print("Clipboard QA outcome: " + markers)
        XCTAssertTrue(result.contains("RESTORED"), "Original clipboard restore outcome: " + markers)
    }
}

private final class ClipboardQAOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func store(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
