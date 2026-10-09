import XCTest
import Network
@testable import AetherScreensCore

final class ZRLETransportTests: XCTestCase {
    func testUnvalidatedNativeLayoutAndInvalidLengthPreserveDesktop() throws {
        try assertFailurePreservesFramebuffer(Self.rectangle(.appleDisplayLayout,
            x: 0, y: 0, width: 0, height: 0, payload: Data([0, 4, 0, 5, 255, 255])),
            expectedReason: "Native display layout geometry is not yet validated")
        try assertFailurePreservesFramebuffer(Self.rectangle(.appleDisplayLayout,
            x: 0, y: 0, width: 0, height: 0, payload: Data([0, 1, 0])),
            expectedReason: "Invalid native display layout length")
    }

    func testDesktopSizeAnnouncementDoesNotPublishPixelsOrClearSameSizedDesktop() throws {
        let ready = expectation(description: "Size-only listener")
        let layout = expectation(description: "Size announcement delivered")
        let frames = ZRLEFrameCounter(), requests = ZRLEFrameCounter()
        let completed = expectation(description: "Size-only update completed with a full retry")
        let server = try ZRLEWireServer(ready: { ready.fulfill() }, onUpdateRequest: { incremental in
            requests.increment()
            XCTAssertFalse(incremental)
            if requests.value == 2 { completed.fulfill() }
        }) {
            [Self.rectangle(.desktopSize, x: 0, y: 0, width: 4, height: 2, payload: Data())]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let buffer = Framebuffer()
        buffer.resize(newWidth: 4, newHeight: 2)
        buffer.updateRect(x: 0, y: 0, width: 4, height: 2, rawData: Data(repeating: 51, count: 32))
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, framebuffer: buffer)
        defer { client.disconnect() }
        // ServerInit legitimately resets the initial buffer, so seed only after
        // session setup, before the asynchronous rectangle arrives.
        client.onStateChanged = { state in
            if state == .connected { buffer.updateRect(x: 0, y: 0, width: 4, height: 2, rawData: Data(repeating: 51, count: 32)) }
        }
        client.onFrameUpdated = { frames.increment() }
        client.onDisplayLayoutReceived = { _ in layout.fulfill() }
        client.connect(); wait(for: [layout, completed], timeout: 5)
        XCTAssertEqual(frames.value, 0)
        XCTAssertTrue(buffer.pixels.elementsEqual(Data(repeating: 51, count: 32)))
    }

    func testUnknownEncodingFailsBeforeOpaqueBodyCanOverwriteDesktop() throws {
        try assertFailurePreservesFramebuffer(Self.rectangle(.init(rawValue: 0x12345678),
            x: 0, y: 0, width: 0, height: 0, payload: Data(repeating: 0, count: 32)),
            expectedReason: "Unsupported framebuffer encoding 305419896")
    }

    func testModernAppleCursorBootstrapNeedsBothOptInsAndAppleBanner() throws {
        for (banner, cursor, modern, enabled) in [("RFB 003.889\n", true, true, true), ("RFB 003.889\n", false, true, false),
            ("RFB 003.889\n", true, false, false), ("RFB 003.008\n", true, true, false)] {
            let ready = expectation(description: "Modern cursor bootstrap listener")
            let server = try ZRLEWireServer(banner: banner, ready: { ready.fulfill() }, onVersion: { reply in
                XCTAssertEqual(reply, Data((enabled ? "RFB 003.889\n" : "RFB 003.008\n").utf8))
            }, onClientInit: { flag in XCTAssertEqual(flag, enabled ? 0xc1 : 1) }) {
                [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
            }
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                decodeQueue: DispatchQueue(label: "test.cursor.modern"), experimentalAppleCursor: cursor,
                experimentalAppleModernBootstrap: modern)
            defer { client.disconnect() }
            let frame = expectation(description: "Modern/legacy desktop arrives")
            client.onFrameUpdated = { frame.fulfill() }
            client.connect(); wait(for: [frame], timeout: 5)
            XCTAssertEqual(client.state, .connected)
        }
    }

