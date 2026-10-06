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

    func testMacOnlyServerRequestsAccountInsteadOfFailingAsUnsupported() throws {
        let ready = expectation(description: "Listener ready")
        let requested = expectation(description: "Mac account requested")
        let selected = expectation(description: "ARD type selected after entering account")
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    connection.send(content: Data([1, 30]), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, _ in
                            XCTAssertEqual(data, Data([30]))
                            selected.fulfill()
                            connection.cancel()
                        }
                    })
                }
            })
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener?.port)
        let client = RFBClient(host: "127.0.0.1", port: port.rawValue)
        defer { client.disconnect() }
        client.onRequestMacAccount = { continuation in
            requested.fulfill()
            continuation("qa-account", "dummy-password")
        }
        client.connect()
        wait(for: [requested, selected], timeout: 5)
        XCTAssertEqual(client.username, "qa-account")
    }

    func testCancelledOldPasswordPromptCannotFailAReconnectedClient() throws {
        try verifyCancelledOldPasswordPrompt(firstMacAccount: false)
    }

    func testWaitingForMacAccountInputDoesNotExpireConnectionDeadline() throws {
        let ready = expectation(description: "Mac-only listener ready")
        let requested = expectation(description: "Waiting for account input")
        let userInputDelay = expectation(description: "User takes longer than the network deadline")
        let reply = CapturedMacAccountReply()
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    connection.send(content: Data([1, 30]), completion: .contentProcessed { _ in
                        // The user has not submitted credentials; hold the socket
                        // until the client explicitly cancels this test session.
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                            connection.cancel()
                        }
                    })
                }
            })
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener?.port)
        let client = RFBClient(host: "127.0.0.1", port: port.rawValue)
        defer { client.disconnect() }
        client.onRequestMacAccount = { continuation in
            reply.store(continuation)
            requested.fulfill()
        }
        client.connect()
        wait(for: [requested], timeout: 3)
        queue.asyncAfter(deadline: .now() + 21) { userInputDelay.fulfill() }
        wait(for: [userInputDelay], timeout: 24)
        XCTAssertNotNil(reply.load())
        XCTAssertEqual(client.state, .authenticating,
                       "Waiting for user input must not consume the network handshake deadline")
    }

    func testWaitingForVNCPasswordDoesNotExpireConnectionDeadline() throws {
        try verifyWaitingForPassword(ard: false)
    }

    func testWaitingForARDPasswordDoesNotExpireConnectionDeadline() throws {
        try verifyWaitingForPassword(ard: true)
    }

    private func verifyWaitingForPassword(ard: Bool) throws {
        let ready = expectation(description: "Password listener ready")
        let requested = expectation(description: "Password requested")
        let delay = expectation(description: "User still entering password")
        let reply = CapturedPasswordReply()
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    connection.send(content: Data([1, ard ? 30 : 2]), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                            connection.send(content: Data(repeating: 42, count: 16), completion: .contentProcessed { _ in
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
                            })
                        }
                    })
                }
            })
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener?.port)
        let client = RFBClient(host: "127.0.0.1", port: port.rawValue,
                               username: ard ? "qa-account" : nil, connectionTimeoutInterval: 0.5)
        defer { client.disconnect() }
        client.onRequestPassword = { continuation in reply.store(continuation); requested.fulfill() }
        client.connect()
        wait(for: [requested], timeout: 3)
        queue.asyncAfter(deadline: .now() + 1) { delay.fulfill() }
        wait(for: [delay], timeout: 3)
        XCTAssertNotNil(reply.load())
        XCTAssertEqual(client.state, .authenticating)
    }

    func testSubmittedPasswordGetsFreshDeadlineAndStalledServerStillTimesOut() throws {
        let ready = expectation(description: "VNC listener ready")
        let requested = expectation(description: "Password requested")
        let entered = expectation(description: "User finishes entering password")
        let response = expectation(description: "Server receives challenge response")
        let oldDeadline = expectation(description: "Original deadline has elapsed")
        let expired = expectation(description: "Resumed handshake times out")
        let reply = CapturedPasswordReply()
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    connection.send(content: Data([1, 2]), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                            connection.send(content: Data(repeating: 42, count: 16), completion: .contentProcessed { _ in
                                connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { data, _, _, _ in
                                    XCTAssertEqual(data?.count, 16)
                                    response.fulfill()
                                    // Deliberately withhold SecurityResult to exercise the resumed deadline.
                                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
                                }
                            })
                        }
                    })
                }
            })
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener?.port)
        let client = RFBClient(host: "127.0.0.1", port: port.rawValue, connectionTimeoutInterval: 3)
        defer { client.disconnect() }
        client.onRequestPassword = { continuation in reply.store(continuation); requested.fulfill() }
        client.onStateChanged = { state in
            if case .failed(let message) = state, message.contains("Connection timed out") { expired.fulfill() }
        }
        client.connect()
        wait(for: [requested], timeout: 3)
        queue.asyncAfter(deadline: .now() + 1) { entered.fulfill() }
        wait(for: [entered], timeout: 3)
        try XCTUnwrap(reply.load())("dummy-password")
        wait(for: [response], timeout: 2)
        queue.asyncAfter(deadline: .now() + 2.3) { oldDeadline.fulfill() }
        wait(for: [oldDeadline], timeout: 3)
        XCTAssertEqual(client.state, .authenticating, "The pre-prompt deadline must not expire the resumed handshake")
        wait(for: [expired], timeout: 2)
    }

    func testSilentServerStillUsesConnectionDeadline() throws {
        let ready = expectation(description: "Silent listener ready")
        let expired = expectation(description: "Silent peer times out")
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener?.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in connection.cancel() }
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener?.port)
        let client = RFBClient(host: "127.0.0.1", port: port.rawValue, connectionTimeoutInterval: 0.5)
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if case .failed(let message) = state, message.contains("Connection timed out") { expired.fulfill() }
        }
        client.connect()
        wait(for: [expired], timeout: 3)
    }

    func testCancelledOldARDPasswordPromptCannotFailAReconnectedClient() throws {
        try verifyCancelledOldPasswordPrompt(firstMacAccount: true)
    }

    private func verifyCancelledOldPasswordPrompt(firstMacAccount: Bool) throws {
        let ready = expectation(description: "Listener ready")
        let prompt = expectation(description: "First connection requests password")
        let connected = expectation(description: "Second connection completes handshake")
        var connections: [NWConnection] = []
        var number = 0
        let oldReply = CapturedPasswordReply()
        listener = try NWListener(using: .tcp, on: .any)
        listener?.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener?.newConnectionHandler = { connection in
            number += 1
            let first = number == 1
            connections.append(connection)
            connection.start(queue: self.queue)
            connection.send(content: Data("RFB 003.008\n".utf8), completion: .contentProcessed { _ in
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    connection.send(content: Data([1, first ? (firstMacAccount ? 30 : 2) : 1]), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                            if first {
                                connection.send(content: Data(repeating: 42, count: 16), completion: .contentProcessed { _ in })
                            } else {
                                connection.send(content: Data([0, 0, 0, 0]), completion: .contentProcessed { _ in
                                    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                                        var initial = Data([0, 16, 0, 16])
                                        initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                                        initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                                        connection.send(content: initial, completion: .contentProcessed { _ in })
                                    }
                                })
                            }
                        }
                    })
                }
            })
        }
        listener?.start(queue: queue)
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(listener?.port).rawValue, username: firstMacAccount ? "qa-account" : nil)
        defer { client.disconnect(); connections.forEach { $0.cancel() } }
        client.onRequestPassword = { reply in oldReply.store(reply); prompt.fulfill() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [prompt], timeout: 3)
        client.disconnect()
        client.username = nil
        client.connect()
        wait(for: [connected], timeout: 3)
        try XCTUnwrap(oldReply.load())(nil)
        let drained = expectation(description: "Old password continuation drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(client.state, .connected)
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
                                     legacyServiceName: nil, backend: TestKeychainBackend())
        let store = TestStorage.make(userDefaults: defaults, keychain: keychain)
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

        // An unsaved/removed target cannot create an orphan Keychain entry.
        store.updatePassword("synthetic-unsaved-password", for: testDev)
        XCTAssertFalse(store.hasPassword(for: testDev))
        XCTAssertNil(keychain.loadPassword(forKey: testDev.id.uuidString))
        store.addDevice(testDev)

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

private final class CapturedPasswordReply: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (@Sendable (String?) -> Void)?
    func store(_ reply: @escaping @Sendable (String?) -> Void) { lock.lock(); value = reply; lock.unlock() }
    func load() -> (@Sendable (String?) -> Void)? { lock.lock(); defer { lock.unlock() }; return value }
}

private final class CapturedMacAccountReply: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (@Sendable (String?, String?) -> Void)?
    func store(_ reply: @escaping @Sendable (String?, String?) -> Void) { lock.lock(); value = reply; lock.unlock() }
    func load() -> (@Sendable (String?, String?) -> Void)? { lock.lock(); defer { lock.unlock() }; return value }
}
