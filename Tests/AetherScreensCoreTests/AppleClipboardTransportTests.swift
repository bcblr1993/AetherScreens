import XCTest
import Network
import zlib
@testable import AetherScreensCore

final class AppleClipboardTransportTests: XCTestCase {
    func testLargeUnicodeUploadCrossesTCPReceiveChunksWithoutTruncation() throws {
        let frame = expectation(description: "Large upload session ready")
        let uploaded = expectation(description: "Complete large Unicode archive decoded by peer")
        let text = (0..<40_000).map { "row\($0): 中文🙂\n" }.joined()
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        server.observeUploads { actual in XCTAssertEqual(actual, text); uploaded.fulfill() }
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertTrue(client.sendCutText(text))
        wait(for: [uploaded], timeout: 5)
        XCTAssertGreaterThan(try XCTUnwrap(server.uploadedSizes.first), 65_536)
        XCTAssertEqual(server.uploads, 1)
        XCTAssertEqual(client.state, .connected)
    }
    func testEncodedUploadWaitingOnConnectionQueueCannotSurviveObserve() throws {
        try verifyEncodedUploadInvalidation(reconnect: false)
    }

    func testEncodedUploadWaitingOnConnectionQueueCannotReachReplacementSocket() throws {
        try verifyEncodedUploadInvalidation(reconnect: true)
    }

