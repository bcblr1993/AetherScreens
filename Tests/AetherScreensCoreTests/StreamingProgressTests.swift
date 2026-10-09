import XCTest
import Network
@testable import AetherScreensCore

final class StreamingProgressTests: XCTestCase {
    @MainActor
    func testAutomaticCompressionDowngradesAndRecoversAfterActualTCPTransfers() async throws {
        let ready = expectation(description: "Slow quality listener ready")
        let downgraded = expectation(description: "Automatic balanced hint received")
        let recovered = expectation(description: "Automatic high quality restored")
        let allFrames = expectation(description: "All recovery frames decoded")
        downgraded.assertForOverFulfill = false
        var random: UInt32 = 0x12345678
        var rgb = Data()
        let encoder = try ZRLETestDeflater()
        var schedule: [(Data, TimeInterval)] = []
        for index in 0..<19 {
            rgb.removeAll(keepingCapacity: true)
            for _ in 0..<(128 * 64 * 3) {
                random ^= random << 13; random ^= random >> 17; random ^= random << 5
                rgb.append(UInt8(truncatingIfNeeded: random))
            }
            let compressed = try encoder.compress(rgb)
            XCTAssertGreaterThanOrEqual(compressed.count, 16_384)
            var frame = Data([0,0,0,1, 0,0,0,0,0,128,0,64,0,0,0,7, 0])
            frame.append(UInt8(compressed.count & 127) | 128)
            frame.append(UInt8((compressed.count >> 7) & 127) | 128)
            frame.append(UInt8(compressed.count >> 14))
            frame.append(compressed)
            let split = frame.count / 2
            let start = index < 3 ? Double(index) * 0.6 : 6 + Double(index - 3)
            if index < 3 {
                schedule.append((Data(frame.prefix(split)), start))
                schedule.append((Data(frame.dropFirst(split)), start + 0.35))
            } else {
                // A fast server flushes the complete rectangle in one write;
                // only the slow phase deliberately withholds half the payload.
                schedule.append((frame, start))
            }
        }
        let server = try LargeFrameServer(customUpdates: Data(), scheduledChunks: schedule, onEncodingUpdate: { values in
            print("[Adaptive QA quality hints] \(values.filter { (-32 ... -23).contains($0) })")
            if values.contains(-26) {
                XCTAssertEqual(values.first, 7)
                downgraded.fulfill()
            } else if values.contains(-23) {
                XCTAssertEqual(values.first, 7)
                recovered.fulfill()
            }
        }) { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Slow quality QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.requestDisconnect() }
        var frameCount = 0
        let frameHandler = session.client.onFrameUpdated
        session.client.onFrameUpdated = {
            frameHandler?()
            Task { @MainActor in
                frameCount += 1
                if frameCount == 19 { allFrames.fulfill() }
            }
        }
        let sampleHandler = session.client.onPixelTransferSample
        session.client.onPixelTransferSample = { bytes, duration in
            print("[Adaptive QA payload] bytes=\(bytes) duration=\(duration)")
            sampleHandler?(bytes, duration)
        }
        session.selectAutomaticDisplayQuality(true)
        session.startSession()
        await fulfillment(of: [downgraded], timeout: 8)
        await fulfillment(of: [recovered], timeout: 25)
        await fulfillment(of: [allFrames], timeout: 10)
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(session.client.state, .connected)
        XCTAssertTrue(session.hasReceivedFirstFrame)
        let image = try XCTUnwrap(session.client.framebuffer.makeCGImage())
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        for y in 0..<64 {
            for x in 0..<128 {
                let input = (y * 128 + x) * 3, output = (y * 1024 + x) * 4
                XCTAssertEqual(pixels[output], rgb[input + 2])
                XCTAssertEqual(pixels[output + 1], rgb[input + 1])
                XCTAssertEqual(pixels[output + 2], rgb[input])
                XCTAssertEqual(pixels[output + 3], 255)
            }
        }
    }