    func testExperimentalAppleCursorNegotiationNeedsExplicitOptInAndAppleBanner() throws {
        for (banner, enabled, offered) in [("RFB 003.889\n", false, false), ("RFB 003.008\n", true, false), ("RFB 003.889\n", true, true)] {
            let ready = expectation(description: "Cursor negotiation listener")
            let arms = ZRLEFrameCounter(), viewers = ZRLEFrameCounter()
            let server = try ZRLEWireServer(banner: banner, ready: { ready.fulfill() }, onViewerInfo: { packet in
                viewers.increment()
                XCTAssertEqual(packet.count, 66)
                XCTAssertEqual(packet.prefix(10), Data([0x21,0,0,62,0,1,0,0,0,2]))
            }, onAutoUpdate: { packet in
                arms.increment()
                XCTAssertEqual(Data([9]) + packet, AppleFramebufferControl.arm(width: 4, height: 2))
            }) {
                [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
            }
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                decodeQueue: DispatchQueue(label: "test.cursor.negotiation"), experimentalAppleCursor: enabled)
            defer { client.disconnect() }
            let frame = expectation(description: "Desktop still received")
            client.onFrameUpdated = { frame.fulfill() }
            client.connect()
            wait(for: [frame], timeout: 5)
            XCTAssertEqual(server.offers.last?.contains(RFBConstants.EncodingType.appleCursor.rawValue), offered)
            XCTAssertFalse(server.offers.last?.contains(RFBConstants.EncodingType.appleDisplayLayout.rawValue) == true)
            XCTAssertEqual(server.offers.last?.contains(RFBConstants.EncodingType.cursor.rawValue), !offered)
            XCTAssertEqual(arms.value, offered ? 1 : 0)
            XCTAssertEqual(viewers.value, offered ? 1 : 0)
            XCTAssertEqual(client.state, .connected)
        }
    }

