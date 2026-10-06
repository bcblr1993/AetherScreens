import XCTest
import Network
@testable import AetherScreensCore

final class ZRLETransportTests: XCTestCase {
    func testReconnectFromConnectingNotificationReplacesTheAttempt() throws {
        try verifyReconnectFromState(.connecting)
    }

    func testReconnectFromVersionNotificationDoesNotReadTheNewBannerTwice() throws {
        try verifyReconnectFromState(.negotiatingVersion)
    }

    func testReconnectFromAuthenticationNotificationKeepsNewHandshakeIndependent() throws {
        try verifyReconnectFromState(.authenticating)
    }

    func testReconnectFromInitializationNotificationDoesNotSendOldClientInit() throws {
        try verifyReconnectFromState(.initializing)
    }

    func testReconnectFromConnectedNotificationDoesNotSendAnOldRequestOnNewSocket() throws {
        try verifyReconnectFromState(.connected)
    }

    private func verifyReconnectFromState(_ trigger: RFBClient.State) throws {
        let ready = expectation(description: "State reconnect listener ready")
        let expected = Data(repeating: 51, count: 4 * 2 * 4)
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: expected)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let once = ZRLEReconnectOnce()
        let delivered = expectation(description: "Replacement receives a complete frame")
        let frames = ZRLEFrameCounter()
        client.onStateChanged = { [weak client] state in
            if state == trigger, once.take() { client?.disconnect(); client?.connect() }
            if case .failed(let reason) = state { XCTFail(reason) }
        }
        client.onFrameUpdated = { frames.increment(); delivered.fulfill() }
        client.connect()
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(frames.value, 1)
        // Cancelling the first socket need not flush its pending SetEncodings.
        // Count accepted sockets separately from messages that reached the server.
        XCTAssertEqual(server.connectionCount, trigger == .connecting ? 1 : 2)
        XCTAssertEqual(server.offers.last?.first, RFBConstants.EncodingType.zrle.rawValue)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(expected))
    }

    func testReconnectFromFailureNotificationKeepsTheNewConnectionAlive() throws {
        let ready = expectation(description: "Failure reconnect listener ready")
        let first = ZRLEReconnectOnce()
        let invalid = try ZRLETestDeflater().compress(Data([17]))
        let expected = Data(repeating: 42, count: 4 * 2 * 4)
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            if first.take() {
                return [Self.rectangle(.zrle, x: 0, y: 0, width: 4, height: 2, compressed: invalid)]
            }
            return [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: expected)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let failed = expectation(description: "Malformed first connection rejected")
        let delivered = expectation(description: "Replacement connection survives failure callback")
        client.onStateChanged = { [weak client] state in
            if case .failed(let reason) = state {
                XCTAssertEqual(reason, "Invalid ZRLE pixel data")
                failed.fulfill()
                client?.connect()
            }
        }
        client.onFrameUpdated = { delivered.fulfill() }
        client.connect()
        wait(for: [failed, delivered], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(server.offers.count, 2)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(expected))
    }

    func testReconnectFromReceiveNotificationCannotConsumeOldPayloadOnNewConnection() throws {
        let ready = expectation(description: "Reentrant reconnect fixture ready")
        let image = zrleRawTileFixture(width: 257, height: 257)
        let server = try ZRLEWireServer(width: 257, height: 257, ready: { ready.fulfill() }) {
            [Self.rectangle(.zrle, x: 0, y: 0, width: 257, height: 257,
                            compressed: try ZRLETestDeflater().compress(image.tiles))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let once = ZRLEReconnectOnce()
        let frames = ZRLEFrameCounter()
        let delivered = expectation(description: "Fresh connection frame decoded")
        client.onBytesReceived = { [weak client] count in
            guard let client else { return }
            // Handshake packets are smaller; reconnect during an actual framebuffer receive.
            if count > 100, once.take() { client.disconnect(); client.connect() }
        }
        client.onFrameUpdated = { frames.increment(); delivered.fulfill() }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [delivered], timeout: 5)
        XCTAssertEqual(frames.value, 1)
        XCTAssertEqual(server.offers.count, 2)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(image.pixels), "The new connection must deliver the complete expected framebuffer")
    }

    func testLargeCompressedWireRectangleCrossesReceiveAndInflationChunks() throws {
        let ready = expectation(description: "Large ZRLE fixture ready")
        let image = zrleRawTileFixture(width: 257, height: 257)
        let compressed = try ZRLETestDeflater().compress(image.tiles)
        XCTAssertGreaterThan(compressed.count, 65_536)
        let server = try ZRLEWireServer(width: 257, height: 257, ready: { ready.fulfill() }) {
            [Self.rectangle(.zrle, x: 0, y: 0, width: 257, height: 257, compressed: compressed)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "Large ZRLE received and decoded")
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(image.pixels), "The received framebuffer must match every expected pixel")
    }

    func testNegotiatedZRLEInterleavesWithZlibAndRawAndReconnectsWithFreshDictionary() throws {
        let ready = expectation(description: "ZRLE listener ready")
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            let zrle = try ZRLETestDeflater(), zlib = try ZRLETestDeflater()
            return [
                Self.rectangle(.zrle, x: 0, y: 0, width: 4, height: 2, compressed: try zrle.compress(Data([1, 1, 2, 3]))),
                Self.rectangle(.zlib, x: 0, y: 0, width: 2, height: 1, compressed: try zlib.compress(Data([20, 30, 40, 255, 20, 30, 40, 255]))),
                Self.rectangle(.zrle, x: 1, y: 1, width: 2, height: 1, compressed: try zrle.compress(Data([2, 21, 22, 23, 31, 32, 33, 0x40]))),
                Self.rectangle(.zlib, x: 2, y: 0, width: 1, height: 1, compressed: try zlib.compress(Data([20, 30, 40, 255]))),
                Self.rectangle(.raw, x: 3, y: 0, width: 1, height: 1, payload: Data([61, 62, 63, 255]))
            ]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let expected = [UInt8](arrayLiteral: 20,30,40,255, 20,30,40,255, 20,30,40,255, 61,62,63,255,
                              1,2,3,255, 21,22,23,255, 31,32,33,255, 1,2,3,255)
        for _ in 0..<2 {
            let frames = expectation(description: "Five mixed actual wire rectangles decoded")
            frames.expectedFulfillmentCount = 5
            client.onFrameUpdated = { frames.fulfill() }
            client.connect()
            wait(for: [frames], timeout: 5)
            XCTAssertEqual(client.framebuffer.pixels, expected)
            client.disconnect()
        }
        XCTAssertEqual(server.offers.count, 2)
        for offer in server.offers {
            XCTAssertEqual(offer.first, RFBConstants.EncodingType.zrle.rawValue)
            XCTAssertTrue(offer.contains(RFBConstants.EncodingType.zlib.rawValue))
            XCTAssertTrue(offer.contains(RFBConstants.EncodingType.raw.rawValue))
        }
    }

    func testMalformedZRLEFailsWithoutPublishingOrOverwritingPartialPixels() throws {
        // The first run is valid; the second overruns the remaining pixel.
        // Partial decoding must stay in the temporary buffer, outside the framebuffer.
        let invalid = try ZRLETestDeflater().compress(Data([128, 99, 98, 97, 0, 88, 87, 86, 255, 0]))
        try assertFailurePreservesFramebuffer(Self.rectangle(.zrle, x: 1, y: 1, width: 2, height: 1, compressed: invalid),
                                             expectedReason: "Invalid ZRLE pixel data")
    }

    func testShortZlibPayloadFailsWithoutPublishingOrOverwritingPixels() throws {
        let compressed = try ZRLETestDeflater().compress(Data([1, 2, 3, 255]))
        try assertFailurePreservesFramebuffer(Self.rectangle(.zlib, x: 1, y: 1, width: 2, height: 1, compressed: compressed),
                                             expectedReason: "Invalid Zlib pixel data")
    }

    func testOversizedZlibPayloadFailsWithoutPublishingOrOverwritingPixels() throws {
        let compressed = try ZRLETestDeflater().compress(Data([1, 2, 3, 255, 4, 5, 6, 255]))
        try assertFailurePreservesFramebuffer(Self.rectangle(.zlib, x: 1, y: 1, width: 1, height: 1, compressed: compressed),
                                             expectedReason: "Invalid Zlib pixel data")
    }

    func testOversizedZlibLengthFailsBeforeReadingPayload() throws {
        var packet = Self.rectangle(.zlib, x: 0, y: 0, width: 4, height: 2, payload: Data())
        packet.append(contentsOf: [255, 255, 255, 255])
        try assertFailurePreservesFramebuffer(packet, expectedReason: "Invalid Zlib compressed length")
    }

    func testOutOfBoundsZlibRectangleFailsBeforeReadingLength() throws {
        try assertFailurePreservesFramebuffer(Self.rectangle(.zlib, x: 3, y: 1, width: 2, height: 1, payload: Data()),
                                             expectedReason: "Invalid Zlib rectangle size")
    }

    func testOutOfBoundsRawRectangleFailsBeforeReadingPixels() throws {
        // The server keeps the socket open and supplies no pixel payload.
        // Geometry must fail immediately instead of waiting for eight bytes.
        try assertUnsupportedPacketPreservesFramebuffer(Self.rectangle(.raw, x: 3, y: 1, width: 2, height: 1, payload: Data()),
                                                        expectedReason: "Invalid Raw rectangle size")
    }

    func testOutOfBoundsRawPixelsCannotPublishAClippedFrame() throws {
        try assertUnsupportedPacketPreservesFramebuffer(Self.rectangle(.raw, x: 3, y: 1, width: 2, height: 1,
                                                                         payload: Data([61, 62, 63, 255, 71, 72, 73, 255])),
                                                        expectedReason: "Invalid Raw rectangle size")
    }

    func testRawRectangleAtBottomRightEdgePreservesPixelsAndRequestsNextUpdate() throws {
        let replacement = Data([61, 62, 63, 255, 71, 72, 73, 255])
        try assertRawSequence(Self.rectangle(.raw, x: 2, y: 1, width: 2, height: 1, payload: replacement),
                              replacement: replacement)
    }

    func testZeroAreaRawAtFramebufferBoundaryKeepsTheNextUpdateReadable() throws {
        try assertRawSequence(Self.rectangle(.raw, x: 4, y: 2, width: 0, height: 0, payload: Data()),
                              replacement: nil)
    }

    private func assertRawSequence(_ packet: Data, replacement: Data?) throws {
        let ready = expectation(description: "Raw geometry listener ready")
        let original = Data(Array(repeating: [UInt8(4), 5, 6, 255], count: 8).flatMap { $0 })
        var expected = Array(original)
        if let replacement { expected.replaceSubrange(24..<32, with: replacement) }
        let marker = "raw-geometry-sequence-complete"
        var boundary = Data([RFBConstants.ServerMessageType.serverCutText.rawValue, 0, 0, 0])
        Self.append(UInt32(marker.utf8.count), to: &boundary)
        boundary.append(contentsOf: marker.utf8)
        // Each packet is released only after a complete client update request.
        // Receiving the marker proves the request after the second frame arrived.
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: original), packet, boundary]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let completed = expectation(description: "Raw sequence protocol boundary received")
        completed.assertForOverFulfill = true
        let frames = ZRLEFrameSnapshots()
        let framebuffer = client.framebuffer
        client.onFrameUpdated = {
            let pixels = framebuffer.pixels
            let count = frames.record(pixels)
            XCTAssertLessThanOrEqual(count, 2)
            XCTAssertEqual(pixels, count == 1 ? Array(original) : expected)
        }
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, marker)
            XCTAssertEqual(frames.snapshots, [Array(original), expected])
            completed.fulfill()
        }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(frames.snapshots, [Array(original), expected])
        XCTAssertEqual(client.framebuffer.pixels, expected)
        XCTAssertEqual(client.state, .connected)
    }

    func testUnknownFramebufferEncodingFailsBeforeParsingPayloadAsNextRectangle() throws {
        let unknown = RFBConstants.EncodingType(rawValue: 2_147_483_646)
        let forged = Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2,
                                    payload: Data(repeating: 99, count: 4 * 2 * 4))
        // The unknown body deliberately resembles the next rectangle. Its
        // length is unknown, so skipping only its header loses framing.
        var packet = Self.rectangle(unknown, x: 0, y: 0, width: 4, height: 2,
                                    payload: Data(forged.dropFirst(4)))
        packet[3] = 2
        try assertUnsupportedPacketPreservesFramebuffer(packet,
            expectedReason: "Unsupported framebuffer encoding: \(unknown.rawValue)")
    }

    func testUnknownServerMessageFailsBeforeParsingPayloadAsFramebufferUpdate() throws {
        let unknown: UInt8 = 126
        var packet = Data([unknown])
        // A body with a valid message prefix must not become a new message.
        packet.append(Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2,
                                     payload: Data(repeating: 88, count: 4 * 2 * 4)))
        try assertUnsupportedPacketPreservesFramebuffer(packet,
            expectedReason: "Unsupported server message type: \(unknown)")
    }

    func testSupportedBellAndMixedLosslessFramebufferUpdatesRemainConnected() throws {
        let ready = expectation(description: "Supported message listener ready")
        let original = Data(Array(repeating: [UInt8(4), 5, 6, 255], count: 8).flatMap { $0 })
        var afterZlib = Array(original)
        afterZlib.replaceSubrange(4..<8, with: [UInt8(61), 62, 63, 255])
        var afterCopy = afterZlib
        afterCopy.replaceSubrange(0..<4, with: [UInt8(61), 62, 63, 255])
        var afterZRLE = afterCopy
        afterZRLE.replaceSubrange(16..<20, with: [UInt8(71), 72, 73, 255])
        let expectedSnapshots = [Array(original), afterZlib, afterCopy, afterZRLE]
        let completionMarker = "supported-frame-sequence-complete"
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            var first = Data([RFBConstants.ServerMessageType.bell.rawValue])
            first.append(Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: original))
            // The fixture sends this boundary only after the request following
            // the fourth frame. Its callback never touches a system pasteboard.
            var boundary = Data([RFBConstants.ServerMessageType.serverCutText.rawValue, 0, 0, 0])
            Self.append(UInt32(completionMarker.utf8.count), to: &boundary)
            boundary.append(contentsOf: completionMarker.utf8)
            return [
                first,
                Self.rectangle(.zlib, x: 1, y: 0, width: 1, height: 1,
                               compressed: try ZRLETestDeflater().compress(Data([61, 62, 63, 255]))),
                Self.rectangle(.copyRect, x: 0, y: 0, width: 1, height: 1, payload: Data([0, 1, 0, 0])),
                Self.rectangle(.zrle, x: 0, y: 1, width: 1, height: 1,
                               compressed: try ZRLETestDeflater().compress(Data([1, 71, 72, 73]))),
                boundary
            ]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let delivered = expectation(description: "Final supported pixel update decoded correctly")
        delivered.assertForOverFulfill = true
        let completed = expectation(description: "Supported sequence protocol boundary received")
        completed.assertForOverFulfill = true
        let observations = ZRLEFrameSnapshots()
        let framebuffer = client.framebuffer
        client.onFrameUpdated = {
            let pixels = framebuffer.pixels
            let frame = observations.record(pixels)
            guard frame <= expectedSnapshots.count else {
                XCTFail("Unexpected framebuffer callback after the supported sequence")
                return
            }
            let expected = expectedSnapshots[frame - 1]
            XCTAssertEqual(pixels, expected, "Supported frame \(frame) must have its exact ordered snapshot")
            if frame == expectedSnapshots.count, pixels == expected { delivered.fulfill() }
        }
        client.onClipboardReceived = { marker in
            XCTAssertEqual(marker, completionMarker)
            XCTAssertEqual(observations.snapshots, expectedSnapshots,
                           "Bell and the completion boundary must not publish extra frame callbacks")
            completed.fulfill()
        }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTFail(reason) } }
        client.connect()
        wait(for: [delivered, completed], timeout: 5)
        XCTAssertEqual(observations.snapshots, expectedSnapshots)
        XCTAssertEqual(client.framebuffer.pixels, afterZRLE)
        XCTAssertEqual(client.state, .connected)
        let offer = try XCTUnwrap(server.offers.last)
        for encoding in [RFBConstants.EncodingType.raw, .zlib, .copyRect, .zrle] {
            XCTAssertTrue(offer.contains(encoding.rawValue))
        }
    }

    func testOversizedAnnouncedLengthFailsBeforeReadingPayload() throws {
        var packet = Self.rectangle(.zrle, x: 0, y: 0, width: 4, height: 2, payload: Data())
        packet.append(contentsOf: [255, 255, 255, 255])
        try assertFailurePreservesFramebuffer(packet, expectedReason: "Invalid ZRLE compressed length")
    }

    private func assertUnsupportedPacketPreservesFramebuffer(_ packet: Data, expectedReason: String) throws {
        let ready = expectation(description: "Unsupported packet listener ready")
        let original = Data(Array(repeating: [UInt8(4), 5, 6, 255], count: 8).flatMap { $0 })
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: original), packet]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let first = expectation(description: "Baseline framebuffer received")
        let failed = expectation(description: "Unsupported packet terminates the connection")
        let frames = ZRLEFrameCounter()
        client.onFrameUpdated = {
            frames.increment()
            if frames.value == 1 { first.fulfill() }
        }
        client.onStateChanged = { state in
            if case .failed(let reason) = state {
                XCTAssertEqual(reason, expectedReason)
                failed.fulfill()
            }
        }
        client.connect()
        wait(for: [first, failed], timeout: 5)
        XCTAssertEqual(client.state, .failed(expectedReason))
        XCTAssertEqual(frames.value, 1, "Unsupported payload must never publish a forged framebuffer")
        XCTAssertEqual(client.framebuffer.pixels, Array(original), "Unsupported payload must preserve the last complete framebuffer")
    }

    private func assertFailurePreservesFramebuffer(_ invalid: Data, expectedReason: String) throws {
        let ready = expectation(description: "Failure fixture ready")
        let original = Data(Array(repeating: [UInt8(4), 5, 6, 255], count: 8).flatMap { $0 })
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: original), invalid]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let first = expectation(description: "Valid framebuffer received")
        let failed = expectation(description: "Invalid compressed rectangle rejected")
        let counts = ZRLEFrameCounter()
        client.onFrameUpdated = { counts.increment(); first.fulfill() }
        client.onStateChanged = { if case .failed(let reason) = $0 { XCTAssertEqual(reason, expectedReason); failed.fulfill() } }
        client.connect()
        wait(for: [first, failed], timeout: 5)
        XCTAssertEqual(counts.value, 1)
        XCTAssertEqual(client.framebuffer.pixels, Array(original))
    }

    private static func rectangle(_ encoding: RFBConstants.EncodingType, x: UInt16, y: UInt16, width: UInt16, height: UInt16,
                                  compressed: Data) -> Data {
        var payload = Data()
        append(UInt32(compressed.count), to: &payload)
        payload.append(compressed)
        return rectangle(encoding, x: x, y: y, width: width, height: height, payload: payload)
    }
    private static func rectangle(_ encoding: RFBConstants.EncodingType, x: UInt16, y: UInt16, width: UInt16, height: UInt16,
                                  payload: Data) -> Data {
        var result = Data([0, 0, 0, 1])
        for coordinate in [x, y, width, height] { append(coordinate, to: &result) }
        append(UInt32(bitPattern: encoding.rawValue), to: &result)
        result.append(payload)
        return result
    }
    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }
}

