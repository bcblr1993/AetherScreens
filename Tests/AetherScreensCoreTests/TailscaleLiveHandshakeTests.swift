import XCTest
import Network
import Security
@testable import AetherScreensCore

/// Talks to a real Mac with Screen Sharing on. Skipped unless a host is given, e.g.
/// `AETHERSCREENS_LIVE_HOST=100.x.y.z swift test --filter TailscaleLiveHandshakeTests`
final class TailscaleLiveHandshakeTests: XCTestCase {

    var targetHost = ""
    var targetPort: UInt16 = 5900

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_LIVE_HOST"], !host.isEmpty else {
            throw XCTSkip("Set AETHERSCREENS_LIVE_HOST to run live Screen Sharing tests")
        }
        targetHost = host
        if let port = env["AETHERSCREENS_LIVE_PORT"].flatMap(UInt16.init) {
            targetPort = port
        }
    }

    func testLiveTailscaleHandshakeIfReachable() throws {
        let expectation = XCTestExpectation(description: "RFB handshake with \(targetHost)")

        let nwHost = NWEndpoint.Host(targetHost)
        let nwPort = NWEndpoint.Port(rawValue: targetPort)!
        let params = NWParameters.tcp
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        let queue = DispatchQueue(label: "com.aethernative.aetherscreens.livetest")

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // 1. Receive 12-byte Server Version (e.g. "RFB 003.889\n")
                conn.receive(minimumIncompleteLength: 12, maximumLength: 12) { content, _, _, error in
                    guard let content = content, error == nil else {
                        XCTFail("Failed to receive RFB version: \(String(describing: error))")
                        expectation.fulfill()
                        return
                    }

                    guard let (major, minor) = RFBDecoder.parseVersion(content) else {
                        XCTFail("Could not parse RFB version: \(content)")
                        expectation.fulfill()
                        return
                    }

                    XCTAssertEqual(major, 3, "Major version should be 3")
                    XCTAssertTrue(minor >= 8, "Minor version should be at least 8 (got \(minor))")

                    // 2. Client replies with RFB 003.008\n
                    let clientVer = Data(RFBConstants.protocolVersion38.utf8)
                    conn.send(content: clientVer, completion: .contentProcessed({ sendErr in
                        guard sendErr == nil else {
                            XCTFail("Failed to send version reply")
                            expectation.fulfill()
                            return
                        }

                        // 3. Receive security types count
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { countData, _, _, _ in
                            guard let countData = countData, !countData.isEmpty else {
                                XCTFail("Failed to receive security types count")
                                expectation.fulfill()
                                return
                            }

                            let count = Int(countData[0])
                            XCTAssertGreaterThan(count, 0, "Server must offer at least 1 security type")

                            // 4. Receive security types array
                            conn.receive(minimumIncompleteLength: count, maximumLength: count) { typesData, _, _, _ in
                                guard let typesData = typesData else {
                                    XCTFail("Failed to receive security types data")
                                    expectation.fulfill()
                                    return
                                }

                                let types = typesData.map { RFBConstants.SecurityType(rawValue: $0) }
                                XCTAssertTrue(types.contains(.vncAuth), "Server should support VNC Auth (2)")

                                // 5. Select VNC Auth (2)
                                conn.send(content: Data([RFBConstants.SecurityType.vncAuth.rawValue]), completion: .contentProcessed({ _ in
                                    // 6. Receive 16-byte random challenge
                                    conn.receive(minimumIncompleteLength: 16, maximumLength: 16) { challengeData, _, _, _ in
                                        guard let challenge = challengeData else {
                                            XCTFail("Failed to receive 16-byte auth challenge")
                                            expectation.fulfill()
                                            return
                                        }

                                        XCTAssertEqual(challenge.count, 16, "VNC Auth challenge must be exactly 16 bytes")

                                        // Test Challenge Encryption with dummy password
                                        let encrypted = VNCAuthCrypto.encryptChallenge(challenge, password: "test_password")
                                        XCTAssertEqual(encrypted.count, 16, "Encrypted challenge response must be 16 bytes")

                                        conn.cancel()
                                        expectation.fulfill()
                                    }
                                }))
                            }
                        }
                    }))
                }

            case .failed(let err):
                // Explicitly requested live acceptance must fail when the host is unreachable.
                XCTFail("Live Screen Sharing host is unreachable: \(err)")
                expectation.fulfill()

            default:
                break
            }
        }

        conn.start(queue: queue)
        wait(for: [expectation], timeout: 5.0)
    }

    func testLiveTailscaleFullSessionWithSavedPassword() throws {
        let env = ProcessInfo.processInfo.environment
        let savedDevice = env["AETHERSCREENS_QA_USE_SAVED_CREDENTIALS"] == "1" ? UserDefaults(suiteName: "com.aethernative.aetherscreens")?
            .data(forKey: DeviceStore.storageKey)
            .flatMap { try? JSONDecoder().decode([RemoteDevice].self, from: $0) }?
            .first { $0.host == targetHost && $0.port == targetPort } : nil

        let configuredPassword = env["AETHERSCREENS_LIVE_PASSWORD"]
        let savedPassword = configuredPassword == nil ? savedDevice.flatMap(noninteractiveSavedPassword) : nil
        guard let pwd = configuredPassword ?? savedPassword, !pwd.isEmpty else {
            throw XCTSkip("Provide a test password or an existing credential readable without a Keychain prompt")
        }
        let username = env["AETHERSCREENS_LIVE_USERNAME"] ??
            (configuredPassword == nil && savedDevice?.authMethod == .macAccount ? savedDevice?.username : nil)

        let frameExpectation = expectation(description: "Receive at least 1 screen frame from remote Mac")
        frameExpectation.assertForOverFulfill = false

        let client = RFBClient(host: targetHost, port: targetPort, password: pwd,
                               username: username, automaticClipboard: false)
        client.setInputEnabled(false)
        defer { client.disconnect() }
        client.onFrameUpdated = {
            frameExpectation.fulfill()
        }

        client.connect()
        wait(for: [frameExpectation], timeout: 60.0)
        let stableSession = expectation(description: "Live connection remains active for 60 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            XCTAssertEqual(client.state, .connected)
            XCTAssertGreaterThan(client.framebuffer.width, 0)
            XCTAssertGreaterThan(client.framebuffer.height, 0)
            stableSession.fulfill()
        }
        wait(for: [stableSession], timeout: 65)
        let unexpectedFailure = expectation(description: "Intentional disconnect must not fail")
        unexpectedFailure.isInverted = true
        client.onStateChanged = { state in
            if case .failed = state { unexpectedFailure.fulfill() }
        }
        client.disconnect()
        wait(for: [unexpectedFailure], timeout: 1)
        XCTAssertEqual(client.state, .disconnected)
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
}