    func testAppleCursorStoreSelectUnknownAndPixelsStayAlignedWithoutAdvertising() throws {
        let ready = expectation(description: "Apple cursor listener ready")
        let shape = expectation(description: "STORE and known SELECT")
        shape.expectedFulfillmentCount = 2
        let frame = expectation(description: "Only actual desktop pixels publish")
        let store = try Self.appleCursorPayload(id: 7, plain: Data([10,20,30,0, 30,40,50,0, 255,128]))
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.appleCursor, x: 1, y: 0, width: 2, height: 1, payload: store),
             Self.rectangle(.appleCursor, x: 0, y: 0, width: 0, height: 0, payload: Self.appleCursorSelect(8)),
             Self.rectangle(.appleCursor, x: 0, y: 0, width: 0, height: 0, payload: Self.appleCursorSelect(7)),
             Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.onCursorReceived = { cursor in
            XCTAssertEqual(cursor.hotspotX, 1)
            XCTAssertEqual(cursor.pixels, Data([10,20,30,255, 15,20,25,128]))
            shape.fulfill()
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [shape, frame], timeout: 5)
        XCTAssertFalse(server.offers.last?.contains(RFBConstants.EncodingType.appleCursor.rawValue) == true)
        XCTAssertEqual(client.state, .connected)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(Data(repeating: 51, count: 32)))
    }

    func testAppleCursorCallbackReconnectCannotReusePreviousSessionCache() throws {
        let ready = expectation(description: "Apple cache reconnect listener ready")
        let store = try Self.appleCursorPayload(id: 7, plain: Data([1,2,3,0,255]))
        let once = ZRLEReconnectOnce()
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            once.take()
                ? [Self.rectangle(.appleCursor, x: 0, y: 0, width: 1, height: 1, payload: store)]
                : [Self.rectangle(.appleCursor, x: 0, y: 0, width: 0, height: 0, payload: Self.appleCursorSelect(7)),
                   Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let shapes = ZRLEFrameCounter()
        client.onCursorReceived = { [weak client] _ in
            shapes.increment()
            if shapes.value == 1 { client?.disconnect(); client?.connect() }
        }
        let frame = expectation(description: "Replacement desktop arrives despite cache miss")
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(shapes.value, 1)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(client.state, .connected)
    }

    func testAppleCursorOversizeLengthFailsBeforeReadingBody() throws {
        var prefix = Data(); Self.append(UInt32(7), to: &prefix)
        Self.append(UInt32(AppleCursorCache.maximumCompressedBytes + 1), to: &prefix)
        try assertFailurePreservesFramebuffer(Self.rectangle(.appleCursor, x: 0, y: 0, width: 1, height: 1, payload: prefix),
            expectedReason: "Invalid Apple cursor length")
    }

    func testAppleCursorDamagedStoreDoesNotOverwriteDesktop() throws {
        var prefix = Data(); Self.append(UInt32(7), to: &prefix); Self.append(UInt32(3), to: &prefix)
        prefix.append(contentsOf: [1,2,3])
        try assertFailurePreservesFramebuffer(Self.rectangle(.appleCursor, x: 0, y: 0, width: 1, height: 1, payload: prefix),
            expectedReason: "Invalid Apple cursor data")
    }

    private static func appleCursorPayload(id: UInt32, plain: Data) throws -> Data {
        let compressed = try ZRLETestDeflater().compress(plain)
        var result = Data(); append(id, to: &result); append(UInt32(compressed.count), to: &result)
        result.append(compressed); return result
    }
    private static func appleCursorSelect(_ id: UInt32) -> Data {
        var result = Data(); append(id, to: &result); append(UInt32(0), to: &result); return result
    }

    func testRichCursorBothDepthsThenHidePreserveFrameAlignmentAndFrameCount() throws {
        for depth in [RFBColorDepth.fullColor, .rgb565] {
            let ready = expectation(description: "Rich cursor listener ready")
            let shapes = expectation(description: "Visible shape followed by explicit hide")
            shapes.expectedFulfillmentCount = 2
            let frame = expectation(description: "Only actual pixels publish a frame")
            let pixels = Data((0..<8).flatMap { _ in [UInt8(0), 0, 255, 255] })
            let raw = depth == .fullColor ? pixels : Data((0..<8).flatMap { _ in [UInt8(0), 248] })
            let cursor = depth == .fullColor ? Data([0,0,255,0, 0,255,0,0, 255,0,0,0, 0xe0]) : Data([0,248,224,7,31,0,0xe0])
            let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
                [Self.rectangle(.cursor, x: 1, y: 0, width: 3, height: 1, payload: cursor),
                 Self.rectangle(.cursor, x: 0, y: 0, width: 0, height: 0, payload: Data()),
                 Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: raw)]
            }
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, colorDepth: depth)
            defer { client.disconnect() }
            let count = ZRLEFrameCounter()
            client.onCursorReceived = { shape in
                if !shape.isHidden {
                    XCTAssertEqual(shape.hotspotX, 1)
                    XCTAssertEqual(shape.pixels, Data([0,0,255,255, 0,255,0,255, 255,0,0,255]))
                }
                shapes.fulfill()
            }
            client.onFrameUpdated = { count.increment(); frame.fulfill() }
            client.connect()
            wait(for: [shapes, frame], timeout: 5)
            XCTAssertTrue(server.offers.last?.contains(RFBConstants.EncodingType.cursor.rawValue) == true)
            XCTAssertEqual(count.value, 1)
            XCTAssertTrue(client.framebuffer.pixels.elementsEqual(pixels))
            XCTAssertEqual(client.state, .connected)
        }
    }

    func testCursorOnlyReplyKeepsRequestFullUntilDesktopPixelsArrive() throws {
        let ready = expectation(description: "Initial cursor listener ready")
        let requests = expectation(description: "Full fetch, full retry, then incremental")
        requests.expectedFulfillmentCount = 3
        let count = ZRLEFrameCounter()
        let server = try ZRLEWireServer(ready: { ready.fulfill() }, onUpdateRequest: { incremental in
            count.increment()
            XCTAssertEqual(incremental, count.value >= 3)
            requests.fulfill()
        }) {
            [Self.rectangle(.cursor, x: 0, y: 0, width: 1, height: 1, payload: Data([1,2,3,0,0x80])),
             Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        client.connect()
        wait(for: [requests], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(Data(repeating: 51, count: 32)))
    }

    func testRichCursorCallbackReconnectCannotConsumeReplacementFrame() throws {
        let ready = expectation(description: "Cursor reconnect listener ready")
        let server = try ZRLEWireServer(ready: { ready.fulfill() }) {
            [Self.rectangle(.cursor, x: 0, y: 0, width: 1, height: 1, payload: Data([1,2,3,0,0x80])),
             Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let once = ZRLEReconnectOnce()
        let frame = expectation(description: "Replacement frame survives cursor callback reconnect")
        client.onCursorReceived = { [weak client] _ in if once.take() { client?.disconnect(); client?.connect() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(Data(repeating: 51, count: 32)))
    }
    func testCursorWorkerDoesNotBlockPointerAndReconnectDiscardsPendingShape() throws {
        let ready = expectation(description: "Cursor worker listener ready")
        let pointer = expectation(description: "Pointer delivered while shape worker held")
        let first = ZRLEReconnectOnce()
        let server = try ZRLEWireServer(ready: { ready.fulfill() }, onPointer: { _ in pointer.fulfill() }) {
            first.take()
                ? [Self.rectangle(.cursor, x: 0, y: 0, width: 1, height: 1, payload: Data([1,2,3,0,0x80]))]
                : [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: Data(repeating: 51, count: 32))]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let worker = DispatchQueue(label: "test.cursor.held-worker")
        let release = DispatchSemaphore(value: 0)
        let held = expectation(description: "Worker held")
        worker.async { held.fulfill(); release.wait() }
        defer { release.signal() }
        wait(for: [held], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, decodeQueue: worker)
        defer { client.disconnect() }
        let bytes = ZRLEByteCounter(), once = ZRLEReconnectOnce()
        client.onBytesReceived = { [weak client] count in
            // Banner/security/ServerInit (44 bytes) plus a 21-byte cursor update.
            if bytes.add(count) >= 65, once.take() {
                client?.sendPointerEvent(buttonMask: [], x: 1, y: 1)
            }
        }
        let stale = expectation(description: "Cancelled cursor never reaches replacement session")
        stale.isInverted = true
        client.onCursorReceived = { _ in stale.fulfill() }
        let connected = expectation(description: "Reconnect progresses independently of worker")
        client.onStateChanged = { state in
            if state == .connected && server.connectionCount == 2 { connected.fulfill() }
        }
        let frame = expectation(description: "Replacement frame")
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [pointer], timeout: 5)
        client.disconnect(); client.connect()
        wait(for: [connected], timeout: 5)
        release.signal()
        wait(for: [frame], timeout: 5)
        wait(for: [stale], timeout: 0.2)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(Data(repeating: 51, count: 32)))
    }

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

    func testRGB565NegotiationHalvesRawPixelsWithoutChangingCoordinates() throws {
        let expected = Data([0,0,255,255, 0,255,0,255, 255,0,0,255, 255,255,255,255] +
                            [0,0,255,255, 0,255,0,255, 255,0,0,255, 255,255,255,255])
        let reduced = Data([0,248,224,7,31,0,255,255, 0,248,224,7,31,0,255,255])
        for (depth, wire, bits) in [(RFBColorDepth.fullColor, expected, UInt8(32)), (.rgb565, reduced, UInt8(16))] {
            let ready = expectation(description: "Color-depth listener ready")
            let frame = expectation(description: "Actual negotiated raw frame decoded")
            let pointer = expectation(description: "Coordinates preserved on wire")
            let server = try ZRLEWireServer(ready: { ready.fulfill() }, onPixelFormat: { format in
                XCTAssertEqual(format.bitsPerPixel, bits)
                XCTAssertEqual(format.bigEndianFlag, 0)
                XCTAssertEqual(format.redShift, bits == 16 ? 11 : 16)
                XCTAssertEqual(format.greenMax, bits == 16 ? 63 : 255)
            }, onPointerCoordinates: { x, y in
                XCTAssertEqual(x, 3); XCTAssertEqual(y, 1); pointer.fulfill()
            }) {
                [Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: wire)]
            }
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
            XCTAssertTrue(client.configureColorDepth(depth))
            defer { client.disconnect() }
            let bytes = ZRLEByteCounter()
            client.onBytesReceived = { _ = bytes.add($0) }
            client.onFrameUpdated = { frame.fulfill() }
            client.connect()
            wait(for: [frame], timeout: 5)
            XCTAssertFalse(client.configureColorDepth(depth == .fullColor ? .rgb565 : .fullColor), "An active socket must retain its negotiated format")
            XCTAssertEqual(client.colorDepth, depth)
            XCTAssertEqual(client.framebuffer.width, 4); XCTAssertEqual(client.framebuffer.height, 2)
            XCTAssertTrue(client.framebuffer.pixels.elementsEqual(expected))
            XCTAssertEqual(bytes.add(0), wire.count + 60, "Actual server bytes must match the smaller wire representation")
            client.sendPointerEvent(buttonMask: .left, x: 3, y: 1)
            wait(for: [pointer], timeout: 3)
        }
    }

    func testRGB565InterleavesZRLEZlibRawAndReconnects() throws {
        let ready = expectation(description: "RGB565 mixed stream ready")
        let red = Data([0, 0, 255, 255])
        let expectedRed = Data((0..<8).flatMap { _ in Array(red) })
        let expectedBlue = Data((0..<8).flatMap { _ in [UInt8(255),0,0,255] })
        let blueWire = Data((0..<8).flatMap { _ in [UInt8(31),0] })
        let server = try ZRLEWireServer(ready: { ready.fulfill() }, onPixelFormat: { format in
            XCTAssertEqual(format.bitsPerPixel, 16)
        }) {
            let zrle = try ZRLETestDeflater(), zlib = try ZRLETestDeflater()
            return [Self.rectangle(.zrle, x: 0, y: 0, width: 4, height: 2, compressed: try zrle.compress(Data([1,0,248]))),
                    Self.rectangle(.zlib, x: 0, y: 0, width: 4, height: 2, compressed: try zlib.compress(blueWire)),
                    Self.rectangle(.raw, x: 0, y: 0, width: 4, height: 2, payload: blueWire)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, colorDepth: .rgb565)
        defer { client.disconnect() }
        for _ in 0..<2 {
            let frames = expectation(description: "Three reduced-color actual frames")
            frames.expectedFulfillmentCount = 3
            let count = ZRLEFrameCounter()
            client.onFrameUpdated = {
                count.increment()
                XCTAssertTrue(client.framebuffer.pixels.elementsEqual(count.value == 1 ? expectedRed : expectedBlue))
                frames.fulfill()
            }
            client.connect()
            wait(for: [frames], timeout: 5)
            XCTAssertEqual(count.value, 3)
            client.disconnect()
        }
    }

    func testReconnectWhileLargeDecodeIsPendingCannotPublishOldPixels() throws {
        let ready = expectation(description: "Decode reconnect listener ready")
        let image = zrleRawTileFixture(width: 2048, height: 2048)
        let compressed = try ZRLETestDeflater().compress(image.tiles)
        let replacementPixels = Data(repeating: 51, count: 2048 * 2048 * 4)
        let firstSocket = ZRLEReconnectOnce()
        let server = try ZRLEWireServer(width: 2048, height: 2048, ready: { ready.fulfill() }) {
            firstSocket.take()
                ? [Self.rectangle(.zrle, x: 0, y: 0, width: 2048, height: 2048, compressed: compressed)]
                : [Self.rectangle(.raw, x: 0, y: 0, width: 2048, height: 2048, payload: replacementPixels)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let decodeQueue = DispatchQueue(label: "test.zrle.held-worker")
        let releaseWorker = DispatchSemaphore(value: 0)
        let workerHeld = expectation(description: "Decode worker held")
        decodeQueue.async { workerHeld.fulfill(); releaseWorker.wait() }
        defer { releaseWorker.signal() }
        wait(for: [workerHeld], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, decodeQueue: decodeQueue)
        defer { client.disconnect() }
        let bytes = ZRLEByteCounter(), once = ZRLEReconnectOnce(), frames = ZRLEFrameCounter()
        let replacementConnected = expectation(description: "Replacement socket connected with worker held")
        client.onStateChanged = { state in
            if state == .connected && server.connectionCount == 2 { replacementConnected.fulfill() }
        }
        let delivered = expectation(description: "Replacement raw frame delivered")
        let stale = expectation(description: "Old decode publishes after replacement")
        stale.isInverted = true
        client.onBytesReceived = { [weak client] count in
            if bytes.add(count) >= compressed.count + 64, once.take() {
                DispatchQueue.main.async {
                    client?.disconnect(); client?.connect()
                }
            }
        }
        client.onFrameUpdated = {
            frames.increment()
            if frames.value == 1 { delivered.fulfill() } else { stale.fulfill() }
        }
        client.connect()
        wait(for: [replacementConnected], timeout: 10)
        XCTAssertEqual(frames.value, 0)
        releaseWorker.signal()
        wait(for: [delivered], timeout: 10)
        wait(for: [stale], timeout: 2)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(frames.value, 1)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(replacementPixels))
    }

    func testWheelDeliveryDoesNotWaitForLargeRectangleDecode() throws {
        let ready = expectation(description: "Large interactive fixture ready")
        let frame = expectation(description: "Large image decoded")
        let wheel = expectation(description: "Wheel reaches actual TCP server before image completion")
        let image = zrleRawTileFixture(width: 2048, height: 2048)
        let compressed = try ZRLETestDeflater().compress(image.tiles)
        let frames = ZRLEFrameCounter()
        let server = try ZRLEWireServer(width: 2048, height: 2048, ready: { ready.fulfill() }, onPointer: { mask in
            if mask & RFBConstants.ButtonMask.scrollDown.rawValue != 0 {
                XCTAssertEqual(frames.value, 0, "Input must not wait for compressed image decoding")
                wheel.fulfill()
            }
        }) {
            [Self.rectangle(.zrle, x: 0, y: 0, width: 2048, height: 2048, compressed: compressed)]
        }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let decodeQueue = DispatchQueue(label: "test.zrle.held-worker")
        let releaseWorker = DispatchSemaphore(value: 0)
        let workerHeld = expectation(description: "Decode worker held")
        decodeQueue.async { workerHeld.fulfill(); releaseWorker.wait() }
        defer { releaseWorker.signal() }
        wait(for: [workerHeld], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, decodeQueue: decodeQueue)
        defer { client.disconnect() }
        let bytes = ZRLEByteCounter(), once = ZRLEReconnectOnce()
        client.onBytesReceived = { [weak client] count in
            // 44 handshake bytes and 20 framebuffer/rectangle/length bytes.
            if bytes.add(count) >= compressed.count + 64, once.take() {
                DispatchQueue.global(qos: .userInteractive).async {
                    client?.sendPointerEvent(buttonMask: .scrollDown, x: 20, y: 20)
                }
            }
        }
        client.onFrameUpdated = { frames.increment(); frame.fulfill() }
        client.connect()
        wait(for: [wheel], timeout: 10)
        XCTAssertEqual(frames.value, 0)
        releaseWorker.signal()
        wait(for: [frame], timeout: 10)
        XCTAssertTrue(client.framebuffer.pixels.elementsEqual(image.pixels))
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
        let timing = expectation(description: "Standard ZRLE numeric timing")
        client.onZRLETiming = { bytes, wait, decode in
            XCTAssertEqual(bytes, compressed.count)
            XCTAssertTrue(wait.isFinite && wait >= 0)
            XCTAssertTrue(decode.isFinite && decode >= 0)
            timing.fulfill()
        }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [timing, frame], timeout: 5)
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

    func testOversizedAnnouncedLengthFailsBeforeReadingPayload() throws {
        var packet = Self.rectangle(.zrle, x: 0, y: 0, width: 4, height: 2, payload: Data())
        packet.append(contentsOf: [255, 255, 255, 255])
        try assertFailurePreservesFramebuffer(packet, expectedReason: "Invalid ZRLE compressed length")
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

private final class ZRLEByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ value: Int) -> Int { lock.lock(); defer { lock.unlock() }; count += value; return count }
}

private final class ZRLEFrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Reads the client's actual pixel-format/encoding/request messages before sending rectangles.
private final class ZRLEWireServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.zrle-wire-qa")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var receivedOffers: [[Int32]] = []
    private let onUpdateRequest: (@Sendable (Bool) -> Void)?
    private let onVersion: (@Sendable (Data) -> Void)?
    private let onClientInit: (@Sendable (UInt8) -> Void)?
    private let onViewerInfo: (@Sendable (Data) -> Void)?
    private let onAutoUpdate: (@Sendable (Data) -> Void)?
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return connections.count }
    var offers: [[Int32]] { lock.lock(); defer { lock.unlock() }; return receivedOffers }

    private let onPixelFormat: (@Sendable (RFBPixelFormat) -> Void)?
    private let onPointerCoordinates: (@Sendable (UInt16, UInt16) -> Void)?
    private let onPointer: (@Sendable (UInt8) -> Void)?
    init(width: UInt16 = 4, height: UInt16 = 2, banner: String = "RFB 003.008\n", ready: @escaping () -> Void, onUpdateRequest: (@Sendable (Bool) -> Void)? = nil, onVersion: (@Sendable (Data) -> Void)? = nil, onClientInit: (@Sendable (UInt8) -> Void)? = nil, onViewerInfo: (@Sendable (Data) -> Void)? = nil, onAutoUpdate: (@Sendable (Data) -> Void)? = nil, onPointer: (@Sendable (UInt8) -> Void)? = nil, onPixelFormat: (@Sendable (RFBPixelFormat) -> Void)? = nil, onPointerCoordinates: (@Sendable (UInt16, UInt16) -> Void)? = nil, packets: @escaping () throws -> [Data]) throws {
        self.onVersion = onVersion
        self.onClientInit = onClientInit
        self.onViewerInfo = onViewerInfo
        self.onAutoUpdate = onAutoUpdate
        self.onUpdateRequest = onUpdateRequest
        self.onPointer = onPointer
        self.onPixelFormat = onPixelFormat
        self.onPointerCoordinates = onPointerCoordinates
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, let frames = try? packets() else { connection.cancel(); return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue)
            connection.send(content: Data(banner.utf8), completion: .contentProcessed { [weak self] _ in
                Self.read(connection, count: 12) { data in
                    self?.onVersion?(data)
                    connection.send(content: Data([1, 1]), completion: .contentProcessed { _ in
                        Self.read(connection, count: 1) { _ in
                            connection.send(content: Data([0, 0, 0, 0]), completion: .contentProcessed { _ in
                                Self.read(connection, count: 1) { data in
                                    self?.onClientInit?(data[0])
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
                Self.read(connection, count: 19) { [weak self] data in
                    if let format = RFBPixelFormat.parse(from: Data(data.suffix(16))) { self?.onPixelFormat?(format) }
                    self?.messages(connection, frames: frames, next: next)
                }
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
                Self.read(connection, count: 9) { [weak self] data in
                    guard let self else { return }
                    self.onUpdateRequest?(data[0] != 0)
                    if next < frames.count {
                        connection.send(content: frames[next], completion: .contentProcessed { [weak self] _ in
                            self?.messages(connection, frames: frames, next: next + 1)
                        })
                    } else { self.messages(connection, frames: frames, next: next) }
                }
            case 0x21:
                Self.read(connection, count: 3) { [weak self] prefix in
                    let size = Int(prefix[1]) << 8 | Int(prefix[2])
                    Self.read(connection, count: size) { [weak self] payload in
                        self?.onViewerInfo?(Data([0x21]) + prefix + payload)
                        self?.messages(connection, frames: frames, next: next)
                    }
                }
            case 9:
                Self.read(connection, count: 15) { [weak self] data in
                    self?.onAutoUpdate?(data)
                    self?.messages(connection, frames: frames, next: next)
                }
            case 5:
                Self.read(connection, count: 5) { [weak self] packet in
                    self?.onPointer?(packet[0])
                    self?.onPointerCoordinates?(UInt16(packet[1]) << 8 | UInt16(packet[2]), UInt16(packet[3]) << 8 | UInt16(packet[4]))
                    self?.messages(connection, frames: frames, next: next)
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