    private func verifyEncodedUploadInvalidation(reconnect: Bool) throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let callbacks = AppleClipboardCounter()
        let uploaded = expectation(description: "Only fresh encoded content reaches peer")
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop(); release.signal() }
        server.observeUploads { text in XCTAssertEqual(text, "fresh"); uploaded.fulfill() }
        let worker = DispatchQueue(label: "qa.clipboard.encoded.worker")
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user", decodeQueue: worker)
        defer { client.disconnect() }
        client.onClipboardReceived = { _ in
            if callbacks.increment() == 1 {
                entered.signal()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        client.connect()
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(client.sendCutText("stale"))
        // The worker has encoded and queued the send behind the held callback.
        worker.sync {}
        if reconnect {
            client.onFrameUpdated = { [weak client] in XCTAssertTrue(client?.sendCutText("fresh") == true) }
            client.disconnect(); client.connect()
        } else {
            client.setInputEnabled(false); client.setInputEnabled(true)
            XCTAssertTrue(client.sendCutText("fresh"))
        }
        release.signal()
        wait(for: [uploaded], timeout: 5)
        XCTAssertEqual(server.uploads, 1)
        XCTAssertEqual(client.state, .connected)
    }

    func testNativeUnicodeUploadAndQueuedCoalescingPreservePan() throws {
        let frame = expectation(description: "Upload session ready")
        let uploaded = expectation(description: "Only latest Unicode upload reaches peer")
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        server.observeUploads { text in
            XCTAssertEqual(text, "latest 中文🙂\nline"); uploaded.fulfill()
        }
        let worker = DispatchQueue(label: "qa.clipboard.upload.worker")
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user", decodeQueue: worker)
        defer { client.disconnect() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        worker.suspend()
        for index in 0..<100 { XCTAssertTrue(client.sendCutText("pending \(index)")) }
        XCTAssertTrue(client.sendCutText("latest 中文🙂\r\nline"))
        client.setPointerInputEnabled(false)
        client.cancelPendingWheelEvents()
        worker.resume()
        wait(for: [uploaded], timeout: 5)
        XCTAssertEqual(server.uploads, 1)
        XCTAssertEqual(client.state, .connected)
        XCTAssertFalse(client.sendCutText(String(repeating: "x", count: 1_048_001)))
    }

    func testObserveInvalidatesQueuedUploadEvenAfterReturningToControl() throws {
        let frame = expectation(description: "Observe upload session ready")
        let uploaded = expectation(description: "Fresh control upload reaches peer")
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        server.observeUploads { text in XCTAssertEqual(text, "fresh"); uploaded.fulfill() }
        let worker = DispatchQueue(label: "qa.clipboard.observe.worker")
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user", decodeQueue: worker)
        defer { client.disconnect() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        worker.suspend()
        XCTAssertTrue(client.sendCutText("stale"))
        client.setInputEnabled(false)
        XCTAssertFalse(client.sendCutText("blocked"))
        client.setInputEnabled(true)
        XCTAssertTrue(client.sendCutText("fresh"))
        worker.resume()
        wait(for: [uploaded], timeout: 5)
        XCTAssertEqual(server.uploads, 1)
    }
    func testNativeUnicodeAndStatusInterleaveWithFramebuffer() throws {
        let clipboard = expectation(description: "Unicode native clipboard received")
        let frame = expectation(description: "Framebuffer follows clipboard without desynchronization")
        let status = expectation(description: "Non-clipboard control command preserved")
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onAppleStatusReceived = { command in
            XCTAssertEqual(command, 4)
            status.fulfill()
        }
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "中文🙂\nsecond line"); clipboard.fulfill()
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [clipboard, frame, status], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(server.fetches, 1)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(Data([1, 2, 3, 255])))
    }

    func testChangeNotificationsDuringFetchCoalesceToOneRefetch() throws {
        let delivered = expectation(description: "Initial and latest clipboard archives")
        delivered.expectedFulfillmentCount = 2
        let frame = expectation(description: "Refetch preserves desktop framing")
        let server = try makeServer { index in
            let changed = Data([20, 0, 0, 4, 0, 1, 0, 2])
            return (index == 1 ? changed + changed : Data()) + Self.unicodeFixture
        }
        defer { server.stop() }
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onClipboardReceived = { _ in delivered.fulfill() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [delivered, frame], timeout: 5)
        XCTAssertEqual(server.fetches, 2)
        XCTAssertEqual(client.state, .connected)
    }

    func testEmptyArchiveDeliversExplicitClearAndPreservesNextFrame() throws {
        let delivered = expectation(description: "Explicit empty clipboard delivered")
        let frame = expectation(description: "Frame after empty clipboard")
        let server = try makeServer { _ in Data(hex: "1f000000000000000000000000000007789c000000ffff") }
        defer { server.stop() }
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onClipboardReceived = { text in XCTAssertEqual(text, ""); delivered.fulfill() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [delivered, frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
    }

    func testIncompleteNativeBodyHasBoundedReadDeadline() throws {
        let failed = expectation(description: "Incomplete archive cannot stall forever")
        let server = try makeServer { _ in Data(Self.unicodeFixture.prefix(16)) }
        defer { server.stop() }
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onStateChanged = { if case .failed(let reason) = $0 {
            XCTAssertEqual(reason, "Native clipboard data timed out"); failed.fulfill()
        } }
        client.onClipboardReceived = { _ in XCTFail("Incomplete archive must not deliver") }
        client.connect()
        wait(for: [failed], timeout: 18)
    }

    func testPromiseAndUnknownFlavorDoNotClearClipboard() throws {
        for promise in [false, true] {
            let frame = expectation(description: "Ignored archive followed by valid image")
            let archive = promise ? Self.unicodeFixture : Self.unsupportedFixture()
            var packet = archive
            if promise { packet[2] = 1 }
            let response = packet
            let server = try makeServer { _ in response }
            defer { server.stop() }
            let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
            defer { client.disconnect() }
            client.onClipboardReceived = { _ in XCTFail("Metadata/unsupported flavor must not overwrite clipboard") }
            client.onFrameUpdated = { frame.fulfill() }
            client.connect()
            wait(for: [frame], timeout: 5)
            XCTAssertEqual(client.state, .connected)
            XCTAssertEqual(server.fetches, 1)
        }
    }

    func testOversizedNativeHeaderFailsBeforeReadingBody() throws {
        var bad = Data(Self.unicodeFixture.prefix(16))
        bad.replaceSubrange(12..<16, with: Self.word(AppleClipboardArchive.maximumBytes + 1))
        let response = bad
        let server = try makeServer { _ in response }
        defer { server.stop() }
        let failed = expectation(description: "Untrusted announced size rejected")
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onStateChanged = { if case .failed(let reason) = $0 {
            XCTAssertEqual(reason, "Native clipboard exceeds the supported size"); failed.fulfill()
        } }
        client.onClipboardReceived = { _ in XCTFail("Invalid archive must not deliver") }
        client.connect()
        wait(for: [failed], timeout: 5)
    }

    func testClipboardCallbackReconnectDoesNotStartOldLoopOnReplacement() throws {
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        let delivered = expectation(description: "Replacement receives its own clipboard")
        let frame = expectation(description: "Replacement keeps image transport")
        let counter = AppleClipboardCounter()
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onClipboardReceived = { [weak client] text in
            XCTAssertEqual(text, "中文🙂\nsecond line")
            if counter.increment() == 1 { client?.disconnect(); client?.connect() }
            else { delivered.fulfill() }
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [delivered, frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(server.fetches, 2)
    }

    func testOrdinaryBannerDoesNotEnableNativeMessages() throws {
        let server = try makeServer(apple: false) { _ in XCTFail("Ordinary server must not receive vendor fetch"); return Data() }
        defer { server.stop() }
        let frame = expectation(description: "Ordinary account-authenticated frame")
        let client = RFBClient(host: "127.0.0.1", port: server.port, password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(server.fetches, 0)
        XCTAssertEqual(client.state, .connected)
    }

    func testStatusCallbackReconnectCannotConsumeReplacementMessages() throws {
        let server = try makeServer { _ in Self.unicodeFixture }
        defer { server.stop() }
        let replacement = expectation(description: "Replacement receives its own archive")
        let frame = expectation(description: "Replacement receives pixels")
        let counter = AppleClipboardCounter()
        let client = RFBClient(host: "127.0.0.1", port: server.port,
            password: "fixture-password", username: "qa-user")
        defer { client.disconnect() }
        client.onAppleStatusReceived = { [weak client] command in
            XCTAssertEqual(command, 4)
            if counter.increment() == 1 { client?.disconnect(); client?.connect() }
        }
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "中文🙂\nsecond line")
            replacement.fulfill()
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [replacement, frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(server.fetches, 2)
    }

    private func makeServer(apple: Bool = true, response: @escaping @Sendable (Int) -> Data) throws -> AppleClipboardWireServer {
        let ready = expectation(description: "Clipboard listener ready")
        let server = try AppleClipboardWireServer(apple: apple, ready: { ready.fulfill() }, response: response)
        wait(for: [ready], timeout: 3)
        return server
    }
    private static let unicodeFixture = Data(hex: "1f000000000000000000007000000065789c62606060646060102b284dcac94cd62b2d49b3d02dc849ccccd32d49ad28618000900a01a88adcccdc54dd92ca8254a09804488d3e58b97572466251716a892dd0045d0b90894f76ac7d36adfdc3fc994d5cc5a9c9f979290a399979a900000000ffff")
    private static func word(_ value: Int) -> Data {
        var be = UInt32(value).bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }
    private static func unsupportedFixture() -> Data {
        let uti = Data("public.png".utf8)
        let plain = word(1) + word(uti.count) + uti + word(0) + word(0) + word(2) + Data([1, 2])
        var size = compressBound(uLong(plain.count))
        var output = [UInt8](repeating: 0, count: Int(size))
        let status = plain.withUnsafeBytes { bytes in
            compress2(&output, &size, bytes.baseAddress!.assumingMemoryBound(to: Bytef.self), uLong(plain.count), Z_DEFAULT_COMPRESSION)
        }
        XCTAssertEqual(status, Z_OK)
        return Data([31, 0, 0, 0, 0, 0, 0, 0]) + word(plain.count) + word(Int(size)) + Data(output.prefix(Int(size)))
    }
}

private final class AppleClipboardCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Only the message transport is under test; synthetic ARD credential response
/// length is consumed here. Credential validity is covered independently.
private final class AppleClipboardWireServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "qa.apple.clipboard.wire")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private let counter = AppleClipboardCounter()
    private let uploadCounter = AppleClipboardCounter()
    private var uploadObserver: (@Sendable (String) -> Void)?
    private var uploadSizes: [Int] = []
    private let response: @Sendable (Int) -> Data
    var port: UInt16 { listener.port!.rawValue }
    var fetches: Int { counter.count }
    var uploads: Int { uploadCounter.count }
    var uploadedSizes: [Int] { lock.lock(); defer { lock.unlock() }; return uploadSizes }
    func observeUploads(_ observer: @escaping @Sendable (String) -> Void) {
        lock.lock(); uploadObserver = observer; lock.unlock()
    }
    init(apple: Bool, ready: @escaping @Sendable () -> Void, response: @escaping @Sendable (Int) -> Data) throws {
        self.response = response
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue)
            self.send(connection, Data((apple ? "RFB 003.889\n" : "RFB 003.008\n").utf8)) {
                Self.read(connection, 12) { version in
                    XCTAssertEqual(version, Data("RFB 003.008\n".utf8))
                    self.send(connection, Data([1, 30])) {
                        Self.read(connection, 1) { type in
                            XCTAssertEqual(type, Data([30]))
                            let prime = Data(repeating: 255, count: 15) + Data([0x61])
                            let peer = Data(repeating: 0, count: 15) + Data([5])
                            self.send(connection, Data([0, 5, 0, 16]) + prime + peer) {
                                Self.read(connection, 144) { _ in
                                    self.send(connection, Data([0, 0, 0, 0])) {
                                        Self.read(connection, 1) { shared in
                                            XCTAssertEqual(shared, Data([1]))
                                            let initial = Data([0, 1, 0, 1]) + RFBPixelFormat.standardBGRA32.serializedData + Data([0, 0, 0, 2, 81, 65])
                                            self.send(connection, initial) { self.messages(connection, frameSent: false) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        listener.start(queue: queue)
    }
    func stop() {
        listener.cancel()
        lock.lock(); let current = connections; lock.unlock()
        current.forEach { $0.cancel() }
    }
    private func send(_ connection: NWConnection, _ data: Data, then: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in if error == nil { then() } })
    }
    private func messages(_ connection: NWConnection, frameSent: Bool) {
        Self.read(connection, 1) { [weak self] type in
            guard let self else { return }
            switch type.first! {
            case 0: Self.read(connection, 19) { _ in self.messages(connection, frameSent: frameSent) }
            case 2:
                Self.read(connection, 3) { header in
                    let size = (Int(header[1]) << 8 | Int(header[2])) * 4
                    Self.read(connection, size) { _ in self.messages(connection, frameSent: frameSent) }
                }
            case 21:
                Self.read(connection, 7) { body in
                    XCTAssertEqual(body, Data([0, 0, 1, 0, 0, 0, 0]))
                    self.messages(connection, frameSent: frameSent)
                }
            case 11:
                Self.read(connection, 7) { body in
                    XCTAssertEqual(body, Data(repeating: 0, count: 7))
                    let packet = self.response(self.counter.increment())
                    // Status plus a deliberately split archive header/payload.
                    self.send(connection, Data([20, 0, 0, 4, 0, 1, 0, 4]) + packet.prefix(5)) {
                        self.send(connection, Data(packet.dropFirst(5).prefix(11))) {
                            self.send(connection, Data(packet.dropFirst(16))) { self.messages(connection, frameSent: frameSent) }
                        }
                    }
                }
            case 3:
                Self.read(connection, 9) { _ in
                    if frameSent { self.messages(connection, frameSent: true); return }
                    let frame = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, 2, 3, 255])
                    self.send(connection, frame) { self.messages(connection, frameSent: true) }
                }
            case 31:
                Self.read(connection, 15) { header in
                    let plainSize = Int(header[7..<11].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                    let size = Int(header[11..<15].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                    guard size > 0, size <= 2_000_000, plainSize <= 2_000_000 else { XCTFail("Invalid outgoing archive bounds"); return }
                    Self.read(connection, size) { compressed in
                        // Decode with the existing generic inflater, then an
                        // independent fixed one-flavor wire parser, not our
                        // new archive decoder.
                        guard let raw = ZlibDecompressor().decompress(data: compressed, expectedBytes: plainSize),
                              raw.count >= 42,
                              raw.prefix(8) == Data([0, 0, 0, 1, 0, 0, 0, 22]),
                              raw[8..<30] == Data("public.utf8-plain-text".utf8),
                              raw[30..<38] == Data(repeating: 0, count: 8) else { XCTFail("Invalid outgoing archive structure"); return }
                        let textSize = Int(raw[38..<42].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                        guard textSize == raw.count - 42,
                              let text = String(data: Data(raw.dropFirst(42)), encoding: .utf8) else { XCTFail("Invalid outgoing UTF-8"); return }
                        _ = self.uploadCounter.increment()
                        self.lock.lock(); self.uploadSizes.append(size); let observer = self.uploadObserver; self.lock.unlock()
                        observer?(text)
                        self.messages(connection, frameSent: frameSent)
                    }
                }
            default: XCTFail("Unexpected client packet \(type.first!)"); connection.cancel()
            }
        }
    }
    private static func read(_ connection: NWConnection, _ size: Int, partial: Data = Data(), done: @escaping @Sendable (Data) -> Void) {
        if size == 0 { done(Data()); return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: size - partial.count) { data, _, complete, error in
            guard error == nil, let data, !data.isEmpty else { return }
            let result = partial + data
            if result.count == size { done(result) }
            else if !complete { read(connection, size, partial: result, done: done) }
        }
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<end], radix: 16)!); index = end
        }
    }
}