    func testCompressionQualityChangesOnSameTCPConnectionAndRestoresLossless() throws {
        let ready = expectation(description: "Live quality listener ready")
        let balanced = expectation(description: "Balanced quality received")
        let lossless = expectation(description: "Lossless preference restored")
        let updates = Data([0,0,0,1, 0,0,0,0,0,1,0,1,0,0,0,7, 0x80,255,0,0])
        let server = try LargeFrameServer(customUpdates: updates, onEncodingUpdate: { encodings in
            if encodings.contains(-26) {
                XCTAssertEqual(encodings.first, 7)
                balanced.fulfill()
            } else {
                XCTAssertEqual(encodings.first, 16)
                XCTAssertFalse(encodings.contains(where: { (-32 ... -23).contains($0) }))
                lossless.fulfill()
            }
            XCTAssertTrue(encodings.contains(0))
            XCTAssertTrue(encodings.contains(6))
        }) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "Desktop before quality change")
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        client.setCompressionQuality(jpegQuality: 6)
        wait(for: [balanced], timeout: 3)
        client.setCompressionQuality(jpegQuality: nil)
        wait(for: [lossless], timeout: 3)
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(client.state, .connected)
        let image = try XCTUnwrap(client.framebuffer.makeCGImage())
        let pixels = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertEqual(Data(pixels.prefix(4)), Data([0,0,255,255]))
    }

    func testTightJPEGOverTCPProducesCorrectColor() throws {
        let jpeg = try TightJPEGTests().imageData(type: "public.jpeg")
        XCTAssertLessThan(jpeg.count, 16_384)
        var updates = Data([0,0,0,1, 0,0,0,0,0,4,0,4,0,0,0,7, 0x90])
        updates.append(UInt8(jpeg.count & 127) | 128)
        updates.append(UInt8(jpeg.count >> 7))
        updates.append(jpeg)
        let ready = expectation(description: "JPEG Tight listener ready")
        let server = try LargeFrameServer(customUpdates: updates) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "JPEG Tight decoded")
        let sample = expectation(description: "Completed JPEG payload timing")
        client.onPixelTransferSample = { count, duration in
            XCTAssertEqual(count, jpeg.count)
            XCTAssertGreaterThanOrEqual(duration, 0)
            sample.fulfill()
        }
        frame.assertForOverFulfill = false
        client.onStateChanged = { if case .failed(let message) = $0 { XCTFail(message); frame.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame, sample], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        let image = try XCTUnwrap(client.framebuffer.makeCGImage())
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        for y in 0..<4 {
            for x in 0..<4 {
                let offset = (y * 1024 + x) * 4
                XCTAssertLessThanOrEqual(abs(Int(bytes[offset]) - 10), 5)
                XCTAssertLessThanOrEqual(abs(Int(bytes[offset + 1]) - 20), 5)
                XCTAssertLessThanOrEqual(abs(Int(bytes[offset + 2]) - 240), 5)
                XCTAssertEqual(bytes[offset + 3], 255)
            }
        }
    }

    func testTightTCPRejectsInvalidControlFilterPaletteAndJPEG() throws {
        let cases: [Data] = [Data([0xa0]), Data([0x40,3]), Data([0x40,1,0]), Data([0x90,0]),
                             Data([0x90,3,1,2,3]), Data([0x40,1,2, 255,0,0,0,255,0,0,0,255, 3])]
        for payload in cases {
            let ready = expectation(description: "Malformed Tight listener ready")
            let updates = Data([0,0,0,1, 0,0,0,0,0,1,0,1,0,0,0,7]) + payload
            let server = try LargeFrameServer(customUpdates: updates) { ready.fulfill() }
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
            defer { client.disconnect() }
            let failed = expectation(description: "Malformed Tight rejected")
            failed.assertForOverFulfill = false
            client.onStateChanged = { if case .failed = $0 { failed.fulfill() } }
            client.onFrameUpdated = { XCTFail("Invalid Tight rectangle must not publish pixels") }
            client.connect()
            wait(for: [failed], timeout: 5)
            guard case .failed(let message) = client.state else { XCTFail("Expected failed connection"); continue }
            XCTAssertTrue(message.contains("Tight"))
        }
    }

    func testTightRGB565TCPFillPaletteGradientAndCompressedCopy() throws {
        var updates = Data([0,0,0,4])
        func rectangle(x: UInt8, width: UInt8, payload: Data) -> Data {
            Data([0,x,0,0,0,width,0,1,0,0,0,7]) + payload
        }
        updates.append(rectangle(x: 0, width: 1, payload: Data([0x80,0,248])))
        updates.append(rectangle(x: 1, width: 2, payload: Data([0x40,1,1, 224,7,31,0, 0x40])))
        updates.append(rectangle(x: 3, width: 2, payload: Data([0x40,2, 224,255,32,8])))
        let compressed = try ZRLETestDeflater().compress(Data(Array(repeating: [UInt8(31),0], count: 6).flatMap { $0 }))
        XCTAssertLessThan(compressed.count, 128)
        updates.append(rectangle(x: 5, width: 6, payload: Data([0,UInt8(compressed.count)]) + compressed))
        let ready = expectation(description: "RGB565 Tight listener ready")
        let server = try LargeFrameServer(customUpdates: updates) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                               colorDepth: .rgb565)
        defer { client.disconnect() }
        let frame = expectation(description: "RGB565 Tight decoded")
        frame.assertForOverFulfill = false
        client.onStateChanged = { if case .failed(let message) = $0 { XCTFail(message); frame.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        let image = try XCTUnwrap(client.framebuffer.makeCGImage())
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        var expected = Data([0,0,255,255, 0,255,0,255, 255,0,0,255, 0,255,255,255, 0,0,0,255])
        expected.append(Data(Array(repeating: [UInt8(255),0,0,255], count: 6).flatMap { $0 }))
        XCTAssertEqual(Data(bytes.prefix(expected.count)), expected)
    }

    func testTightTCPPaletteGradientAndPersistentCompressedRectangles() throws {
        let encoder = try ZRLETestDeflater()
        var updates = Data([0,0,0,4])
        func rectangle(x: UInt8, width: UInt8, payload: Data) -> Data {
            Data([0,x,0,0,0,width,0,1,0,0,0,7]) + payload
        }
        updates.append(rectangle(x: 0, width: 2, payload: Data([0x40,1,1, 255,0,0, 0,0,255, 0x40])))
        updates.append(rectangle(x: 2, width: 2, payload: Data([0x40,2, 10,20,30, 1,2,3])))
        for (x, value): (UInt8, UInt8) in [(4,40), (8,50)] {
            let compressed = try encoder.compress(Data(repeating: value, count: 12))
            XCTAssertLessThan(compressed.count, 128)
            updates.append(rectangle(x: x, width: 4, payload: Data([0, UInt8(compressed.count)]) + compressed))
        }
        let ready = expectation(description: "Tight filters listener ready")
        let server = try LargeFrameServer(customUpdates: updates) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "All Tight filters decoded")
        frame.assertForOverFulfill = false
        client.onStateChanged = { if case .failed(let message) = $0 { XCTFail(message); frame.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        let image = try XCTUnwrap(client.framebuffer.makeCGImage())
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        var expected = Data([0,0,255,255, 255,0,0,255, 30,20,10,255, 33,22,11,255])
        expected.append(Data(Array(repeating: [UInt8(40),40,40,255], count: 4).flatMap { $0 }))
        expected.append(Data(Array(repeating: [UInt8(50),50,50,255], count: 4).flatMap { $0 }))
        XCTAssertEqual(Data(bytes.prefix(expected.count)), expected)
    }

    func testTightRectanglesAcrossFragmentedTCPReadsPreservePixels() throws {
        var updates = Data([0,0,0,2])
        // Two rectangles in one update: red fill followed by green raw Tight.
        updates.append(contentsOf: [0,0,0,0,0,1,0,1,0,0,0,7, 0x80,255,0,0])
        updates.append(contentsOf: [0,1,0,0,0,1,0,1,0,0,0,7, 0,0,255,0])
        let ready = expectation(description: "Tight TCP listener ready")
        let server = try LargeFrameServer(customUpdates: updates) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "Tight update decoded")
        frame.assertForOverFulfill = false
        client.onStateChanged = { if case .failed(let message) = $0 { XCTFail(message); frame.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 5)
        XCTAssertEqual(client.state, .connected)
        let image = try XCTUnwrap(client.framebuffer.makeCGImage())
        let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertEqual(Data(bytes.prefix(8)), Data([0,0,255,255, 0,255,0,255]))
    }

    @MainActor
    func testCancellingReauthenticationStopsRetriesUntilManualReconnect() async throws {
        let ready = expectation(description: "Cancelled authentication listener ready")
        let server = try LargeFrameServer(requirePasswordAfterFirst: true) { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Cancel auth QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.requestDisconnect() }
        session.startSession()
        for _ in 0..<100 where !session.hasReceivedFirstFrame {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.hasReceivedFirstFrame)
        guard session.hasReceivedFirstFrame else { return }
        server.dropConnections()
        for _ in 0..<160 where !session.isPromptingPassword {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.isPromptingPassword)
        session.cancelPasswordPrompt()
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertFalse(session.isPromptingPassword)
        XCTAssertFalse(session.isAwaitingAutomaticReconnect)
        XCTAssertEqual(server.connectionCount, 2)
        session.reconnectSession()
        for _ in 0..<100 where !session.isPromptingPassword {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.isPromptingPassword)
        XCTAssertEqual(server.connectionCount, 3)
    }

    @MainActor
    func testAutomaticReconnectWaitsForFreshPasswordWithoutAdditionalSockets() async throws {
        let ready = expectation(description: "Reauthentication listener ready")
        let server = try LargeFrameServer(requirePasswordAfterFirst: true) { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Reauthentication QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.requestDisconnect() }
        session.startSession()
        for _ in 0..<100 where !session.hasReceivedFirstFrame {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.hasReceivedFirstFrame)
        guard session.hasReceivedFirstFrame else { return }
        server.dropConnections()
        for _ in 0..<160 where !session.isPromptingPassword {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.isPromptingPassword)
        XCTAssertFalse(session.isAwaitingAutomaticReconnect)
        XCTAssertEqual(server.connectionCount, 2)
        try await Task.sleep(nanoseconds: 2_200_000_000)
        XCTAssertTrue(session.isPromptingPassword, "Automatic retry must not dismiss the fresh credential prompt")
        XCTAssertEqual(server.connectionCount, 2)
        session.submitPassword("QA-only", rememberInKeychain: false)
        for _ in 0..<160 where !session.hasReceivedFirstFrame || session.sessionState != .connected {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.hasReceivedFirstFrame)
        XCTAssertEqual(session.sessionState, .connected)
        XCTAssertFalse(session.isPromptingPassword)
        XCTAssertEqual(server.connectionCount, 2)
        session.requestDisconnect()
        XCTAssertFalse(session.isPromptingPassword)
    }

    @MainActor
    func testAutomaticReconnectStopsAfterFiveRejectedSockets() async throws {
        let ready = expectation(description: "Bounded retry listener ready")
        let server = try LargeFrameServer(rejectConnectionsAfterFirst: true) { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Retry budget QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.requestDisconnect() }
        session.startSession()
        for _ in 0..<100 where !session.hasReceivedFirstFrame {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(session.hasReceivedFirstFrame)
        guard session.hasReceivedFirstFrame else { return }
        server.dropConnections()
        for _ in 0..<840 where server.connectionCount < 6 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(server.connectionCount, 6, "One established socket plus exactly five retries")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(server.connectionCount, 6, "Exhausted budget must not open a seventh socket")
        XCTAssertNotEqual(session.sessionState, .connected)
    }

    @MainActor
    func testPendingAutomaticReconnectStopsWhenClosedOrHidden() async throws {
        for close in [true, false] {
            let ready = expectation(description: "Cancel listener ready")
            let server = try LargeFrameServer { ready.fulfill() }
            defer { server.stop() }
            await fulfillment(of: [ready], timeout: 3)
            let session = SessionViewModel(device: RemoteDevice(name: "Cancel reconnect QA", host: "127.0.0.1",
                port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
            defer { session.requestDisconnect() }
            session.startSession()
            for _ in 0..<100 where !session.hasReceivedFirstFrame {
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            XCTAssertTrue(session.hasReceivedFirstFrame)
            server.dropConnections()
            for _ in 0..<100 where session.sessionState == .connected {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertNotEqual(session.sessionState, .connected)
            XCTAssertTrue(session.isAwaitingAutomaticReconnect)
            if close { session.requestDisconnect() }
            else { session.setForegroundSession(false) }
            XCTAssertFalse(session.isAwaitingAutomaticReconnect)
            try await Task.sleep(nanoseconds: 1_300_000_000)
            XCTAssertEqual(server.connectionCount, 1, "A pending reconnect must stop before opening another socket")
            if !close {
                session.setForegroundSession(true)
                for _ in 0..<160 where server.connectionCount < 2 || !session.hasReceivedFirstFrame {
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                XCTAssertEqual(server.connectionCount, 2)
                XCTAssertTrue(session.hasReceivedFirstFrame)
            }
        }
    }

    @MainActor
    func testSessionAutomaticallyReconnectsAfterActualSocketLoss() async throws {
        let ready = expectation(description: "Reconnect listener ready")
        let server = try LargeFrameServer { ready.fulfill() }
        defer { server.stop() }
        await fulfillment(of: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Reconnect QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.requestDisconnect() }
        session.startSession()
        func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
            for _ in 0..<200 {
                if predicate() { return true }
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            return predicate()
        }
        let first = await waitUntil { session.hasReceivedFirstFrame }
        XCTAssertTrue(first)
        guard first else { return }
        session.zoomScale = 2.5
        session.viewOffset = CGSize(width: 20, height: 30)
        session.cycleCmd()
        session.trackpadEngine.beginDrag()
        let input = session.inputGeneration
        server.dropConnections()
        let recovered = await waitUntil { server.connectionCount >= 2 && session.hasReceivedFirstFrame && session.sessionState == .connected }
        XCTAssertTrue(recovered, "Must establish a new TCP socket and receive a fresh desktop without manual reconnect")
        XCTAssertFalse(session.isAwaitingAutomaticReconnect)
        XCTAssertNotEqual(session.inputGeneration, input)
        XCTAssertFalse(session.isCmdActive)
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        XCTAssertEqual(session.zoomScale, 2.5)
        XCTAssertEqual(session.viewOffset, CGSize(width: 20, height: 30))
        session.requestDisconnect()
        let count = server.connectionCount
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(server.connectionCount, count, "Explicit close must not reconnect")
    }

    func testOrdinaryPixelProgressSurvivesInitialDeadline() throws {
        let ready = expectation(description: "Listener ready")
        let server = try LargeFrameServer(delayedPixelProgress: true) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let frame = expectation(description: "Slow ordinary frame decoded after 20 seconds")
        frame.assertForOverFulfill = false
        client.onStateChanged = { if case .failed(let message) = $0 { XCTFail(message); frame.fulfill() } }
        client.onFrameUpdated = { frame.fulfill() }
        client.connect()
        wait(for: [frame], timeout: 28)
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(client.framebuffer.width, 1024)
    }

    func testClosedRemotePortReportsServiceGuidance() throws {
        let ready = expectation(description: "Port allocated")
        let closed = expectation(description: "Listener stopped")
        let listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .cancelled = state { closed.fulfill() }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: DispatchQueue(label: "qa.closed-port"))
        wait(for: [ready], timeout: 3)
        let port = try XCTUnwrap(listener.port).rawValue
        listener.cancel()
        wait(for: [closed], timeout: 3)
        let failed = expectation(description: "Refused connection explained")
        let client = RFBClient(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if case .failed(let message) = state {
                XCTAssertTrue(message.contains("remote port refused"))
                XCTAssertTrue(message.contains("Screen Sharing"))
                failed.fulfill()
            }
        }
        client.connect()
        wait(for: [failed], timeout: 5)
    }

    func testInitializedServerWithoutPixelsFailsInsteadOfLoadingForever() throws {
        let ready = expectation(description: "Listener ready")
        let server = try LargeFrameServer(sendPixels: false) { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let failed = expectation(description: "Missing first image is actionable")
        client.onStateChanged = { state in
            if case .failed(let message) = state {
                XCTAssertTrue(message.contains("no desktop image arrived"))
                failed.fulfill()
            }
        }
        client.connect()
        wait(for: [failed], timeout: 25)
    }

    func testOnlyFirstFramebufferDownloadReportsProgressAndReconnectRestartsIt() throws {
        let ready = expectation(description: "Listener ready")
        let server = try LargeFrameServer { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        for _ in 0..<2 {
            let frames = expectation(description: "Two actual large frames decoded")
            frames.expectedFulfillmentCount = 2
            let observations = FrameProgressObservations()
            client.onDownloadProgress = { _, _ in observations.progress() }
            client.onFrameUpdated = { observations.frame(); frames.fulfill() }
            client.connect()
            wait(for: [frames], timeout: 5)
            let counts = observations.counts
            XCTAssertEqual(counts.count, 2)
            XCTAssertGreaterThan(counts.first ?? 0, 0, "Initial loading must still show progress, including after reconnect")
            XCTAssertEqual(counts.last, 0, "Subsequent decoded frames must not enqueue loading UI work")
            XCTAssertEqual(client.framebuffer.width, 1024)
            client.disconnect()
        }
    }
}

private final class FrameProgressObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var completed: [Int] = []
    func progress() { lock.lock(); pending += 1; lock.unlock() }
    func frame() { lock.lock(); completed.append(pending); pending = 0; lock.unlock() }
    var counts: [Int] { lock.lock(); defer { lock.unlock() }; return completed }
}

/// Sends real 4 MiB raw frames after an RFB handshake, without client hooks.
private final class LargeFrameServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.large-frame-qa")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    init(sendPixels: Bool = true, delayedPixelProgress: Bool = false, rejectConnectionsAfterFirst: Bool = false,
         requirePasswordAfterFirst: Bool = false, customUpdates: Data? = nil,
         scheduledChunks: [(Data, TimeInterval)]? = nil,
         onEncodingUpdate: (@Sendable ([Int32]) -> Void)? = nil, ready: @escaping () -> Void) throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        listener = try NWListener(using: NWParameters(tls: nil, tcp: tcpOptions), on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock(); self.connections.append(connection)
            let shouldReject = rejectConnectionsAfterFirst && self.connections.count > 1
            let needsPassword = requirePasswordAfterFirst && self.connections.count > 1
            self.lock.unlock()
            connection.start(queue: self.queue)
            if shouldReject { connection.cancel(); return }
            connection.send(content: Data("RFB 003.008\n".utf8), completion: .contentProcessed { _ in
                Self.read(connection, count: 12) {
                    connection.send(content: Data([1, needsPassword ? 2 : 1]), completion: .contentProcessed { _ in
                        Self.read(connection, count: 1) {
                            let finishAuthentication: @Sendable () -> Void = {
                            connection.send(content: Data([0, 0, 0, 0]), completion: .contentProcessed { _ in
                                Self.read(connection, count: 1) {
                                    var initial = Data([4, 0, 4, 0])
                                    initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                                    initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                                    connection.send(content: initial, completion: .contentProcessed { _ in
                                        // Announce the initial display layout before any visible pixels.
                                        var frames = Data([0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 4, 0, 255, 255, 254, 204,
                                                           1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0])
                                        for _ in 0..<(sendPixels ? 2 : 0) {
                                            frames.append(contentsOf: [0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0])
                                            frames.append(Data(repeating: 42, count: 1024 * 1024 * 4))
                                        }
                                        if let customUpdates {
                                            Self.readData(connection, count: 20) { format in
                                                XCTAssertEqual(format.first, 0, "SetPixelFormat must precede encoding negotiation")
                                                Self.readData(connection, count: 4) { header in
                                                    guard header.count == 4, header[0] == 2 else { XCTFail("Missing SetEncodings"); return }
                                                    let count = Int(header[2]) << 8 | Int(header[3])
                                                    guard count > 0, count <= 64 else { XCTFail("Invalid encoding count"); return }
                                                    Self.readData(connection, count: count * 4) { body in
                                                        let encodings = stride(from: 0, to: body.count, by: 4).map { offset in
                                                            body.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                                                        }
                                                        XCTAssertTrue(encodings.contains(7), "Tight must be advertised before server selects it")
                                                        XCTAssertTrue(encodings.contains(16), "Retain ZRLE fallback")
                                                        XCTAssertTrue(encodings.contains(6), "Retain Zlib fallback")
                                                        XCTAssertTrue(encodings.contains(0), "Retain Raw fallback")
                                                        if let scheduledChunks {
                                                            for (chunk, delay) in scheduledChunks {
                                                                self.queue.asyncAfter(deadline: .now() + delay) {
                                                                    connection.send(content: chunk, completion: .contentProcessed { _ in })
                                                                }
                                                            }
                                                        } else {
                                                            connection.send(content: Data(customUpdates.prefix(17)), completion: .contentProcessed { _ in })
                                                            self.queue.asyncAfter(deadline: .now() + 0.02) {
                                                                connection.send(content: Data(customUpdates.dropFirst(17)), completion: .contentProcessed { _ in })
                                                            }
                                                        }
                                                        if let onEncodingUpdate {
                                                            Self.readClientCommands(connection, encodings: onEncodingUpdate)
                                                        }
                                                    }
                                                }
                                            }
                                        } else if delayedPixelProgress {
                                            // Actual pixel bytes arrive before the initial 20s deadline;
                                            // the complete image arrives afterwards. Metadata alone must
                                            // not renew the deadline.
                                            let first = Data(frames.prefix(64))
                                            let rest = Data(frames.dropFirst(64))
                                            self.queue.asyncAfter(deadline: .now() + 15) {
                                                connection.send(content: first, completion: .contentProcessed { _ in })
                                            }
                                            self.queue.asyncAfter(deadline: .now() + 22) {
                                                connection.send(content: rest, completion: .contentProcessed { _ in })
                                            }
                                        } else {
                                            connection.send(content: frames, completion: .contentProcessed { _ in })
                                        }
                                    })
                                }
                            })
                            }
                            if needsPassword {
                                let challenge = Data(repeating: 42, count: 16)
                                connection.send(content: challenge, completion: .contentProcessed { _ in
                                    connection.receive(minimumIncompleteLength: 16, maximumLength: 16) { data, _, _, error in
                                        guard error == nil, data == VNCAuthCrypto.encryptChallenge(challenge, password: "QA-only") else {
                                            connection.cancel(); return
                                        }
                                        finishAuthentication()
                                    }
                                })
                            } else { finishAuthentication() }
                        }
                    })
                }
            })
        }
        listener.start(queue: queue)
    }
    private static func read(_ connection: NWConnection, count: Int, done: @escaping @Sendable () -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, data?.count == count else { return }
            done()
        }
    }
    private static func readData(_ connection: NWConnection, count: Int, done: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, let data, data.count == count else { XCTFail("Incomplete client negotiation"); return }
            done(data)
        }
    }
    private static func readClientCommands(_ connection: NWConnection, encodings: @escaping @Sendable ([Int32]) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, _, error in
            guard error == nil, let type = data?.first else { return }
            switch type {
            case 5:
                readData(connection, count: 5) { _ in readClientCommands(connection, encodings: encodings) }
            case 3:
                readData(connection, count: 9) { _ in readClientCommands(connection, encodings: encodings) }
            case 2:
                readData(connection, count: 3) { header in
                    let count = Int(header[1]) << 8 | Int(header[2])
                    guard count > 0, count <= 64 else { XCTFail("Invalid updated encoding count"); return }
                    readData(connection, count: count * 4) { body in
                        let values = stride(from: 0, to: body.count, by: 4).map { offset in
                            body.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: Int32.self).bigEndian }
                        }
                        encodings(values)
                        readClientCommands(connection, encodings: encodings)
                    }
                }
            default: XCTFail("Unexpected client message in quality fixture: \(type)")
            }
        }
    }
    func stop() {
        lock.lock(); let active = connections; lock.unlock()
        active.forEach { $0.cancel() }; listener.cancel()
    }
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return connections.count }
    func dropConnections() {
        lock.lock(); let active = connections; lock.unlock()
        active.forEach { $0.cancel() }
    }
}
