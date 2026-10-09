import XCTest
import Network
import zlib
@testable import AetherScreensCore

final class PointerTransportTests: XCTestCase {
    func testReceiveTimeoutLatePacketKeepsDesktopPointerTransportAlive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-idle-tcp-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = expectation(description: "Idle file listener")
        let connected = expectation(description: "Idle file connected")
        let expired = expectation(description: "Receive deadline expired")
        let late = expectation(description: "Late file frame consumed")
        let pointer = expectation(description: "Pointer still reaches peer")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        let queue = DispatchQueue(label: "file-idle-tcp-qa")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, inactivityTimeout: 0.05, queue: queue,
            onEvent: { _ in XCTFail("Expired receiver cannot process") },
            onFailure: { expired.fulfill() },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("No completed transfer") })
        XCTAssertTrue(client.installAppleFileCopyReceiver(worker))
        wait(for: [expired], timeout: 3)
        client.onAppleFileCopyReceived = { if $0.sessionID == 7 { late.fulfill() } }
        server.sendFileCopyFixture(try AppleFileCopyMessage(version: 1, command: 104,
            sessionID: 7, body: Data(repeating: 0, count: 4)).encode())
        wait(for: [late], timeout: 3)
        server.onPointer = { if $0.x == 10 && $0.y == 20 { pointer.fulfill() } }
        client.sendPointerEvent(buttonMask: [], x: 10, y: 20)
        wait(for: [pointer], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testInstalledUploadReceivesServerResultAndDisconnectCancelsReplacement() throws {
        let ready = expectation(description: "Upload listener")
        let connected = expectation(description: "Upload connected")
        let completed = expectation(description: "Upload server result dispatched")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect(); wait(for: [connected], timeout: 3)
        let oldGeneration = try XCTUnwrap(client.fileCopyTransportGeneration)
        client.setInputEnabled(false)
        XCTAssertNil(client.fileCopyTransportGeneration)
        client.setInputEnabled(true)
        let generation = try XCTUnwrap(client.fileCopyTransportGeneration)
        XCTAssertNotEqual(generation, oldGeneration)
        XCTAssertFalse(client.sendAppleFileCopy(AppleFileCopyControl.stop.message(sessionID: 7),
            expectedGeneration: oldGeneration, processed: { _ in XCTFail("Rejected write callback fired") }))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("upload-tcp-\(UUID())")
        try Data([0, 255]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var header = Data(repeating: 0, count: 104)
        header[0] = 1; header[49] = 2
        let source = AppleFileCopySendSession.Source(item: .init(catalogHeader: header,
            level: 0, wireName: "QA", symbolicLinkTarget: nil, extensions: Data()),
            dataURL: url, resourceURL: nil)
        server.onFileCopyWire = { wire in
            do {
                let message = try XCTUnwrap(AppleFileCopyMessage.decode(wire)?.message)
                if message.command == 104 {
                    server.sendFileCopyFixture(try AppleFileCopyMessage(version: 1, command: 200,
                        sessionID: message.sessionID, body: Data([0, 0, 0, 0, 0])).encode())
                }
            } catch { XCTFail("Invalid uploaded frame") }
        }
        let sender = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 2,
            blockSize: 1, transport: { [weak client] message, done in
                client?.sendAppleFileCopy(message, expectedGeneration: generation, processed: done) ?? false
            }, onCompleted: { _ in completed.fulfill() }, onFailure: { XCTFail("Upload failed") })
        XCTAssertTrue(client.installAppleFileCopySender(sender))
        XCTAssertFalse(client.installAppleFileCopySender(sender))
        XCTAssertTrue(sender.start())
        wait(for: [completed], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        client.removeAppleFileCopySender(sender)
        let replacement = try AppleFileCopySendWorker(sessionID: 8, sources: [source], maximumBytes: 2,
            transport: { [weak client] message, done in
                client?.sendAppleFileCopy(message, processed: done) ?? false
            }, onCompleted: { _ in XCTFail("Unstarted replacement completed") },
            onFailure: { XCTFail("Disconnect should cancel quietly") })
        XCTAssertTrue(client.installAppleFileCopySender(replacement))
        client.removeAppleFileCopySender(sender) // obsolete owner cannot cancel replacement
        XCTAssertFalse(client.installAppleFileCopySender(sender))
        client.disconnect()
        XCTAssertFalse(replacement.start())
        XCTAssertFalse(replacement.enqueue(.init(version: 1, command: 200, sessionID: 8,
            body: Data([0, 0, 0, 0, 0]))))
        XCTAssertEqual(try Data(contentsOf: url), Data([0, 255]))
    }

    func testOutgoingItemAndBinaryAttributeReachTCPWireUnchanged() throws {
        let ready = expectation(description: "Outgoing item listener")
        let connected = expectation(description: "Outgoing item connection")
        let sent = expectation(description: "Outgoing item bytes")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        var expectedCatalog = Data(repeating: 0, count: 104)
        expectedCatalog[93] = 2; expectedCatalog[101] = 1
        // ext1 envelope length 30, table length 20, one key and binary value.
        let expectedAttribute = Data([0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1, 0, 30,
            0, 0, 0, 20, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 2, 65, 0, 0, 0xff])
        let expected = Data([0x22, 0, 0, 0, 0, 144, 0, 1, 0, 101, 0, 0, 0, 42])
            + expectedCatalog + Data([65, 0]) + expectedAttribute
        server.onFileCopyWire = { wire in
            XCTAssertEqual(wire, expected)
            sent.fulfill()
        }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        let attribute = try AppleFileCopyAttributeBlock.encode(entries: [
            .init(name: Data([65]), value: Data([0, 0xff]))])
        let item = AppleFileCopyItem(catalogHeader: Data(repeating: 0, count: 104),
            level: 2, wireName: "A", symbolicLinkTarget: nil, extensions: attribute)
        XCTAssertTrue(client.sendAppleFileCopy(try item.message(sessionID: 42)))
        wait(for: [sent], timeout: 3)
    }

    func testNativeFileCopyDispatchKeepsFollowingClipboardFrameAligned() throws {
        let ready = expectation(description: "File copy listener")
        let connected = expectation(description: "File copy connected")
        let received = expectation(description: "File copy message")
        let following = expectation(description: "Following framed message")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onAppleFileCopyReceived = { message in
            XCTAssertEqual(message.command, 104)
            XCTAssertEqual(message.sessionID, 7)
            XCTAssertEqual(message.body, Data([0, 0, 0, 0]))
            received.fulfill()
        }
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "QA")
            following.fulfill()
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        // One TCP write contains both frames. No system clipboard is accessed.
        server.sendFileCopyFixture(Data([0x22, 0, 0, 0, 0, 12, 0, 1, 0, 104,
                                        0, 0, 0, 7, 0, 0, 0, 0,
                                        3, 0, 0, 0, 0, 0, 0, 2, 81, 65]))
        wait(for: [received, following], timeout: 3)
    }

    func testNativeFileCopyStartEncodingReachesWireUnchanged() throws {
        let ready = expectation(description: "Start listener ready")
        let connected = expectation(description: "Start fixture connected")
        let sent = expectation(description: "Literal start packet received")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        server.onFileCopyWire = { wire in
            XCTAssertEqual(wire, Data([0x22, 0, 0, 0, 0, 22, 0, 1, 0, 2, 0, 0, 0, 42,
                                      0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 47, 81, 65, 0]))
            sent.fulfill()
        }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        let start = AppleFileCopyStart(direction: .serverReceives, flags: 0,
            reserved: Data(repeating: 0, count: 4), path: Data("/QA".utf8), trailingBytes: Data())
        XCTAssertTrue(client.sendAppleFileCopy(try start.message(sessionID: 42)))
        wait(for: [sent], timeout: 3)
    }

    func testNativeFileCopySendUsesBoundedWireAndObserveModeRejectsIt() throws {
        let ready = expectation(description: "File copy send listener")
        let connected = expectation(description: "File copy send connected")
        let sent = expectation(description: "File copy literal wire")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        server.onFileCopyWire = { wire in
            XCTAssertEqual(wire, Data([0x22, 0, 0, 0, 0, 12, 0, 1, 0, 104, 0, 0, 0, 7, 0, 0, 0, 0]))
            sent.fulfill()
        }
        let message = AppleFileCopyMessage(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))
        XCTAssertFalse(client.sendAppleFileCopy(message))
        client.connect()
        wait(for: [connected], timeout: 3)
        client.setInputEnabled(false)
        XCTAssertFalse(client.sendAppleFileCopy(message))
        client.setInputEnabled(true)
        XCTAssertFalse(client.sendAppleFileCopy(AppleFileCopyMessage(version: 1, command: 102, sessionID: 7,
                                                                    body: Data(repeating: 0, count: 1_048_576))))
        XCTAssertTrue(client.sendAppleFileCopy(message))
        wait(for: [sent], timeout: 3)
        client.disconnect()
        XCTAssertFalse(client.sendAppleFileCopy(message))
    }

    func testNativeFileCopyQueuedSendIsInvalidatedAcrossObserveModeChange() throws {
        let invalidated = expectation(description: "Stale packet reports rejection")
        let processed = expectation(description: "Fresh packet reports local write completion")
        let ready = expectation(description: "Queued file copy listener")
        let connected = expectation(description: "Queued file copy connected")
        let queueHeld = expectation(description: "Connection queue held")
        let sent = expectation(description: "Only fresh file copy sent")
        sent.assertForOverFulfill = true
        let release = DispatchSemaphore(value: 0)
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { release.signal(); server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onAppleFileCopyReceived = { _ in
            queueHeld.fulfill()
            XCTAssertEqual(release.wait(timeout: .now() + 3), .success)
        }
        server.onFileCopyWire = { wire in
            XCTAssertEqual(wire, Data([0x22, 0, 0, 0, 0, 8, 0, 1, 0, 104, 0, 0, 0, 9]))
            sent.fulfill()
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        server.sendFileCopyFixture(Data([0x22, 0, 0, 0, 0, 8, 0, 1, 0, 104, 0, 0, 0, 1]))
        wait(for: [queueHeld], timeout: 3)
        XCTAssertTrue(client.sendAppleFileCopy(AppleFileCopyMessage(version: 1, command: 104, sessionID: 8, body: Data())) { success in
            XCTAssertFalse(success)
            invalidated.fulfill()
        })
        client.setInputEnabled(false)
        client.setInputEnabled(true)
        XCTAssertTrue(client.sendAppleFileCopy(AppleFileCopyMessage(version: 1, command: 104, sessionID: 9, body: Data())) { success in
            XCTAssertTrue(success)
            processed.fulfill()
        })
        release.signal()
        wait(for: [sent, invalidated, processed], timeout: 3)
    }

    func testNativeFileCopyReceiveWorkerDoesNotBlockFollowingControlMessage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-wire-worker-qa-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = expectation(description: "Wire worker listener")
        let connected = expectation(description: "Wire worker connected")
        let following = expectation(description: "Control message received while file worker is held")
        let prepared = expectation(description: "Wire bytes staged exactly")
        let finalStatus = expectation(description: "Final control result remains readable")
        let release = DispatchSemaphore(value: 0)
        let workerQueue = DispatchQueue(label: "file-wire-worker-qa")
        workerQueue.async { _ = release.wait(timeout: .now() + 3) }
        defer { release.signal() }
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 3, maximumItems: 1, queue: workerQueue,
            onEvent: { _ in }, onFailure: { XCTFail("Valid wire receive must not fail") },
            onPrepared: { files in
                XCTAssertEqual(files.count, 1)
                XCTAssertEqual(try? Data(contentsOf: files[0].dataForkURL), Data([11, 22]))
                XCTAssertEqual(try? Data(contentsOf: files[0].resourceForkURL), Data([33]))
                files.forEach { $0.cancel() }
                prepared.fulfill()
            })
        defer { worker.cancel() }
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onClipboardReceived = { text in XCTAssertEqual(text, "QA"); following.fulfill() }
        client.onAppleFileCopyReceived = { message in
            if message.command == 200 {
                XCTAssertEqual(try? AppleFileCopyServerStatus.decode(message, expectedSessionID: 7),
                               .finished(errorCode: 0, destinationName: Data([65])))
                finalStatus.fulfill()
            }
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        XCTAssertTrue(client.installAppleFileCopyReceiver(worker))
        XCTAssertFalse(client.installAppleFileCopyReceiver(worker))
        var catalog = Data(repeating: 0, count: 104)
        catalog[0] = 1
        catalog[41] = 1; catalog[49] = 2; catalog[101] = 1
        catalog.append(contentsOf: [65, 0])
        var packet = Data([0x22, 0, 0, 0, 0, 114, 0, 1, 0, 101, 0, 0, 0, 7]) + catalog
        packet.append(contentsOf: [0x22, 0, 0, 0, 0, 14, 0, 1, 0, 102, 0, 0, 0, 7, 0, 0, 0, 2, 11, 22])
        packet.append(contentsOf: [0x22, 0, 0, 0, 0, 13, 0, 1, 0, 102, 0, 0, 0, 7, 0, 0, 0, 1, 33])
        packet.append(contentsOf: [0x22, 0, 0, 0, 0, 12, 0, 1, 0, 104, 0, 0, 0, 7, 0, 0, 0, 0])
        packet.append(contentsOf: [3, 0, 0, 0, 0, 0, 0, 2, 81, 65])
        server.sendFileCopyFixture(packet)
        wait(for: [following], timeout: 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
                      "The blocked file worker must not write on the connection queue")
        release.signal()
        wait(for: [prepared], timeout: 3)
        server.sendFileCopyFixture(Data([0x22, 0, 0, 0, 0, 14, 0, 1, 0, 200, 0, 0, 0, 7,
                                        0, 0, 0, 1, 65, 0]))
        wait(for: [finalStatus], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        workerQueue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testNativeFileCopyDisconnectCancelsInstalledStaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-disconnect-qa-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let ready = expectation(description: "File disconnect listener")
        let connected = expectation(description: "File disconnect connected")
        let staged = expectation(description: "File staged before disconnect")
        let queue = DispatchQueue(label: "file-disconnect-qa")
        let worker = try AppleFileCopyReceiveWorker(sessionID: 7, parentDirectory: root,
            maximumBytes: 0, maximumItems: 1, queue: queue,
            onEvent: { if $0 == .itemPrepared { staged.fulfill() } },
            onFailure: { XCTFail("No failed file frame") },
            onPrepared: { files in files.forEach { $0.cancel() }; XCTFail("No sender-end received") })
        defer { worker.cancel() }
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        XCTAssertFalse(client.installAppleFileCopyReceiver(worker))
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        XCTAssertTrue(client.installAppleFileCopyReceiver(worker))
        var body = Data(repeating: 0, count: 104)
        body[0] = 1
        body[101] = 1; body.append(contentsOf: [65, 0])
        server.sendFileCopyFixture(Data([0x22, 0, 0, 0, 0, 114, 0, 1, 0, 101, 0, 0, 0, 7]) + body)
        wait(for: [staged], timeout: 3)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        client.disconnect()
        queue.sync {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertFalse(worker.enqueue(.init(version: 1, command: 104, sessionID: 7, body: Data(repeating: 0, count: 4))))
    }

    func testNativeFileCopyFragmentedHeaderAndBodyAreReassembled() throws {
        let ready = expectation(description: "Fragmented file copy listener")
        let connected = expectation(description: "Fragmented file copy connected")
        let received = expectation(description: "Fragmented file copy reassembled")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.onAppleFileCopyReceived = { message in
            XCTAssertEqual(message, AppleFileCopyMessage(version: 1, command: 104, sessionID: 7,
                                                         body: Data([0x9c, 0xff, 0xff, 0xff])))
            received.fulfill()
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        server.sendFileCopyFragments([
            Data([0x22, 0, 0]), Data([0, 0, 12, 0]), Data([1, 0, 104, 0, 0, 0, 7, 0x9c]),
            Data([0xff, 0xff, 0xff])
        ])
        wait(for: [received], timeout: 3)
    }

    func testNativeFileCopyTruncatedBodyDoesNotDispatch() throws {
        let ready = expectation(description: "Truncated file copy listener")
        let connected = expectation(description: "Truncated file copy connected")
        let failed = expectation(description: "Truncated file copy failed")
        let unwanted = expectation(description: "Incomplete message must not dispatch")
        unwanted.isInverted = true
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed = state { failed.fulfill() }
        }
        client.onAppleFileCopyReceived = { _ in unwanted.fulfill() }
        client.connect()
        wait(for: [connected], timeout: 3)
        server.sendFileCopyFragments([Data([0x22, 0, 0, 0, 0, 12, 0, 1, 0, 104, 0, 0, 0, 7, 0])], closeAfter: true)
        wait(for: [failed], timeout: 3)
        wait(for: [unwanted], timeout: 0.1)
    }

    func testUnknownServerMessageFailsRatherThanDispatchingItsBody() throws {
        let ready = expectation(description: "Unknown message listener")
        let connected = expectation(description: "Unknown message connected")
        let failed = expectation(description: "Unknown message rejected")
        let unwanted = expectation(description: "Unknown body must not become clipboard")
        unwanted.isInverted = true
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed(let reason) = state {
                XCTAssertEqual(reason, "Unsupported server message type: 255")
                failed.fulfill()
            }
        }
        client.onClipboardReceived = { _ in unwanted.fulfill() }
        client.connect()
        wait(for: [connected], timeout: 3)
        // The unknown body's bytes deliberately resemble a valid text frame.
        server.sendFileCopyFixture(Data([255, 3, 0, 0, 0, 0, 0, 0, 2, 81, 65]))
        wait(for: [failed], timeout: 3)
        wait(for: [unwanted], timeout: 0.1)
    }

    func testNativeFileCopyInvalidLengthFailsWithoutWaitingForPayload() throws {
        let ready = expectation(description: "Invalid file copy listener")
        let connected = expectation(description: "Invalid file copy connected")
        let failed = expectation(description: "Invalid prefix rejected")
        let server = try PointerWireServer(nativeBanner: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed(let reason) = state {
                XCTAssertEqual(reason, "Invalid native file-copy message length")
                failed.fulfill()
            }
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        server.sendFileCopyFixture(Data([0x22, 0, 0xff, 0xff, 0xff, 0xff]))
        wait(for: [failed], timeout: 3)
    }


    @MainActor
    func testConfiguredDisconnectRunsOnlyForExplicitClose() throws {
        let ready = expectation(description: "Configured close listener")
        let connected = expectation(description: "Configured close connected")
        let delivered = expectation(description: "Configured lock release")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let device = RemoteDevice(name: "Disconnect QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        DisconnectActionStore.shared.save(.lockScreen, for: device.id)
        defer { DisconnectActionStore.shared.remove(for: device.id) }
        let session = SessionViewModel(device: device, password: nil)
        defer { session.client.disconnect() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.endSession()
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertEqual(session.client.state, .disconnected, "Lifecycle cleanup closes without remote actions")
        let reconnected = expectation(description: "Explicit close connection")
        session.client.onStateChanged = { if $0 == .connected { reconnected.fulfill() } }
        session.startSession()
        wait(for: [reconnected], timeout: 3)
        server.onKey = { if $0.key == MacKeyMap.controlLeft && !$0.down { delivered.fulfill() } }
        session.requestDisconnect()
        session.endSession() // SwiftUI disappearance must not cancel the final packet.
        session.requestDisconnect()
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(server.keys.count, 6)
        let closed = expectation(description: "Explicit close drained")
        if session.client.state == .disconnected { closed.fulfill() }
        else { session.client.onStateChanged = { if $0 == .disconnected { closed.fulfill() } } }
        wait(for: [closed], timeout: 3)
        let resumed = expectation(description: "Same session restarted")
        session.client.onStateChanged = { if $0 == .connected { resumed.fulfill() } }
        session.startSession()
        wait(for: [resumed], timeout: 3)
        let input = expectation(description: "Restarted session input restored")
        server.onKey = { if $0.key == MacKeyMap.escape && !$0.down { input.fulfill() } }
        session.client.sendKeyEvent(down: true, keySym: MacKeyMap.escape)
        session.client.sendKeyEvent(down: false, keySym: MacKeyMap.escape)
        wait(for: [input], timeout: 2)
    }
    func testObserveDisconnectDoesNotSendConfiguredFinalChord() throws {
        let ready = expectation(description: "Observe close listener")
        let connected = expectation(description: "Observe close connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        client.setInputEnabled(false)
        let unwanted = expectation(description: "Observe close must not lock")
        unwanted.isInverted = true
        server.onKey = { _ in unwanted.fulfill() }
        client.disconnect(afterSendingKeySequence: MacKeyMap.MacShortcut.lockScreen.keySequence)
        wait(for: [unwanted], timeout: 0.2)
        XCTAssertEqual(client.state, .disconnected)
        XCTAssertTrue(server.keys.isEmpty)
    }
    func testOldGracefulDisconnectTimeoutCannotCloseReplacementConnection() throws {
        let ready = expectation(description: "Replacement listener")
        let first = expectation(description: "First connection")
        let closed = expectation(description: "First gracefully closed")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = {
            if $0 == .connected { first.fulfill() }
            if $0 == .disconnected { closed.fulfill() }
        }
        client.connect()
        wait(for: [first], timeout: 3)
        client.disconnect(afterSendingKeySequence: MacKeyMap.MacShortcut.lockScreen.keySequence)
        wait(for: [closed], timeout: 3)
        let replacement = expectation(description: "Replacement connection")
        client.onStateChanged = { if $0 == .connected { replacement.fulfill() } }
        client.setInputEnabled(true)
        client.connect()
        wait(for: [replacement], timeout: 3)
        let oldTimeout = expectation(description: "Past old close deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { oldTimeout.fulfill() }
        wait(for: [oldTimeout], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        let input = expectation(description: "Replacement still accepts input")
        server.onKey = { if $0.key == MacKeyMap.escape && !$0.down { input.fulfill() } }
        client.sendKeyEvent(down: true, keySym: MacKeyMap.escape)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.escape)
        wait(for: [input], timeout: 3)
    }
    func testDisconnectSendsCompleteFinalChordBeforeClosing() throws {
        let ready = expectation(description: "Final chord listener")
        let connected = expectation(description: "Final chord connected")
        let delivered = expectation(description: "Final chord released")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        server.onKey = { key in if key.key == MacKeyMap.controlLeft && !key.down { delivered.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        let chord = MacKeyMap.MacShortcut.lockScreen.keySequence
        client.disconnect(afterSendingKeySequence: chord)
        client.disconnect(afterSendingKeySequence: chord)
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(server.keys.map(\.key), chord.map(\.key))
        XCTAssertEqual(server.keys.map(\.down), chord.map(\.down))
    }
    @MainActor
    func testCancelledQueuedLockShortcutDoesNotReachWire() throws {
        let ready = expectation(description: "Lock shortcut listener")
        let connected = expectation(description: "Lock shortcut connection")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Lock QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.client.disconnect(); session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.curtainManager.setCurtain(active: true)
        session.curtainManager.setCurtain(active: false)
        let drained = expectation(description: "Queued shortcut callbacks drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertTrue(server.keys.isEmpty, "Cancelled local lock notice must not lock the remote screen")
        session.curtainManager.setCurtain(active: true)
        session.setForegroundSession(false)
        session.setForegroundSession(true)
        let selectionDrained = expectation(description: "Old foreground shortcut callback drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { selectionDrained.fulfill() }
        wait(for: [selectionDrained], timeout: 2)
        XCTAssertEqual(session.client.state, .connected, "Switching selection must preserve the active socket")
        XCTAssertTrue(server.keys.isEmpty, "Switching away and back must not resurrect an old queued lock")
        session.curtainManager.setCurtain(active: true)
        session.curtainManager.setCurtain(active: false)
        session.curtainManager.setCurtain(active: true)
        let delivered = expectation(description: "Intentional lock chord delivered")
        server.onKey = { key in if key.key == MacKeyMap.commandLeft && !key.down { delivered.fulfill() } }
        wait(for: [delivered], timeout: 2)
        let settled = expectation(description: "Lock chord settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(server.keys.count, 6, "Rapid toggles must send only the final intentional chord")
        XCTAssertTrue(server.keys.contains { $0.key == UInt32(Character("q").asciiValue!) && $0.down })
    }

    func testKeyboardInputDuringHandshakeCannotCorruptProtocolOnWire() throws {
        let ready = expectation(description: "Handshake input listener")
        let connected = expectation(description: "Input cannot corrupt handshake")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onStateChanged = { [weak client] state in
            if state == .negotiatingVersion || state == .initializing {
                client?.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
                client?.sendText("QA")
            }
            if state == .connected { connected.fulfill() }
        }
        client.connect()
        wait(for: [connected], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        XCTAssertTrue(server.keys.isEmpty, "Pre-handshake input must never enter the wire")
        client.sendKeyEvent(down: true, keySym: MacKeyMap.escape)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.escape)
        waitUntil { server.keys.count == 2 }
        XCTAssertEqual(server.keys.map { $0.key }, [MacKeyMap.escape, MacKeyMap.escape])
    }

    func testActualTCPTransportReportSuppliesPositiveRTT() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        let measured = expectation(description: "Kernel TCP transport RTT")
        client.onTransportRTT = { milliseconds in
            XCTAssertTrue(milliseconds.isFinite)
            XCTAssertGreaterThan(milliseconds, 0)
            measured.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.1) {
            client.sendPointerEvent(buttonMask: [], x: 10, y: 20)
        }
        wait(for: [measured], timeout: 4)
        client.onTransportRTT = nil
        // A local transport report can finish before the peer consumes the packet.
        waitUntil { server.pointers.contains { $0.x == 10 && $0.y == 20 } }
        XCTAssertTrue(server.pointers.contains { $0.x == 10 && $0.y == 20 })
    }

    func testHardwareKeyboardShortcutRepeatAndFocusReleaseReachWire() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        var keyboard = HardwareKeyboardState()
        for (usage, text) in [(0xe3, ""), (6, "c"), (6, "C")] {
            client.sendKeyEvent(down: true, keySym: try XCTUnwrap(keyboard.begin(usage: usage, characters: text)))
        }
        for key in keyboard.releaseAll() { client.sendKeyEvent(down: false, keySym: key) }
        waitUntil { server.keys.count == 5 }
        XCTAssertEqual(server.keys.map { $0.key }, [MacKeyMap.commandLeft, 0x63, 0x63, 0x63, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map { $0.down }, [true, true, true, false, false])

        client.sendKeyEvent(down: true, keySym: MacKeyMap.shiftRight)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.arrowLeft)
        client.setInputEnabled(false)
        client.sendKeyEvent(down: true, keySym: 0x61)
        waitUntil { server.keys.count >= 9 }
        XCTAssertEqual(server.keys.count, 9)
        XCTAssertEqual(Set(server.keys.suffix(2).map { $0.key }), [MacKeyMap.shiftRight, MacKeyMap.arrowLeft])
        XCTAssertTrue(server.keys.suffix(2).allSatisfy { !$0.down })
        client.setInputEnabled(true)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.return)
        waitUntil { server.keys.count >= 11 }
        XCTAssertEqual(server.keys.count, 11, "Observe must not leak an extra key-down")
        XCTAssertEqual(server.keys.suffix(2).map { $0.key }, [MacKeyMap.return, MacKeyMap.return])
    }

    @MainActor
    func testOnceModifiersSurviveHoverAndDragThenReleaseAfterPointerUpOnWire() throws {
        let ready = expectation(description: "Modifier pointer listener ready")
        let connected = expectation(description: "Modifier pointer session connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Modifier pointer QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.cycleShift()
        session.sendNativePointer(buttonMask: [], x: 4, y: 4)
        XCTAssertEqual(session.shiftState, .activeOnce, "Hover must retain a pending modified click")
        session.trackpadEngine.beginDrag()
        session.trackpadEngine.handleSecondaryTap()
        XCTAssertEqual(session.shiftState, .activeOnce, "Releasing one button must preserve a modified drag")
        session.trackpadEngine.endDrag()
        XCTAssertEqual(session.shiftState, .inactive)
        waitUntil { server.keys.contains { $0.key == MacKeyMap.shiftLeft && !$0.down } }
        let first = try XCTUnwrap(server.inputEvents.firstIndex(of: "down:65505"))
        XCTAssertEqual(Array(server.inputEvents[first...]), ["down:65505", "pointer:0", "pointer:1", "pointer:5", "pointer:1", "pointer:0", "up:65505"], "The modifier release must follow the mouse-up on the actual TCP stream")

        session.cycleCmd(); session.cycleCmd()
        session.sendNativePointer(buttonMask: .left, x: 5, y: 5)
        session.sendNativePointer(buttonMask: [], x: 5, y: 5)
        XCTAssertEqual(session.cmdState, .locked, "A locked modifier survives clicks")
        session.cycleOption()
        session.sendNativePointer(buttonMask: .right, x: 6, y: 6)
        session.sendNativePointer(buttonMask: [], x: 6, y: 6)
        XCTAssertEqual(session.optState, .inactive, "The native pointer path must also consume a once modifier")
        XCTAssertEqual(session.cmdState, .locked)
        waitUntil { server.keys.contains { $0.key == MacKeyMap.optionLeft && !$0.down } }
        let native = try XCTUnwrap(server.inputEvents.firstIndex(of: "down:65513"))
        XCTAssertEqual(Array(server.inputEvents[native...]), ["down:65513", "pointer:4", "pointer:0", "up:65513"])
        session.isObserveOnly = true
        XCTAssertEqual(session.cmdState, .inactive)
        session.isObserveOnly = false
        // Cancel a native held button through local Pan, then verify a new hover
        // cannot consume a modifier for the next click in the resumed session.
        session.sendNativePointer(buttonMask: .left, x: 7, y: 7)
        session.isPanningViewport = true
        session.cycleShift()
        session.isPanningViewport = false
        session.sendNativePointer(buttonMask: [], x: 7, y: 7)
        XCTAssertEqual(session.shiftState, .activeOnce)
        session.sendNativePointer(buttonMask: .left, x: 7, y: 7)
        session.sendNativePointer(buttonMask: [], x: 7, y: 7)
        XCTAssertEqual(session.shiftState, .inactive)
        session.sendNativePointer(buttonMask: .left, x: 8, y: 8)
        session.isObserveOnly = true
        session.isObserveOnly = false
        session.cycleOption()
        session.sendNativePointer(buttonMask: [], x: 8, y: 8)
        XCTAssertEqual(session.optState, .activeOnce, "A new input generation must forget cancelled pointer buttons")
        session.sendNativePointer(buttonMask: .right, x: 8, y: 8)
        session.sendNativePointer(buttonMask: [], x: 8, y: 8)
        XCTAssertEqual(session.optState, .inactive)
    }

    @MainActor
    func testToolbarHeldKeyRepeatsKeepOnceModifierAndCancelOnHideOnWire() throws {
        let ready = expectation(description: "Toolbar hold listener")
        let connected = expectation(description: "Toolbar hold connection")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Toolbar hold QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.isKeyboardVisible = true
        session.cycleShift()
        for _ in 0..<3 { session.repeatToolbarKey(MacKeyMap.arrowRight) }
        XCTAssertEqual(session.shiftState, .activeOnce)
        session.releaseToolbarKey(MacKeyMap.arrowRight)
        session.releaseToolbarKey(MacKeyMap.arrowRight)
        XCTAssertEqual(session.shiftState, .inactive)
        waitUntil { server.keys.count >= 6 }
        XCTAssertEqual(server.inputEvents, ["down:65505", "down:65363", "down:65363", "down:65363", "up:65363", "up:65505"])
        session.cycleCmd(); session.cycleCmd()
        session.repeatToolbarKey(MacKeyMap.pageDown)
        session.isKeyboardVisible = false
        session.repeatToolbarKey(MacKeyMap.pageDown)
        session.releaseToolbarKey(MacKeyMap.pageDown)
        XCTAssertEqual(session.cmdState, .locked)
        waitUntil { server.keys.count >= 9 }
        XCTAssertEqual(Array(server.inputEvents.dropFirst(6)), ["down:\(MacKeyMap.commandLeft)", "down:65366", "up:65366"])
        session.isKeyboardVisible = true
        session.repeatToolbarKey(MacKeyMap.delete)
        session.setForegroundSession(false)
        session.repeatToolbarKey(MacKeyMap.delete)
        session.releaseToolbarKey(MacKeyMap.delete)
        waitUntil { server.keys.count >= 12 }
        XCTAssertEqual(Array(server.inputEvents.dropFirst(9)), ["down:65535", "up:65535", "up:\(MacKeyMap.commandLeft)"])
    }

    @MainActor
    func testOnceModifierReleasesAfterDelayedWheelPairOnWire() throws {
        let ready = expectation(description: "Once wheel listener")
        let connected = expectation(description: "Once wheel connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Once wheel QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.cycleShift()
        session.trackpadEngine.handleScroll(deltaY: 10)
        XCTAssertEqual(session.shiftState, .activeOnce, "A queued wheel must keep its modifier until its actual pulse")
        waitUntil { server.pointers.contains { $0.mask == 8 } }
        waitUntil { session.shiftState == .inactive }
        let wheel = try XCTUnwrap(server.inputEvents.firstIndex(of: "pointer:8"))
        waitUntil { server.keys.contains { $0.key == MacKeyMap.shiftLeft && !$0.down } }
        XCTAssertEqual(Array(server.inputEvents[wheel...]), ["pointer:8", "pointer:0", "up:65505"])
    }

    @MainActor
    func testModifiedWheelDragCancellationAndNewModifierGenerationOnWire() throws {
        let ready = expectation(description: "Wheel lifecycle listener")
        let connected = expectation(description: "Wheel lifecycle connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Wheel lifecycle QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.cycleOption()
        session.trackpadEngine.beginDrag()
        session.trackpadEngine.handleScroll(deltaY: 10)
        session.trackpadEngine.endDrag()
        XCTAssertEqual(session.optState, .activeOnce, "Mouse-up cannot overtake its delayed wheel")
        waitUntil { session.optState == .inactive }
        waitUntil { server.keys.contains { $0.key == MacKeyMap.optionLeft && !$0.down } }
        let wheel = try XCTUnwrap(server.inputEvents.lastIndex(of: "pointer:8"))
        XCTAssertEqual(Array(server.inputEvents[wheel...]), ["pointer:8", "pointer:0", "up:65513"])

        // A newly selected Once is not the modifier captured by an earlier pulse.
        session.cycleShift()
        session.trackpadEngine.handleHorizontalScroll(deltaX: 10)
        session.cycleShift(); session.cycleShift(); session.cycleShift()
        let drained = expectation(description: "Delayed wheel and actor callback drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(session.shiftState, .activeOnce)
        session.sendNativePointer(buttonMask: .left, x: 3, y: 4)
        session.sendNativePointer(buttonMask: [], x: 3, y: 4)
        XCTAssertEqual(session.shiftState, .inactive)

        // Pan cancels queued pulses and must also clear the local pending count.
        session.cycleControl()
        session.trackpadEngine.handleScroll(deltaY: 10)
        session.isPanningViewport = true
        session.isPanningViewport = false
        session.sendNativePointer(buttonMask: .left, x: 5, y: 6)
        session.sendNativePointer(buttonMask: [], x: 5, y: 6)
        XCTAssertEqual(session.ctrlState, .inactive, "A cancelled wheel cannot block subsequent modifier consumption")
        let settled = expectation(description: "Cancelled wheel settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        let oldWheels = server.pointers.filter { $0.mask & 0x78 != 0 }.count
        session.cycleOption()
        session.trackpadEngine.handleScroll(deltaY: 10)
        session.toggleFullscreen()
        session.sendNativePointer(buttonMask: .left, x: 7, y: 8)
        session.sendNativePointer(buttonMask: [], x: 7, y: 8)
        XCTAssertEqual(session.optState, .inactive)
        let resized = expectation(description: "Fullscreen cancels prior wheels")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { resized.fulfill() }
        wait(for: [resized], timeout: 1)
        XCTAssertEqual(server.pointers.filter { $0.mask & 0x78 != 0 }.count, oldWheels)
        session.cycleCmd(); session.cycleCmd()
        session.trackpadEngine.handleScroll(deltaY: -10)
        waitUntil { server.pointers.contains { $0.mask == 16 } }
        XCTAssertEqual(session.cmdState, .locked)
        session.cycleCmd()
        session.cycleOption()
        session.trackpadEngine.handleScroll(deltaY: 10)
        session.isObserveOnly = true
        session.isObserveOnly = false
        session.cycleShift()
        let observed = expectation(description: "Observe cancellation settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { observed.fulfill() }
        wait(for: [observed], timeout: 1)
        XCTAssertEqual(session.shiftState, .activeOnce, "Old cancelled callbacks must not clear a resumed modifier")
        session.trackpadEngine.handleScroll(deltaY: 10)
        waitUntil { session.shiftState == .inactive }
    }

    @MainActor
    func testEditingCommandsHaveCompleteChordsAndPreserveLockedCommandOnWire() throws {
        let ready = expectation(description: "Edit command listener")
        let connected = expectation(description: "Edit command session")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Edit command QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.sendCommandShortcut("c")
        waitUntil { server.keys.count >= 4 }
        XCTAssertEqual(server.keys.prefix(4).map { $0.key }, [MacKeyMap.commandLeft, 99, 99, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.prefix(4).map { $0.down }, [true, true, false, false])
        session.cycleCmd(); session.cycleCmd()
        session.sendCommandShortcut("v")
        XCTAssertEqual(session.cmdState, .locked)
        waitUntil { server.keys.count >= 7 }
        XCTAssertEqual(server.keys.dropFirst(4).map { $0.key }, [MacKeyMap.commandLeft, 118, 118])
        XCTAssertEqual(server.keys.dropFirst(4).map { $0.down }, [true, true, false])
        session.cycleCmd()
        session.cycleCmd()
        session.sendCommandShortcut("x")
        XCTAssertEqual(session.cmdState, .inactive)
        waitUntil { server.keys.count >= 12 }
        XCTAssertEqual(server.keys.suffix(4).map { $0.key }, [MacKeyMap.commandLeft, 120, 120, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.suffix(4).map { $0.down }, [true, true, false, false])
        session.isObserveOnly = true
        let count = server.keys.count
        session.sendCommandShortcut("a")
        let settled = expectation(description: "Observe edit commands are blocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(server.keys.count, count)
    }

    func testWheelDoesNotReleaseHeldMouseButton() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        client.sendPointerEvent(buttonMask: .left, x: 10, y: 20)
        client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: 10, y: 20)
        waitUntil { server.pointers.contains { $0.mask & 0x78 != 0 } && server.pointers.count >= 4 }
        XCTAssertTrue(server.pointers.allSatisfy { $0.mask & 1 != 0 }, "Wheel positioning and release must preserve the drag button on the wire")
        XCTAssertEqual(server.pointers.last?.mask, 1)
    }

    func testDelayedWheelUsesCurrentButtonsAndPositionAfterDragEnds() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        client.sendPointerEvent(buttonMask: .left, x: 10, y: 20)
        client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: 10, y: 20)
        client.sendPointerEvent(buttonMask: [], x: 100, y: 120)
        waitUntil { server.pointers.contains { $0.mask & 0x78 != 0 } && server.pointers.count >= 5 }
        let wheel = try XCTUnwrap(server.pointers.first { $0.mask & 0x78 != 0 })
        XCTAssertEqual(wheel.mask & 7, 0, "A queued wheel must not press a released drag button again")
        XCTAssertEqual(wheel.x, 100)
        XCTAssertEqual(wheel.y, 120)
        XCTAssertEqual(server.pointers.last?.mask, 0)
    }

    func testObserveCancelsWheelEvenWhenControlResumesImmediately() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        let unwanted = expectation(description: "Cancelled wheel reaches server")
        unwanted.isInverted = true
        server.onPointer = { if $0.mask & 0x78 != 0 { unwanted.fulfill() } }
        client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 20)
        client.setInputEnabled(false)
        client.setInputEnabled(true)
        client.sendPointerEvent(buttonMask: [], x: 100, y: 120)
        waitUntil { server.pointers.contains { $0.x == 100 } }
        wait(for: [unwanted], timeout: 0.15)
    }

    func testResumedControlDoesNotWaitForCancelledScrollBacklog() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        for _ in 0..<300 { client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 20) }
        // Actual positioning packets prove the old work has reserved wheel slots.
        waitUntil { server.pointers.count >= 300 }
        client.setInputEnabled(false)
        client.setInputEnabled(true)
        let freshWheel = expectation(description: "Fresh scrolling after Observe")
        server.onPointer = { if $0.mask == RFBConstants.ButtonMask.scrollUp.rawValue { freshWheel.fulfill() } }
        client.sendPointerEvent(buttonMask: .scrollUp, x: 100, y: 120)
        wait(for: [freshWheel], timeout: 1)
    }

    @MainActor
    func testPanCancelsQueuedWheelsWhileKeyboardAndResumedScrollStillWork() throws {
        let ready = expectation(description: "Pan listener ready")
        let connected = expectation(description: "Pan session connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let suite = "test.aetherscreens.pan.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults, legacySources: [])
        let session = SessionViewModel(device: RemoteDevice(name: "Pan transport QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, deviceStore: store)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.trackpadEngine.beginDrag()
        for _ in 0..<300 { session.client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: 10, y: 10) }
        waitUntil { server.pointers.filter { $0.mask == 1 }.count >= 300 }
        let released = expectation(description: "Pan releases remote mouse")
        server.onPointer = { if $0.mask == 0 { server.onPointer = nil; released.fulfill() } }
        session.isPanningViewport = true
        let key = expectation(description: "Keyboard remains usable during local pan")
        server.onKey = { if $0.down && $0.key == 97 { server.onKey = nil; key.fulfill() } }
        session.client.sendKeyEvent(down: true, keySym: 97)
        session.client.sendKeyEvent(down: false, keySym: 97)
        // The key receipt is a TCP barrier after switching modes; earlier bytes
        // already transmitted before cancellation are not queued old work.
        wait(for: [released, key], timeout: 1)
        let unwanted = expectation(description: "Pointer input continues while panning")
        unwanted.isInverted = true
        server.onPointer = { _ in server.onPointer = nil; unwanted.fulfill() }
        session.trackpadEngine.handleTap()
        session.sendNativePointer(buttonMask: .left, x: 10, y: 10)
        session.client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 10)
        wait(for: [unwanted], timeout: 0.2)
        // Observe's global input flag must not reopen the pointer gate when
        // control resumes while the local Pan mode is still selected.
        session.isObserveOnly = true
        session.isObserveOnly = false
        let nestedPointer = expectation(description: "Observe exit reopens mouse during Pan")
        nestedPointer.isInverted = true
        server.onPointer = { _ in server.onPointer = nil; nestedPointer.fulfill() }
        let restoredKey = expectation(description: "Observe exit restores keyboard during Pan")
        server.onKey = { if $0.down && $0.key == 98 { server.onKey = nil; restoredKey.fulfill() } }
        session.client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 10)
        session.client.sendKeyEvent(down: true, keySym: 98)
        session.client.sendKeyEvent(down: false, keySym: 98)
        wait(for: [restoredKey, nestedPointer], timeout: 0.2)
        session.isPanningViewport = false
        let fresh = expectation(description: "Fresh scrolling resumes without old backlog delay")
        server.onPointer = { if $0.mask == RFBConstants.ButtonMask.scrollUp.rawValue { server.onPointer = nil; fresh.fulfill() } }
        session.client.sendPointerEvent(buttonMask: .scrollUp, x: 12, y: 12)
        wait(for: [fresh], timeout: 0.5)
    }

    @MainActor
    func testDisplaySwitchReleasesAtOriginalPositionAndCancelsScrollBacklog() throws {
        let ready = expectation(description: "Display-switch listener ready")
        let connected = expectation(description: "Display-switch connection ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Display switch QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        let layout = RFBDisplayLayout(width: 16, height: 16, screens: [
            .init(id: 0, x: 0, y: 0, width: 8, height: 16, flags: 0),
            .init(id: 1, x: 8, y: 0, width: 8, height: 16, flags: 0)
        ])
        session.multiDisplayManager.updateFromLayout(layout)
        session.multiDisplayManager.selectDisplay(id: 2)
        waitUntil { session.activeCropRect?.minX == 8 }
        session.trackpadEngine.beginDrag()
        waitUntil { server.pointers.last?.mask == 1 }
        let held = try XCTUnwrap(server.pointers.last)
        XCTAssertGreaterThanOrEqual(held.x, 8)
        for _ in 0..<300 { session.client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: held.x, y: held.y) }
        waitUntil { server.pointers.filter { $0.mask == 1 }.count >= 301 }
        let beforeSwitch = server.pointers.count
        session.multiDisplayManager.selectDisplay(id: 1)
        waitUntil { session.activeCropRect?.minX == 0 }
        let barrier = expectation(description: "Keyboard barrier after display switch")
        server.onKey = { if $0.down && $0.key == 97 { server.onKey = nil; barrier.fulfill() } }
        session.client.sendKeyEvent(down: true, keySym: 97)
        session.client.sendKeyEvent(down: false, keySym: 97)
        wait(for: [barrier], timeout: 1)
        let released = try XCTUnwrap(server.pointers.dropFirst(beforeSwitch).first { $0.mask == 0 })
        XCTAssertEqual(released.x, held.x, "Release must use the last transmitted global position, before translating into the next display")
        XCTAssertEqual(released.y, held.y)
        let stale = expectation(description: "Old wheel reaches newly selected display")
        stale.isInverted = true
        let fresh = expectation(description: "New display scroll bypasses cancelled backlog")
        server.onPointer = { pointer in
            if pointer.mask & RFBConstants.ButtonMask.scrollDown.rawValue != 0 { stale.fulfill() }
            if pointer.mask == RFBConstants.ButtonMask.scrollUp.rawValue {
                XCTAssertLessThan(pointer.x, 8)
                fresh.fulfill()
            }
        }
        session.sendNativePointer(buttonMask: .scrollUp, x: 3, y: 4)
        wait(for: [fresh, stale], timeout: 0.5)
        // A duplicate layout callback must not cancel an ongoing gesture.
        server.onPointer = nil
        session.trackpadEngine.beginDrag()
        waitUntil { server.pointers.last?.mask == 1 }
        let unchangedGeneration = session.inputGeneration
        let unexpectedRelease = expectation(description: "Duplicate layout releases mouse")
        unexpectedRelease.isInverted = true
        server.onPointer = { if $0.mask == 0 { unexpectedRelease.fulfill() } }
        session.client.onDisplayLayoutReceived?(layout)
        wait(for: [unexpectedRelease], timeout: 0.2)
        XCTAssertEqual(session.inputGeneration, unchangedGeneration)
        server.onPointer = nil
    }

    @MainActor
    func testThreeFingerNavigationSendsCompleteShortcutsAndObserveKeepsFullscreenLocal() throws {
        let ready = expectation(description: "Three-finger shortcut listener ready")
        let connected = expectation(description: "Three-finger shortcut connection ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Three-finger QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.cycleCmd()
        session.handleThreeFingerSwipe(.up)
        waitUntil { server.keys.count >= 6 }
        XCTAssertEqual(server.keys.map { $0.key }, [0xFFEB, 0xFFEB, 0xFFE3, 0xFF52, 0xFF52, 0xFFE3])
        XCTAssertEqual(server.keys.map { $0.down }, [true, false, true, true, false, false])
        XCTAssertEqual(session.cmdState, .inactive)
        for (direction, arrow) in [(MacKeyMap.ThreeFingerSwipe.down, UInt32(0xFF54)), (.right, 0xFF51), (.left, 0xFF53)] {
            let start = server.keys.count
            session.handleThreeFingerSwipe(direction)
            waitUntil { server.keys.count >= start + 4 }
            XCTAssertEqual(server.keys.dropFirst(start).map { $0.key }, [0xFFE3, arrow, arrow, 0xFFE3])
            XCTAssertEqual(server.keys.dropFirst(start).map { $0.down }, [true, true, false, false])
        }
        session.isObserveOnly = true
        let unwanted = expectation(description: "Observe receives gesture shortcut")
        unwanted.isInverted = true
        server.onKey = { _ in unwanted.fulfill() }
        for direction in MacKeyMap.ThreeFingerSwipe.allCases { session.handleThreeFingerSwipe(direction) }
        session.zoomScale = 2
        session.viewOffset = CGSize(width: 8, height: 9)
        session.toggleFullscreen()
        XCTAssertTrue(session.isFullscreen)
        session.toggleFullscreen()
        XCTAssertFalse(session.isFullscreen)
        XCTAssertEqual(session.zoomScale, 2)
        XCTAssertEqual(session.viewOffset, CGSize(width: 8, height: 9))
        wait(for: [unwanted], timeout: 0.2)
        server.onKey = nil
    }

    private func connectedPair() throws -> (PointerWireServer, RFBClient) {
        let ready = expectation(description: "Loopback listener ready")
        let connected = expectation(description: "RFB handshake completed")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        return (server, client)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed)
    }
}

@MainActor
final class ClipboardSessionTests: XCTestCase {
    func testHiddenSessionRejectsInputAndClipboardUntilSelectedAgain() throws {
        let ready = expectation(description: "Hidden session listener ready")
        let connected = expectation(description: "Hidden session connected")
        let resumed = expectation(description: "Foreground clipboard delivered")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Background QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: {
            inbox.texts.append($0)
            if $0 == "foreground" { resumed.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.onClipboardReceived?("queued before hiding")
        session.setForegroundSession(false)
        session.isObserveOnly = false
        XCTAssertFalse(session.client.sendCutText("hidden upload"))
        session.client.sendKeyEvent(down: true, keySym: 97)
        session.client.sendPointerEvent(buttonMask: .left, x: 10, y: 10)
        server.sendClipboard("hidden server text")
        drainCallbacks()
        XCTAssertTrue(inbox.texts.isEmpty)
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertTrue(server.pointers.isEmpty)
        session.client.onClipboardReceived?("queued while hidden")
        session.setForegroundSession(true)
        drainCallbacks()
        XCTAssertTrue(inbox.texts.isEmpty, "Reactivation must reject clipboard work queued by the hidden session")
        server.sendClipboard("foreground")
        wait(for: [resumed], timeout: 2)
        XCTAssertEqual(inbox.texts, ["foreground"])
        XCTAssertTrue(session.client.sendCutText("foreground upload"))
        session.isObserveOnly = true
        session.setForegroundSession(false)
        session.setForegroundSession(true)
        XCTAssertFalse(session.client.sendCutText("Observe upload"))
        XCTAssertEqual(session.client.state, .connected, "Hiding and selecting must preserve the socket")
    }

    func testEndedSessionRejectsQueuedAndLaterClipboardDelivery() throws {
        let ready = expectation(description: "Clipboard listener ready")
        let connected = expectation(description: "Clipboard session connected")
        let delivered = expectation(description: "Actual server clipboard delivered")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "actual server clipboard café" { delivered.fulfill() }
        })
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.sendClipboard("actual server clipboard café")
        wait(for: [delivered], timeout: 2)
        let uploaded = expectation(description: "Actual Latin-1 client clipboard received")
        server.onCutText = { bytes in
            XCTAssertEqual(Array(bytes), [99, 97, 102, 233, 10, 110, 97, 239, 118, 101])
            uploaded.fulfill()
        }
        XCTAssertTrue(session.client.sendCutText("café\r\nnaïve"))
        XCTAssertFalse(session.client.sendCutText("中文 😀"), "A legacy-only server must not receive corrupt UTF-8 as Latin-1")
        session.client.setInputEnabled(false)
        XCTAssertFalse(session.client.sendCutText("blocked during Observe"))
        session.client.setInputEnabled(true)
        wait(for: [uploaded], timeout: 2)
        session.client.onClipboardReceived?("queued before end")
        session.endSession()
        session.client.onClipboardReceived?("delivered after end")
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["actual server clipboard café"])
    }

    func testReconnectRejectsOldClipboardButAcceptsNewServerText() throws {
        let ready = expectation(description: "Reconnect clipboard listener ready")
        let connected = expectation(description: "First clipboard session connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let delivered = expectation(description: "New server clipboard delivered")
        let session = SessionViewModel(device: RemoteDevice(name: "Reconnect clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "new session text" { delivered.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.onClipboardReceived?("queued before reconnect")
        let reconnected = expectation(description: "New clipboard session connected")
        session.client.onStateChanged = { if $0 == .connected { reconnected.fulfill() } }
        session.reconnectSession()
        wait(for: [reconnected], timeout: 3)
        server.sendClipboard("new session text")
        wait(for: [delivered], timeout: 2)
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["new session text"])
    }

    func testServerNegotiatesUnicodeOnlyAfterClientAdvertisesClipboardExtension() throws {
        let ready = expectation(description: "Clipboard listener ready")
        let negotiated = expectation(description: "Advertised extension negotiated over TCP")
        let server = try PointerWireServer(advertiseClipboard: true, ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        server.onExtendedClipboard = { flags, _ in
            if flags == 0x1F000001 { negotiated.fulfill() }
        }
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.connect()
        wait(for: [negotiated], timeout: 3)
        XCTAssertTrue(client.sendCutText("协商后的中文"))
    }

    func testExtendedUnicodeClipboardRoundTripAndObserveRequestSuppression() throws {
        let ready = expectation(description: "Extended clipboard listener ready")
        let connected = expectation(description: "Extended clipboard session ready")
        let caps = expectation(description: "Client capabilities received on TCP")
        let uploaded = expectation(description: "Compressed Unicode uploaded on TCP")
        let downloaded = expectation(description: "Compressed Unicode downloaded through session")
        let forbidden = expectation(description: "Observe provides clipboard after delayed request")
        forbidden.isInverted = true
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        var clipboardReads = 0
        let session = SessionViewModel(device: RemoteDevice(name: "Extended clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "远端 😀\nsecond line" { downloaded.fulfill() }
        }, clipboardReader: {
            clipboardReads += 1
            return "客户端 中文 😀\nsecond line\n"
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.onExtendedClipboard = { (flags: UInt32, payload: Data) in
            if flags == 0x1F000001 {
                XCTAssertEqual(payload, Data([0, 0, 0, 0]))
                caps.fulfill()
            } else if flags == 0x08000001 {
                server.sendExtendedClipboard(flags: 0x02000001)
            } else if flags == 0x10000001 {
                do {
                    let plain = try ClipboardWireData.decompress(payload)
                    let expected = Data("客户端 中文 😀\r\nsecond line\r\n".utf8) + Data([0])
                    let declaredSize = plain.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    XCTAssertEqual(declaredSize, UInt32(expected.count))
                    XCTAssertEqual(Data(plain.dropFirst(4)), expected)
                    uploaded.fulfill()
                } catch { XCTFail("Cannot read actual compressed clipboard: \(error)") }
            }
        }
        server.sendExtendedClipboard(flags: 0x1F000001, payload: Data([0, 0, 0, 0]))
        wait(for: [caps], timeout: 2)
        session.sendLocalClipboardToRemote()
        XCTAssertEqual(clipboardReads, 1)
        wait(for: [uploaded], timeout: 2)
        let remotePayload = try ClipboardWireData.compress("远端 😀\r\nsecond line")
        session.isObserveOnly = true
        server.onExtendedClipboard = { flags, _ in
            if flags == 0x10000001 { forbidden.fulfill() }
            if flags == 0x02000001 { server.sendExtendedClipboard(flags: 0x10000001, payload: remotePayload) }
        }
        session.sendLocalClipboardToRemote()
        XCTAssertEqual(clipboardReads, 1, "Observe must not access the local clipboard")
        XCTAssertFalse(session.client.sendCutText("Observe must not upload"))
        server.sendExtendedClipboard(flags: 0x02000001)
        server.sendExtendedClipboard(flags: 0x08000001)
        // The received download is a barrier after the delayed server request.
        wait(for: [downloaded], timeout: 2)
        wait(for: [forbidden], timeout: 0.15)
        XCTAssertEqual(inbox.texts, ["远端 😀\nsecond line"])
    }

    func testTruncatedCapabilityMessageDoesNotEnableUnicodeUploads() throws {
        let ready = expectation(description: "Malformed capabilities listener ready")
        let connected = expectation(description: "Malformed capabilities connection ready")
        let barrier = expectation(description: "Following legacy clipboard decoded")
        let nonTextBarrier = expectation(description: "Non-text capabilities followed by legacy text")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Malformed clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            if text == "capability barrier" { barrier.fulfill() }
            else if text == "non-text capability barrier" { nonTextBarrier.fulfill() }
            else { XCTFail("Unexpected fixture clipboard text") }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        // Text capabilities require a four-byte size after their flags.
        server.sendExtendedClipboard(flags: 0x1F000001)
        server.sendClipboard("capability barrier")
        wait(for: [barrier], timeout: 2)
        XCTAssertFalse(session.client.sendCutText("中文 😀"))
        server.sendExtendedClipboard(flags: 0x1F000002, payload: Data([0, 0, 0, 0]))
        server.sendClipboard("non-text capability barrier")
        wait(for: [nonTextBarrier], timeout: 2)
        XCTAssertFalse(session.client.sendCutText("中文 😀"), "RTF-only capabilities cannot enable UTF-8 text uploads")
    }

    func testUnterminatedExtendedTextDoesNotOverwriteClipboardOrBreakNextMessage() throws {
        let ready = expectation(description: "Unterminated clipboard listener ready")
        let connected = expectation(description: "Unterminated clipboard connection ready")
        let barrier = expectation(description: "Valid clipboard after malformed payload received")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Unterminated clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "valid clipboard barrier" { barrier.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.sendExtendedClipboard(flags: 0x1F000001, payload: Data([0, 0, 0, 0]))
        server.sendExtendedClipboard(flags: 0x10000001, payload: try ClipboardWireData.compress("malformed 中文", terminated: false))
        server.sendClipboard("valid clipboard barrier")
        wait(for: [barrier], timeout: 2)
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["valid clipboard barrier"])
    }

    private func drainCallbacks() {
        let drained = expectation(description: "Clipboard UI tasks drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

@MainActor
private final class ClipboardInbox {
    var texts: [String] = []
}

private enum ClipboardWireData {
    static func compress(_ text: String, terminated: Bool = true) throws -> Data {
        let bytes = Data(text.utf8) + (terminated ? Data([0]) : Data())
        var plain = Data()
        plain.append(contentsOf: withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Array($0) })
        plain.append(bytes)
        var length = compressBound(uLong(plain.count))
        var compressed = [UInt8](repeating: 0, count: Int(length))
        let status = plain.withUnsafeBytes { compress2(&compressed, &length, $0.bindMemory(to: UInt8.self).baseAddress!, uLong(plain.count), Z_DEFAULT_COMPRESSION) }
        XCTAssertEqual(status, Z_OK)
        return Data(compressed.prefix(Int(length)))
    }
    static func decompress(_ compressed: Data) throws -> Data {
        var length: uLongf = 1_048_576
        var bytes = [UInt8](repeating: 0, count: Int(length))
        let status = compressed.withUnsafeBytes { uncompress(&bytes, &length, $0.bindMemory(to: UInt8.self).baseAddress!, uLong(compressed.count)) }
        guard status == Z_OK else { throw NSError(domain: "ClipboardWireFixture", code: Int(status)) }
        return Data(bytes.prefix(Int(length)))
    }
}

/// Inspects real TCP messages after a minimal RFB handshake; no client send hooks.
final class PointerWireServer: @unchecked Sendable {
    struct Pointer { let mask: UInt8; let x: UInt16; let y: UInt16 }
    struct Key { let down: Bool; let key: UInt32 }
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.pointer-wire-qa")
    private let lock = NSLock()
    private var received: [Pointer] = []
    private var receivedKeys: [Key] = []
    private var receivedInputEvents: [String] = []
    private var connection: NWConnection?
    private var pointerHandler: ((Pointer) -> Void)?
    var onPointer: ((Pointer) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return pointerHandler }
        set { lock.lock(); pointerHandler = newValue; lock.unlock() }
    }
    private var keyHandler: ((Key) -> Void)?
    var onKey: ((Key) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return keyHandler }
        set { lock.lock(); keyHandler = newValue; lock.unlock() }
    }
    private var cutTextHandler: ((Data) -> Void)?
    var onCutText: ((Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return cutTextHandler }
        set { lock.lock(); cutTextHandler = newValue; lock.unlock() }
    }
    private var fileCopyHandler: ((Data) -> Void)?
    var onFileCopyWire: ((Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return fileCopyHandler }
        set { lock.lock(); fileCopyHandler = newValue; lock.unlock() }
    }
    private var extendedClipboardHandler: ((UInt32, Data) -> Void)?
    var onExtendedClipboard: ((UInt32, Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return extendedClipboardHandler }
        set { lock.lock(); extendedClipboardHandler = newValue; lock.unlock() }
    }
    var inputEvents: [String] { lock.lock(); defer { lock.unlock() }; return receivedInputEvents }
    var keys: [Key] { lock.lock(); defer { lock.unlock() }; return receivedKeys }
    var pointers: [Pointer] { lock.lock(); defer { lock.unlock() }; return received }

    private let advertiseClipboard: Bool
    init(advertiseClipboard: Bool = false, nativeBanner: Bool = false, ready: @escaping () -> Void) throws {
        self.advertiseClipboard = advertiseClipboard
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connection = connection
            connection.start(queue: self.queue)
            self.send(Data((nativeBanner ? "RFB 003.889\n" : "RFB 003.008\n").utf8))
            self.read(12) { version in
                guard version == Data("RFB 003.008\n".utf8) else { XCTFail("Keyboard bytes corrupted the protocol version"); return }
                self.send(Data([1, 1]))
                self.read(1) { _ in
                    self.send(Data([0, 0, 0, 0]))
                    self.read(1) { _ in
                        var initial = Data([0, 16, 0, 16])
                        initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                        initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                        self.send(initial)
                        self.readMessage()
                    }
                }
            }
        }
        listener.start(queue: queue)
    }
    func stop() { onFileCopyWire = nil; onPointer = nil; onKey = nil; onCutText = nil; onExtendedClipboard = nil; connection?.cancel(); listener.cancel() }
    func sendFileCopyFixture(_ bytes: Data) { send(bytes) }
    func sendFileCopyFragments(_ fragments: [Data], closeAfter: Bool = false) {
        queue.async { [weak self] in self?.sendNextFileCopyFragment(fragments, closeAfter: closeAfter) }
    }
    private func sendNextFileCopyFragment(_ fragments: [Data], closeAfter: Bool) {
        guard let connection else { return }
        guard let fragment = fragments.first else {
            if closeAfter { connection.cancel() }
            return
        }
        connection.send(content: fragment, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { return }
            self.queue.asyncAfter(deadline: .now() + 0.03) {
                self.sendNextFileCopyFragment(Array(fragments.dropFirst()), closeAfter: closeAfter)
            }
        })
    }
    func sendGreenFrame() {
        var packet = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 16, 0, 0, 0, 0])
        for _ in 0..<256 { packet.append(contentsOf: [0, 255, 0, 255]) }
        send(packet)
    }
    func sendClipboard(_ text: String) {
        guard let body = text.data(using: .isoLatin1, allowLossyConversion: false) else { XCTFail("Legacy fixture text must be Latin-1"); return }
        var packet = Data([3, 0, 0, 0])
        packet.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) })
        packet.append(body)
        send(packet)
    }
    func sendExtendedClipboard(flags: UInt32, payload: Data = Data()) {
        var body = Data()
        body.append(contentsOf: withUnsafeBytes(of: flags.bigEndian) { Array($0) })
        body.append(payload)
        var packet = Data([3, 0, 0, 0])
        packet.append(contentsOf: withUnsafeBytes(of: Int32(-body.count).bigEndian) { Array($0) })
        packet.append(body)
        send(packet)
    }
    private func send(_ data: Data) { connection?.send(content: data, completion: .contentProcessed { _ in }) }
    private func read(_ count: Int, accumulated: Data = Data(), done: @escaping (Data) -> Void) {
        if accumulated.count == count { done(accumulated); return }
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, finished, error in
            guard let self, self.connection === connection, let data, !data.isEmpty, error == nil else { return }
            let next = accumulated + data
            if next.count == count { done(next) }
            else if !finished { self.read(count, accumulated: next, done: done) }
        }
    }
    private func readMessage() {
        read(1) { [weak self] type in
            guard let self else { return }
            switch type[0] {
            case 0x22:
                self.read(5) { prefix in
                    let length = prefix.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    guard (8...1_048_576).contains(length) else { XCTFail("Invalid file-copy fixture length"); return }
                    self.read(Int(length)) { body in
                        self.onFileCopyWire?(Data([0x22]) + prefix + body)
                        self.readMessage()
                    }
                }
            case 0: self.read(19) { _ in self.readMessage() }
            case 2:
                self.read(3) { header in
                    let count = Int(header[1]) << 8 | Int(header[2])
                    self.read(count * 4) { bytes in
                        let encodings = stride(from: 0, to: bytes.count, by: 4).map { offset in
                            bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                        }
                        if self.advertiseClipboard && encodings.contains(0xC0A1E5CE) {
                            self.sendExtendedClipboard(flags: 0x1F000001, payload: Data([0, 0, 0, 0]))
                        }
                        self.readMessage()
                    }
                }
            case 3: self.read(9) { _ in self.readMessage() }
            case 4:
                self.read(7) { body in
                    let key = Key(down: body[0] != 0, key: UInt32(body[3]) << 24 | UInt32(body[4]) << 16 | UInt32(body[5]) << 8 | UInt32(body[6]))
                    self.lock.lock(); self.receivedKeys.append(key); self.receivedInputEvents.append("\(key.down ? "down" : "up"):\(key.key)"); self.lock.unlock()
                    self.onKey?(key)
                    self.readMessage()
                }
            case 5:
                self.read(5) { body in
                    let pointer = Pointer(mask: body[0], x: UInt16(body[1]) << 8 | UInt16(body[2]), y: UInt16(body[3]) << 8 | UInt16(body[4]))
                    self.lock.lock(); self.received.append(pointer); self.receivedInputEvents.append("pointer:\(pointer.mask)"); self.lock.unlock()
                    self.onPointer?(pointer)
                    self.readMessage()
                }
            case 6:
                self.read(7) { header in
                    let length = header.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    let signed = Int32(bitPattern: length)
                    let size = abs(Int64(signed))
                    guard size <= 1_048_576 else { XCTFail("Unexpected clipboard size"); return }
                    self.read(Int(size)) { bytes in
                        if signed < 0 {
                            guard bytes.count >= 4 else { XCTFail("Truncated clipboard flags"); return }
                            let flags = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                            self.onExtendedClipboard?(flags, Data(bytes.dropFirst(4)))
                        } else { self.onCutText?(bytes) }
                        self.readMessage()
                    }
                }
            default: XCTFail("Unexpected client message in pointer test: \(type[0])")
            }
        }
    }
}