private final class ZRLEReconnectOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}

private final class ZRLEFrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class ZRLEFrameSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [[UInt8]] = []
    func record(_ pixels: [UInt8]) -> Int {
        lock.lock(); defer { lock.unlock() }
        received.append(pixels)
        return received.count
    }
    var snapshots: [[UInt8]] { lock.lock(); defer { lock.unlock() }; return received }
}

/// Reads the client's actual pixel-format/encoding/request messages before sending rectangles.
private final class ZRLEWireServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.zrle-wire-qa")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var receivedOffers: [[Int32]] = []
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return connections.count }
    var offers: [[Int32]] { lock.lock(); defer { lock.unlock() }; return receivedOffers }

    init(width: UInt16 = 4, height: UInt16 = 2, ready: @escaping () -> Void, packets: @escaping () throws -> [Data]) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, let frames = try? packets() else { connection.cancel(); return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue)
            connection.send(content: Data("RFB 003.008\n".utf8), completion: .contentProcessed { [weak self] _ in
                Self.read(connection, count: 12) { _ in
                    connection.send(content: Data([1, 1]), completion: .contentProcessed { _ in
                        Self.read(connection, count: 1) { _ in
                            connection.send(content: Data([0, 0, 0, 0]), completion: .contentProcessed { _ in
                                Self.read(connection, count: 1) { _ in
                                    var initial = Data([UInt8(width >> 8), UInt8(truncatingIfNeeded: width), UInt8(height >> 8), UInt8(truncatingIfNeeded: height)])
                                    initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                                    initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                                    connection.send(content: initial, completion: .contentProcessed { [weak self] _ in
                                        self?.messages(connection, frames: frames, next: 0)
                                    })
                                }
                            })
                        }
                    })
                }
            })
        }
        listener.start(queue: queue)
    }
    func stop() {
        listener.cancel()
        lock.lock(); let current = connections; lock.unlock()
        current.forEach { $0.cancel() }
    }
    private func messages(_ connection: NWConnection, frames: [Data], next: Int) {
        Self.read(connection, count: 1) { [weak self] type in
            guard let self else { return }
            switch type[0] {
            case 0:
                Self.read(connection, count: 19) { [weak self] _ in self?.messages(connection, frames: frames, next: next) }
            case 2:
                Self.read(connection, count: 3) { [weak self] header in
                    let count = Int(header[1]) * 256 + Int(header[2])
                    guard count > 0 else { return }
                    Self.read(connection, count: count * 4) { [weak self] values in
                        guard let self else { return }
                        let offers = stride(from: 0, to: values.count, by: 4).map { offset in
                            Int32(bitPattern: values[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
                        }
                        self.lock.lock(); self.receivedOffers.append(offers); self.lock.unlock()
                        self.messages(connection, frames: frames, next: next)
                    }
                }
            case 3:
                Self.read(connection, count: 9) { [weak self] _ in
                    guard let self else { return }
                    if next < frames.count {
                        connection.send(content: frames[next], completion: .contentProcessed { [weak self] _ in
                            self?.messages(connection, frames: frames, next: next + 1)
                        })
                    } else { self.messages(connection, frames: frames, next: next) }
                }
            default: connection.cancel()
            }
        }
    }
    private static func read(_ connection: NWConnection, count: Int, accumulated: Data = Data(), completion: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { data, _, complete, error in
            guard error == nil, let data, !data.isEmpty else { return }
            var current = accumulated
            current.append(data)
            if current.count == count { completion(current) }
            else if !complete { read(connection, count: count, accumulated: current, completion: completion) }
        }
    }
}
