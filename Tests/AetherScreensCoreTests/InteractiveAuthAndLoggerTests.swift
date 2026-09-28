import XCTest
import Network
@testable import AetherScreensCore

final class InteractiveAuthAndLoggerTests: XCTestCase {

    var listener: NWListener?
    let authTestPort: UInt16 = 5989
    let queue = DispatchQueue(label: "com.aethernative.aetherscreens.authtest")

    override func tearDown() {
        listener?.cancel()
        listener = nil
        super.tearDown()
    }

    func testAppLoggerRecordingAndExport() {
        let logger = AppLogger.shared
        logger.clear()

        logger.info("Testing info logging", category: "Test")
        logger.warning("Testing warning logging", category: "Test")
        logger.error("Testing error logging", category: "Test")

        XCTAssertEqual(logger.entries.count, 3)
        XCTAssertEqual(logger.entries[0].level, .info)
        XCTAssertEqual(logger.entries[1].level, .warning)
        XCTAssertEqual(logger.entries[2].level, .error)

        let exported = logger.exportLogs()
        XCTAssertTrue(exported.contains("Testing info logging"))
        XCTAssertTrue(exported.contains("Testing warning logging"))
        XCTAssertTrue(exported.contains("Testing error logging"))
        XCTAssertTrue(exported.contains("[Test]"))

        logger.clear()
        XCTAssertEqual(logger.entries.count, 0)
    }

    func testDeviceStorePasswordManagement() {
        let suiteName = "test.aetherscreens.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = KeychainStore(serviceName: "test.aetherscreens.credentials.\(UUID().uuidString)",
                                     legacyServiceName: nil)
        let store = DeviceStore(userDefaults: defaults, keychain: keychain)
        let testDev = RemoteDevice(
            name: "Test Auth Mac",
            host: "100.99.99.99",
            port: 5900,
            deviceType: .mac,
            authMethod: .vncPassword
        )

        // Clear any old credentials
        store.clearPassword(for: testDev)
        XCTAssertFalse(store.hasPassword(for: testDev))

        // Update password
        store.updatePassword("secret123", for: testDev)
        XCTAssertTrue(store.hasPassword(for: testDev))
        XCTAssertEqual(store.getPassword(for: testDev), "secret123")

        // Clear password
        store.clearPassword(for: testDev)
        XCTAssertFalse(store.hasPassword(for: testDev))
    }

    func testInteractiveVNCPasswordPromptWorkflow() throws {
        let promptInvoked = expectation(description: "onRequestPassword prompt callback triggered")
        let authCompleted = expectation(description: "VNC Auth completed successfully with entered password")

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: authTestPort)!)

        let dummyChallenge = Data(repeating: 0x42, count: 16)
        let testPassword = "MyVncPassword"

        listener?.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            newConn.start(queue: self.queue)

            // 1. Send RFB 003.008\n
            newConn.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed({ _ in
                // Receive client version reply
                newConn.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    // 2. Offer security type: vncAuth (2)
                    newConn.send(content: Data([1, RFBConstants.SecurityType.vncAuth.rawValue]), completion: .contentProcessed({ _ in
                        // Receive security selection (1 byte)
                        newConn.receive(minimumIncompleteLength: 1, maximumLength: 1) { selectData, _, _, _ in
                            guard let selectData = selectData, selectData[0] == RFBConstants.SecurityType.vncAuth.rawValue else {
                                XCTFail("Client did not select vncAuth")
                                return
                            }

                            // 3. Send 16-byte random challenge
                            newConn.send(content: dummyChallenge, completion: .contentProcessed({ _ in
                                // Receive 16-byte encrypted response from client
                                newConn.receive(minimumIncompleteLength: 16, maximumLength: 16) { respData, _, _, _ in
                                    guard let respData = respData else {
                                        XCTFail("No encrypted challenge response received")
                                        return
                                    }

                                    // Verify that client encrypted the challenge with the entered password
                                    let expectedResponse = VNCAuthCrypto.encryptChallenge(dummyChallenge, password: testPassword)
                                    XCTAssertEqual(respData, expectedResponse, "Client encrypted response should match expected DES cipher")

                                    // 4. Send SecurityResult OK (0)
                                    let okCode: UInt32 = 0
                                    let okData = withUnsafeBytes(of: okCode.bigEndian) { Data($0) }
                                    newConn.send(content: okData, completion: .contentProcessed({ _ in
                                        // 5. Receive ClientInit (1 byte)
                                        newConn.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                                            authCompleted.fulfill()
                                        }
                                    }))
                                }
                            }))
                        }
                    }))
                }
            }))
        }

        listener?.start(queue: queue)

        // Initialize RFBClient without password
        let client = RFBClient(
            host: "127.0.0.1",
            port: authTestPort,
            password: nil
        )

        client.onRequestPassword = { continuation in
            promptInvoked.fulfill()
            // Provide password dynamically as user would via UI modal
            continuation(testPassword)
        }

        client.connect()

        wait(for: [promptInvoked, authCompleted], timeout: 5.0)
        client.disconnect()
    }
}
