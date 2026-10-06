import XCTest
import Testing
import Network
import zlib
#if canImport(AppKit)
import AppKit
#endif
@testable import AetherScreensCore

final class PointerTransportTests: XCTestCase {
    func testAppleClickAndReturnProduceNewRemotePixelsAfterInitialFrame() throws {
        for behavior in [PointerWireServer.FramebufferBehavior.pushAndPoll, .pollOnly] {
            let ready = expectation(description: "Modeled Apple desktop ready")
            let server = try PointerWireServer(banner: "RFB 003.889\n", framebufferBehavior: behavior,
                                               ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                                   automaticClipboard: false, automaticFramebufferUpdates: true)
            defer { client.disconnect() }
            func pixel() -> UInt8 {
                var result: UInt8 = 0
                client.framebuffer.withPixelBytes { bytes, _, _ in result = bytes[0] }
                return result
            }
            client.connect()
            waitUntil { pixel() == 1 && server.automaticFrameRequests.count == 1 }
            client.sendPointerEvent(buttonMask: .left, x: 1, y: 1)
            client.sendPointerEvent(buttonMask: [], x: 1, y: 1)
            waitUntil { server.pointers.count == 2 }
            waitUntil { pixel() == 2 }
            client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
            client.sendKeyEvent(down: false, keySym: MacKeyMap.return)
            waitUntil { server.keys.count == 2 }
            waitUntil { pixel() == 3 }
            XCTAssertEqual(client.state, .connected)
        }
    }

    func testAppleAutomaticFramesRetainPollingRearmResizeReconnectAndStandardFallback() throws {
        for (banner, desired, active) in [("RFB 003.889\n", true, true),
                                         ("RFB 003.008\n", true, false),
                                         ("RFB 003.889\n", false, false)] {
            let ready = expectation(description: "Automatic frame fixture ready")
            let server = try PointerWireServer(banner: banner, ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                                   automaticClipboard: false, automaticFramebufferUpdates: desired)
            defer { client.disconnect() }
            client.connect()
            waitUntil { server.updateRequests.count == 1 }
            XCTAssertEqual(client.usesAutomaticFramebufferUpdates, active)
            if active {
                waitUntil { server.automaticFrameRequests.count == 1 }
                XCTAssertEqual(server.automaticFrameRequests.first,
                               Data([9, 0, 0, 1, 0, 0, 65, 27, 0, 0, 0, 0, 0, 16, 0, 16]))
            }
            client.setInputEnabled(false)
            let frames = expectation(description: "Two unsolicited frames arrive during Observe")
            frames.expectedFulfillmentCount = 2
            client.onFrameUpdated = { frames.fulfill() }
            let packet = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 80, 120, 200, 255])
            let parsed = expectation(description: "Following clipboard proves both updates were fully consumed")
            client.onClipboardReceived = { if $0 == "frame barrier" { parsed.fulfill() } }
            server.sendRaw(packet + packet)
            server.sendClipboard("frame barrier")
            wait(for: [frames, parsed], timeout: 3)
            client.onFrameUpdated = nil
            client.onClipboardReceived = nil
            client.setInputEnabled(true)
            client.sendKeyEvent(down: true, keySym: 65)
            waitUntil { server.keys.count == 1 }
            waitUntil { server.updateRequests.count == (active ? 2 : 3) }
            XCTAssertEqual(server.updateRequests.last?.prefix(2), Data([3, 1]),
                           "Apple push must keep a coalesced incremental request for a still screen")
            XCTAssertEqual(server.automaticFrameRequests.count, active ? 1 : 0)
            if active {
                server.sendRaw(Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 8, 0, 12, 255, 255, 255, 33]))
                waitUntil { server.automaticFrameRequests.count == 2 && server.updateRequests.contains(Data([3, 0, 0, 0, 0, 0, 0, 8, 0, 12])) }
                XCTAssertEqual(server.automaticFrameRequests.last,
                               Data([9, 0, 0, 1, 0, 0, 65, 27, 0, 0, 0, 0, 0, 8, 0, 12]))
                server.sendRaw(Data([0x1F, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1]))
                waitUntil { if case .failed = client.state { return true }; return false }
                XCTAssertFalse(client.usesAutomaticFramebufferUpdates, "A failed transport must not report active streaming")
                client.disconnect()
                client.connect()
                waitUntil { server.automaticFrameRequests.count == 3 && server.updateRequests.last == Data([3, 0, 0, 0, 0, 0, 0, 16, 0, 16]) }
                XCTAssertEqual(server.automaticFrameRequests.last,
                               Data([9, 0, 0, 1, 0, 0, 65, 27, 0, 0, 0, 0, 0, 16, 0, 16]))
                XCTAssertTrue(client.usesAutomaticFramebufferUpdates)
            }
        }
    }

    func testAppleEmptyRepliesHaveBoundedPollingAndDisconnectCancelsPendingWork() throws {
        let ready = expectation(description: "Empty frame desktop ready")
        let server = try PointerWireServer(banner: "RFB 003.889\n", framebufferBehavior: .empty,
                                           ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                               automaticClipboard: false, automaticFramebufferUpdates: true)
        defer { client.disconnect() }
        client.connect()
        waitUntil { server.updateRequests.count >= 3 }
        let beginning = server.updateRequests.count
        let observation = expectation(description: "Bounded polling observation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { observation.fulfill() }
        wait(for: [observation], timeout: 2)
        XCTAssertGreaterThan(server.updateRequests.count, beginning)
        XCTAssertLessThanOrEqual(server.updateRequests.count - beginning, 10,
                                 "An immediate empty reply must not create an unbounded request loop")
        client.disconnect()
        XCTAssertFalse(client.usesAutomaticFramebufferUpdates)
        let settled = expectation(description: "Old socket settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let stoppedCount = server.updateRequests.count
        let stopped = expectation(description: "No old refresh after disconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { stopped.fulfill() }
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(server.updateRequests.count, stoppedCount)
    }

    func testAppleObserveReceivesChangedRemotePixelsWithoutSendingInput() throws {
        let ready = expectation(description: "Observe desktop ready")
        let server = try PointerWireServer(banner: "RFB 003.889\n", framebufferBehavior: .pollOnly,
                                           ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                               automaticClipboard: false, automaticFramebufferUpdates: true)
        defer { client.disconnect() }
        client.setInputEnabled(false)
        client.connect()
        waitUntil { server.updateRequests.count == 2 }
        client.sendPointerEvent(buttonMask: .left, x: 1, y: 1)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        server.changeDesktop()
        waitUntil {
            var pixel: UInt8 = 0
            client.framebuffer.withPixelBytes { bytes, _, _ in pixel = bytes[0] }
            return pixel == 2
        }
        XCTAssertTrue(server.pointers.isEmpty)
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertEqual(client.state, .connected)
    }

    func testAppleFrameObserverReconnectDoesNotReadOrRefreshReplacementSocketTwice() throws {
        let ready = expectation(description: "Reconnect desktop ready")
        let server = try PointerWireServer(banner: "RFB 003.889\n", framebufferBehavior: .pollOnly,
                                           ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                               automaticClipboard: false, automaticFramebufferUpdates: true)
        defer { client.disconnect() }
        let reconnectedFrame = expectation(description: "Replacement initial frame")
        let first = RefreshReconnectFlag()
        client.onFrameUpdated = {
            if first.take() { client.disconnect(); client.connect() }
            else { reconnectedFrame.fulfill() }
        }
        client.connect()
        wait(for: [reconnectedFrame], timeout: 3)
        client.onFrameUpdated = nil
        waitUntil { server.updateRequests.count == 3 && server.automaticFrameRequests.count == 2 }
        XCTAssertEqual(server.updateRequests.map { $0[1] }, [0, 0, 1],
                       "Only the replacement initial frame may schedule its incremental request")
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.return)
        waitUntil {
            var pixel: UInt8 = 0
            client.framebuffer.withPixelBytes { bytes, _, _ in pixel = bytes[0] }
            return pixel == 2
        }
        XCTAssertEqual(client.state, .connected)
    }

    func testAppleClipboardUsesModernWirePacketAndObserveBlocksUpload() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        waitUntil { server.appleRequests >= 2 }
        XCTAssertEqual(server.viewerInfos.count, 1)
        XCTAssertEqual(server.viewerInfos.first?.count, 66)
        let uploaded = expectation(description: "Modern Apple archive received on TCP")
        server.onAppleClipboard = { packet in
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeText(Data(packet.dropFirst(16)), uncompressedBytes: size), "双向🙂𠮷")
            uploaded.fulfill()
        }
        XCTAssertTrue(client.sendCutText("双向🙂𠮷"))
        wait(for: [uploaded], timeout: 2)
        client.setInputEnabled(false)
        XCTAssertFalse(client.sendCutText("Observe must block upload"))
        XCTAssertEqual(client.queueClipboardAndPaste("Rejected paste"), .rejected)
        client.setInputEnabled(true)
        client.sendKeyEvent(down: true, keySym: 65)
        waitUntil { server.keys.count == 1 }
        XCTAssertEqual(server.keys.first?.key, 65, "The archive must not desynchronize the next key message")
        server.onAppleClipboard = nil
    }

    func testAppleFragmentedClipboardAndStatusKeepMessageStreamAligned() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        waitUntil { server.appleRequests >= 2 }
        let received = expectation(description: "Fragmented Apple clipboard then legacy barrier")
        received.expectedFulfillmentCount = 2
        client.onClipboardReceived = { text in
            XCTAssertTrue(["分片🙂𠮷", "barrier"].contains(text))
            received.fulfill()
        }
        let packet = try XCTUnwrap(ApplePasteboard.encodeText("分片🙂𠮷"))
        server.sendFragmented(packet)
        server.sendRaw(Data([0x14, 0, 0, 4, 0, 1, 0, 2]))
        server.sendClipboard("barrier")
        wait(for: [received], timeout: 3)
        waitUntil { server.appleRequests >= 3 }
        XCTAssertEqual(client.state, .connected)
        client.onClipboardReceived = nil
    }

    func testTypedAppleClipboardBinaryTCPDeliveryUploadAndObserveGate() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        waitUntil { server.appleRequests >= 2 }
        let items: [RFBClipboardFlavor] = [
            .init(type: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0, 255])),
            .init(type: "public.url", data: Data("https://example.com/中文".utf8),
                  aliases: [.init(name: "public.mime-type", data: Data("text/uri-list".utf8))])
        ]
        let received = expectation(description: "Fragmented binary flavors delivered intact")
        let barrier = expectation(description: "Legacy text after binary archive")
        client.onClipboardFlavorsReceived = { actual in
            XCTAssertEqual(actual, items)
            received.fulfill()
        }
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "barrier", "Binary data must not be coerced into text")
            barrier.fulfill()
        }
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeItems(items)))
        server.sendClipboard("barrier")
        wait(for: [received, barrier], timeout: 3)
        let uploaded = expectation(description: "Typed clipboard upload over TCP")
        server.onAppleClipboard = { packet in
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeItems(Data(packet.dropFirst(16)), uncompressedBytes: size), items)
            uploaded.fulfill()
        }
        XCTAssertTrue(client.sendClipboardFlavors(items))
        wait(for: [uploaded], timeout: 3)
        server.onAppleClipboard = { _ in XCTFail("Observe must not upload typed data") }
        client.setInputEnabled(false)
        XCTAssertFalse(client.sendClipboardFlavors(items))
        client.setInputEnabled(true)
        client.sendKeyEvent(down: true, keySym: 65)
        waitUntil { server.keys.count == 1 }
        XCTAssertEqual(client.state, .connected)
        client.onClipboardFlavorsReceived = nil
        client.onClipboardReceived = nil
        server.onAppleClipboard = nil
    }

    func testAppleMonitoringOffManualFetchAndReconnectPreserveWirePolicy() throws {
        let ready = expectation(description: "Off monitoring listener")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, automaticClipboard: false)
        defer { client.disconnect() }
        let connected = expectation(description: "Off monitoring connected")
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        client.sendKeyEvent(down: true, keySym: 65)
        waitUntil { server.keys.count == 1 }
        XCTAssertTrue(server.appleMonitorSelectors.isEmpty)
        XCTAssertEqual(server.appleFetches, 0)
        XCTAssertTrue(client.requestRemoteClipboard())
        waitUntil { server.appleFetches == 1 }
        XCTAssertTrue(server.appleMonitorSelectors.isEmpty, "Manual Get cannot subscribe")
        client.setAutomaticClipboardMonitoring(true)
        waitUntil { server.appleMonitorSelectors == [1] }
        client.setAutomaticClipboardMonitoring(false)
        client.setAutomaticClipboardMonitoring(false)
        waitUntil { server.appleMonitorSelectors == [1, 2] }
        let barrier = expectation(description: "Status processed while monitoring off")
        client.onClipboardReceived = { text in XCTAssertEqual(text, "barrier"); barrier.fulfill() }
        server.sendRaw(Data([0x14, 0, 0, 4, 0, 1, 0, 2]))
        server.sendClipboard("barrier")
        wait(for: [barrier], timeout: 3)
        XCTAssertEqual(server.appleFetches, 1, "Late status must not fetch after stop")
        client.onClipboardReceived = nil
        client.disconnect()
        let reconnected = expectation(description: "Off policy survives reconnect")
        client.onStateChanged = { if $0 == .connected { reconnected.fulfill() } }
        client.connect()
        wait(for: [reconnected], timeout: 3)
        client.sendKeyEvent(down: true, keySym: 66)
        waitUntil { server.keys.contains { $0.key == 66 } }
        XCTAssertEqual(server.appleMonitorSelectors, [1, 2])
        XCTAssertEqual(server.appleFetches, 1)
        XCTAssertTrue(client.requestRemoteClipboard())
        waitUntil { server.appleFetches == 2 }
        XCTAssertEqual(server.appleMonitorSelectors, [1, 2])
    }

    func testAppleReconnectRegistersViewerAndMonitoringAgain() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        waitUntil { server.appleRequests >= 2 }
        client.disconnect()
        let connected = expectation(description: "Apple clipboard reconnect ready")
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        waitUntil { server.appleRequests >= 4 }
        XCTAssertEqual(server.viewerInfos.count, 2)
        let received = expectation(description: "Reconnected Apple clipboard receives updates")
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "reconnected🙂")
            received.fulfill()
        }
        server.sendRaw(Data([0x14, 0, 0, 4, 0, 1, 0, 2]))
        waitUntil { server.appleRequests >= 5 }
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeText("reconnected🙂")))
        wait(for: [received], timeout: 3)
        client.onClipboardReceived = nil
        client.onStateChanged = nil
    }

    func testMalformedAppleArchiveAndPromiseCannotOverwriteClipboard() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        let barrier = expectation(description: "Valid message after ignored Apple payloads")
        client.onClipboardReceived = { text in
            XCTAssertEqual(text, "barrier")
            barrier.fulfill()
        }
        var malformed = try XCTUnwrap(ApplePasteboard.encodeText("malformed"))
        malformed[11] &+= 1 // Uncompressed length does not match the archive.
        server.sendRaw(malformed)
        var promised = try XCTUnwrap(ApplePasteboard.encodeText("metadata only"))
        promised[2] = 1
        server.sendRaw(promised)
        server.sendClipboard("barrier")
        wait(for: [barrier], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        client.onClipboardReceived = nil
    }

    func testOversizedAppleArchiveFailsBeforeReceivingPayload() throws {
        let (server, client) = try connectedPair(banner: "RFB 003.889\n")
        defer { client.disconnect(); server.stop() }
        let rejected = expectation(description: "Oversized archive rejected from header")
        client.onStateChanged = { if case .failed = $0 { rejected.fulfill() } }
        client.onClipboardReceived = { _ in XCTFail("Oversized archive cannot reach the clipboard") }
        server.sendRaw(Data([0x1F, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1]))
        wait(for: [rejected], timeout: 3)
        client.onStateChanged = nil
        client.onClipboardReceived = nil
    }

    func testStandardServerReceivesFullUnicodeScalars() throws {
        try assertUnicodeWire(banner: "RFB 003.008\n", expected: [0x01004E2D, 0x0101F642, 0x01020BB7, 65])
    }

    func testAppleServerReceivesCompleteUTF16Pairs() throws {
        try assertUnicodeWire(banner: "RFB 003.889\n", expected: [0x01004E2D, 0x0100D83D, 0x0100DE42, 0x0100D842, 0x0100DFB7, 65])
    }

    private func assertUnicodeWire(banner: String, expected: [UInt32]) throws {
        let (server, client) = try connectedPair(banner: banner)
        defer { client.disconnect(); server.stop() }
        client.sendText("中🙂𠮷A")
        waitUntil { server.keys.count >= expected.count * 2 }
        XCTAssertEqual(server.keys.map(\.key), expected.flatMap { [$0, $0] })
        XCTAssertEqual(server.keys.map(\.down), expected.flatMap { _ in [true, false] })
        client.setInputEnabled(false)
        client.sendText("🙂𠮷")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(server.keys.count, expected.count * 2, "Observe must suppress every surrogate unit")
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
    func testApplicationBackgroundReleasesHeldInputAndCancelsWheelBacklog() throws {
        let ready = expectation(description: "Application lifecycle listener ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let suite = "test.aetherscreens.application-release.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let session = TestSession.make(device: RemoteDevice(name: "Application lifecycle QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue, sharedClipboard: false), password: nil,
            isTemporary: true, deviceStore: store, keyboardStore: KeyboardToolbarStore(defaults: defaults))
        defer { session.endSession() }
        session.setApplicationInputActive(true)
        session.startSession()
        waitUntil { session.sessionState == .connected && session.client.state == .connected }
        session.isKeyboardVisible = true
        var repeatSettings = HardwareKeyboardConfiguration()
        repeatSettings.repeatDelay = 0.2
        repeatSettings.repeatInterval = 0.05
        session.keyboardConfiguration.hardwareKeyboard = repeatSettings
        session.cycleCmd()
        session.cycleCmd()
        session.cycleOption()
        session.cycleControl()
        session.cycleShift()
        // The toolbar and physical keyboard own the same remote Cmd key.
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        session.handleHardwareKey(down: true, keySym: 98)
        // Also cover a transport-held key outside the view model's key mapping.
        session.client.sendKeyEvent(down: true, keySym: 99)
        session.beginToolbarKeyHold(MacKeyMap.arrowLeft)
        waitUntil { server.keys.contains { $0.key == MacKeyMap.arrowLeft && $0.down } }
        session.trackpadEngine.remoteWidth = 16
        session.trackpadEngine.remoteHeight = 16
        session.trackpadEngine.moveCursor(to: CGPoint(x: 9, y: 10))
        session.trackpadEngine.beginDrag()
        for _ in 0..<300 {
            session.client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: 9, y: 10)
        }
        // These positioning packets prove that the old wheel work reserved slots.
        waitUntil { server.pointers.filter { $0.mask == 1 }.count >= 301 }
        let pointerBoundary = server.pointers.count
        let generation = session.inputGeneration
        session.sendKeyTap(97)
        session.setApplicationInputActive(false)
        XCTAssertNotEqual(session.inputGeneration, generation)
        XCTAssertFalse(session.canSendDictation)
        XCTAssertEqual(session.cmdState, .inactive)
        XCTAssertEqual(session.optState, .inactive)
        XCTAssertEqual(session.ctrlState, .inactive)
        XCTAssertEqual(session.shiftState, .inactive)
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        let heldKeys: Set<UInt32> = [MacKeyMap.commandLeft, MacKeyMap.optionLeft,
            MacKeyMap.controlLeft, MacKeyMap.shiftLeft, MacKeyMap.arrowLeft, 97, 98, 99]
        waitUntil {
            Set(server.keys.filter { !$0.down }.map(\.key)) == heldKeys &&
            server.pointers.dropFirst(pointerBoundary).contains { $0.mask == 0 && $0.x == 9 && $0.y == 10 }
        }
        XCTAssertEqual(server.keys.filter { !$0.down }.count, heldKeys.count,
                       "Each aggregate held key must be released once, including shared Cmd owners")
        let released = try XCTUnwrap(server.pointers.enumerated().dropFirst(pointerBoundary)
            .first { $0.element.mask == 0 && $0.element.x == 9 && $0.element.y == 10 }?.offset)
        session.setApplicationInputActive(true)
        XCTAssertTrue(session.canSendDictation)
        // A distinct key received after the release is a TCP ordering barrier.
        session.client.sendKeyEvent(down: true, keySym: 122)
        session.client.sendKeyEvent(down: false, keySym: 122)
        waitUntil { server.keys.suffix(2).map(\.key) == [122, 122] && server.keys.last?.down == false }
        let settledKeyCount = server.keys.count
        let staleWheel = expectation(description: "Cancelled application-background wheel reaches TCP")
        staleWheel.isInverted = true
        let staleKey = expectation(description: "Cancelled toolbar repeat or delayed tap reaches TCP")
        staleKey.isInverted = true
        let freshWheel = expectation(description: "New scroll bypasses cancelled background backlog")
        server.onPointer = { pointer in
            if pointer.mask & RFBConstants.ButtonMask.scrollDown.rawValue != 0 { staleWheel.fulfill() }
            if pointer.mask == RFBConstants.ButtonMask.scrollUp.rawValue { freshWheel.fulfill() }
        }
        server.onKey = { key in if heldKeys.contains(key.key) { staleKey.fulfill() } }
        session.client.sendPointerEvent(buttonMask: .scrollUp, x: 12, y: 13)
        wait(for: [freshWheel, staleWheel, staleKey], timeout: 0.3)
        XCTAssertEqual(server.keys.count, settledKeyCount)
        XCTAssertTrue(server.pointers.dropFirst(released + 1).allSatisfy {
            $0.mask & RFBConstants.ButtonMask.scrollDown.rawValue == 0
        }, "No old wheel may follow the actual release, even when control resumes immediately")
        XCTAssertEqual(session.cmdState, .inactive, "Foreground must not restore a stale sticky key")
    }

    @MainActor
    func testApplicationInputResumeRequiresSelectedControlSession() throws {
        for mode in ["control", "observe", "hidden", "pan"] {
            let ready = expectation(description: "Application gate listener ready")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let suite = "test.aetherscreens.application-gate.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = TestStorage.make(userDefaults: defaults, legacySources: [])
            let session = TestSession.make(device: RemoteDevice(name: "Application input gate QA", host: "127.0.0.1",
                port: try XCTUnwrap(server.listener.port).rawValue, sharedClipboard: false), password: nil,
                isTemporary: true, deviceStore: store, keyboardStore: KeyboardToolbarStore(defaults: defaults))
            defer { session.endSession() }
            session.setApplicationInputActive(true)
            session.startSession()
            waitUntil { session.sessionState == .connected && session.client.state == .connected }
            session.setApplicationInputActive(false)
            // Changing either existing flag must not reopen application input.
            session.isObserveOnly = true
            session.isObserveOnly = false
            session.setForegroundSession(false)
            session.setForegroundSession(true)
            session.isPanningViewport = true
            session.isPanningViewport = false
            @MainActor func attemptSuppressedInput() {
                session.cycleCmd(); session.cycleOption(); session.cycleControl(); session.cycleShift()
                session.handleHardwareKey(down: true, keySym: 120)
                session.client.sendKeyEvent(down: true, keySym: 121)
                session.sendKeyTap(122)
                session.sendTextString("blocked")
                session.executeShortcut(.spotlight)
                session.handleThreeFingerSwipe(.left)
                session.triggerHotCorner(.bottomRight)
                session.trackpadEngine.handleTap()
                session.sendNativePointer(buttonMask: .left, x: 5, y: 6)
                session.client.sendPointerEvent(buttonMask: .scrollDown, x: 5, y: 6)
                session.isKeyboardVisible = true
                session.beginToolbarKeyHold(MacKeyMap.return)
                session.endToolbarKeyHold(MacKeyMap.return, activate: true)
                session.textInputBuffer = "blocked"
                XCTAssertFalse(session.submitTextInput(pressReturn: true))
            }
            XCTAssertFalse(session.canSendDictation)
            XCTAssertFalse(session.canTriggerHotCorner)
            attemptSuppressedInput()
            let backgroundSettled = expectation(description: "Background remains closed after flag changes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { backgroundSettled.fulfill() }
            wait(for: [backgroundSettled], timeout: 2)
            XCTAssertTrue(server.keys.isEmpty, mode)
            XCTAssertTrue(server.pointers.isEmpty, mode)
            XCTAssertEqual(session.cmdState, .inactive, mode)
            XCTAssertEqual(session.optState, .inactive, mode)
            XCTAssertEqual(session.ctrlState, .inactive, mode)
            XCTAssertEqual(session.shiftState, .inactive, mode)
            if mode == "observe" { session.isObserveOnly = true }
            if mode == "hidden" { session.setForegroundSession(false) }
            if mode == "pan" { session.isPanningViewport = true }
            session.setApplicationInputActive(true)
            if mode == "control" || mode == "pan" {
                XCTAssertTrue(session.canSendDictation, mode)
                session.sendTextString("R")
                waitUntil { server.keys.count == 2 }
                XCTAssertEqual(server.keys.map(\.key), [82, 82], mode)
                XCTAssertEqual(server.keys.map(\.down), [true, false], mode)
                session.sendNativePointer(buttonMask: .left, x: 7, y: 8)
                session.sendNativePointer(buttonMask: [], x: 7, y: 8)
                if mode == "control" {
                    waitUntil { server.pointers.count == 2 }
                    XCTAssertEqual(server.pointers.map(\.mask), [1, 0])
                } else {
                    XCTAssertFalse(session.canTriggerHotCorner)
                    let panSettled = expectation(description: "Application resume preserves pointer Pan gate")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { panSettled.fulfill() }
                    wait(for: [panSettled], timeout: 2)
                    XCTAssertTrue(server.pointers.isEmpty)
                }
            } else {
                XCTAssertFalse(session.canSendDictation, mode)
                XCTAssertFalse(session.canTriggerHotCorner, mode)
                attemptSuppressedInput()
                let resumedSettled = expectation(description: "Resume respects Observe and selected session")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { resumedSettled.fulfill() }
                wait(for: [resumedSettled], timeout: 2)
                XCTAssertTrue(server.keys.isEmpty, mode)
                XCTAssertTrue(server.pointers.isEmpty, mode)
                XCTAssertEqual(session.cmdState, .inactive, mode)
                XCTAssertEqual(session.optState, .inactive, mode)
                XCTAssertEqual(session.ctrlState, .inactive, mode)
                XCTAssertEqual(session.shiftState, .inactive, mode)
            }
        }
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
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let session = TestSession.make(device: RemoteDevice(name: "Pan transport QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, deviceStore: store)
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
        let session = TestSession.make(device: RemoteDevice(name: "Display switch QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
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
        let session = TestSession.make(device: RemoteDevice(name: "Three-finger QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
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

    @MainActor
    func testHotCornersUseSelectedDisplayReleaseInputAndRejectHiddenObserveOrPan() throws {
        let ready = expectation(description: "Hot-corner listener ready")
        let connected = expectation(description: "Hot-corner connection ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Hot-corner QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.multiDisplayManager.updateFromLayout(RFBDisplayLayout(width: 16, height: 16, screens: [
            .init(id: 0, x: 0, y: 0, width: 8, height: 16, flags: 0),
            .init(id: 1, x: 8, y: 0, width: 8, height: 16, flags: 0)
        ]))
        session.multiDisplayManager.selectDisplay(id: 2)
        let selectionSettled = expectation(description: "Display selection callback applied")
        DispatchQueue.main.async { selectionSettled.fulfill() }
        wait(for: [selectionSettled], timeout: 2)
        waitUntil { server.pointers.last?.x == 12 }
        session.cycleCmd()
        session.client.sendKeyEvent(down: true, keySym: MacKeyMap.optionLeft)
        session.trackpadEngine.beginDrag()
        waitUntil { server.pointers.last?.mask == 1 && server.keys.count == 2 }
        let start = server.pointers.count
        session.triggerHotCorner(.bottomRight)
        waitUntil { server.pointers.last?.x == 15 && server.pointers.last?.y == 15 }
        XCTAssertTrue(server.pointers.dropFirst(start).allSatisfy { $0.mask == 0 })
        XCTAssertEqual(Array(server.pointers.suffix(2)).map { [$0.x, $0.y] }, [[12, 8], [15, 15]])
        XCTAssertEqual(session.trackpadEngine.cursorX, 7)
        XCTAssertEqual(session.trackpadEngine.cursorY, 15)
        XCTAssertEqual(session.cmdState, .inactive)
        waitUntil { server.keys.count == 4 }
        XCTAssertTrue(server.keys.suffix(2).allSatisfy { !$0.down })
        XCTAssertEqual(Set(server.keys.suffix(2).map(\.key)), [MacKeyMap.commandLeft, MacKeyMap.optionLeft])
        for (corner, x, y) in [(TrackpadEngine.HotCorner.topLeft, UInt16(8), UInt16(0)), (.topRight, 15, 0), (.bottomLeft, 8, 15), (.bottomRight, 15, 15)] {
            let count = server.pointers.count
            session.triggerHotCorner(corner)
            waitUntil { server.pointers.count >= count + 2 }
            XCTAssertEqual(server.pointers.last?.x, x)
            XCTAssertEqual(server.pointers.last?.y, y)
        }
        let forbidden = expectation(description: "Disabled corner sends remote motion")
        forbidden.isInverted = true
        server.onPointer = { _ in forbidden.fulfill() }
        session.isObserveOnly = true
        XCTAssertFalse(session.canTriggerHotCorner)
        session.triggerHotCorner(.topLeft)
        session.isObserveOnly = false
        session.setForegroundSession(false)
        session.triggerHotCorner(.topRight)
        session.setForegroundSession(true)
        session.isPanningViewport = true
        session.triggerHotCorner(.bottomLeft)
        wait(for: [forbidden], timeout: 0.2)
        server.onPointer = nil
        session.isPanningViewport = false
        XCTAssertTrue(session.canTriggerHotCorner)
        let count = server.pointers.count
        session.triggerHotCorner(.topLeft)
        waitUntil { server.pointers.count >= count + 2 }
        XCTAssertEqual(server.pointers.last?.x, 8)
        XCTAssertEqual(server.pointers.last?.y, 0)
    }

    func testPlainDisconnectReleasesHeldInputBeforeEOFAndRejectsLateInput() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        client.sendKeyEvent(down: true, keySym: 65, source: .app)
        client.sendKeyEvent(down: true, keySym: 65, source: .hardwareKeyboard)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.shiftLeft)
        client.sendPointerEvent(buttonMask: [.left, .right], x: 7, y: 9)
        waitUntil { server.keys.count == 3 && server.pointers.last?.mask == 5 }
        for _ in 0..<80 {
            client.sendPointerEvent(buttonMask: [.left, .right, .scrollDown], x: 7, y: 9)
        }
        client.disconnect()
        client.disconnect()
        XCTAssertEqual(client.state, .disconnected, "Plain disconnect must permit immediate replacement")
        client.sendKeyEvent(down: true, keySym: 98)
        client.sendPointerEvent(buttonMask: .left, x: 1, y: 2)
        XCTAssertFalse(client.sendCutText("Synthetic late clipboard"))
        waitUntil { server.closedInput != nil }
        let closed = try XCTUnwrap(server.closedInput)
        XCTAssertTrue(closed.cleanEOF)
        XCTAssertEqual(closed.keys.map(\.key), [65, 65, MacKeyMap.shiftLeft, 65, MacKeyMap.shiftLeft])
        XCTAssertEqual(closed.keys.map(\.down), [true, true, true, false, false],
                       "Each wire-held key must be released once, regardless of owner count")
        XCTAssertEqual(closed.pointers.last?.mask, 0)
        XCTAssertEqual(closed.pointers.last?.x, 7)
        XCTAssertEqual(closed.pointers.last?.y, 9)
        XCTAssertFalse(closed.pointers.contains { $0.x == 1 && $0.y == 2 })
        let settled = expectation(description: "Cancelled wheel backlog remains closed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(server.keys.count, closed.keys.count)
        XCTAssertEqual(server.pointers.count, closed.pointers.count)
    }

    func testDisconnectOnlyTransactionDrainsReleaseWithoutRemoteAction() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        client.sendKeyEvent(down: true, keySym: MacKeyMap.optionLeft)
        client.sendPointerEvent(buttonMask: .middle, x: 6, y: 8)
        waitUntil { server.keys.count == 1 && server.pointers.count == 1 }
        let processed = expectation(description: "Disconnect-only final write processed once")
        processed.assertForOverFulfill = true
        client.disconnect(after: .disconnectOnly) {
            XCTAssertTrue($0)
            processed.fulfill()
        }
        client.disconnect(after: .disconnectOnly) { XCTAssertFalse($0) }
        client.sendKeyEvent(down: true, keySym: 98)
        client.sendPointerEvent(buttonMask: .left, x: 2, y: 3)
        XCTAssertFalse(client.sendCutText("Synthetic closed transaction"))
        wait(for: [processed], timeout: 3)
        waitUntil { server.closedInput != nil }
        let closed = try XCTUnwrap(server.closedInput)
        XCTAssertTrue(closed.cleanEOF)
        XCTAssertEqual(closed.keys.map(\.key), [MacKeyMap.optionLeft, MacKeyMap.optionLeft])
        XCTAssertEqual(closed.keys.map(\.down), [true, false])
        XCTAssertEqual(closed.pointers.map(\.mask), [2, 0])
        XCTAssertTrue(closed.pointers.allSatisfy { $0.x == 6 && $0.y == 8 })
        XCTAssertEqual(client.state, .disconnected)
    }

    @MainActor
    func testActualApplicationBackgroundDrainsInputWithoutConfiguredActionAndPreservesViewport() throws {
        for action in [RemoteDisconnectAction.lockScreen, .logOut] {
            let ready = expectation(description: "Background close listener ready")
            let server = try PointerWireServer(framebufferBehavior: .pollOnly, ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let store = TestStorage.make()
            let device = RemoteDevice(name: "Background close QA", host: "127.0.0.1",
                port: try XCTUnwrap(server.listener.port).rawValue, disconnectAction: action,
                sharedClipboard: false)
            store.addDevice(device)
            let session = TestSession.make(device: device, password: nil, deviceStore: store)
            defer { session.client.disconnect() }
            session.setApplicationInputActive(true)
            session.startSession()
            waitUntil { session.sessionState == .connected && session.client.state == .connected && session.hasReceivedFirstFrame }
            session.zoomScale = 2.5
            session.viewOffset = CGSize(width: 11, height: -7)
            var hardware = session.keyboardConfiguration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
            hardware.repeatEnabled = false
            session.keyboardConfiguration.hardwareKeyboard = hardware
            session.isKeyboardVisible = true
            session.cycleCmd()
            session.cycleOption()
            session.cycleControl()
            session.cycleShift()
            session.sendNativeKey(down: true, keySym: 65)
            session.client.sendKeyEvent(down: true, keySym: 99)
            session.beginToolbarKeyHold(MacKeyMap.arrowLeft)
            session.client.sendKeyEvent(down: true, keySym: MacKeyMap.arrowLeft, source: .toolbarRepeat)
            session.sendNativePointer(buttonMask: .left, x: 11, y: 12)
            let held: Set<UInt32> = [MacKeyMap.commandLeft, MacKeyMap.optionLeft,
                MacKeyMap.controlLeft, MacKeyMap.shiftLeft, MacKeyMap.arrowLeft, 65, 99]
            waitUntil { Set(server.keys.filter(\.down).map(\.key)) == held && server.pointers.last?.mask == 1 }
            waitUntil {
                var pixel: UInt8 = 0
                session.client.framebuffer.withPixelBytes { bytes, _, _ in pixel = bytes[0] }
                return pixel == 2
            }
            let frame = session.client.framebuffer.pixels
            session.enterApplicationBackground()
            session.enterApplicationBackground()
            waitUntil { server.closedInput != nil && session.client.state == .disconnected }
            let closed = try XCTUnwrap(server.closedInput)
            XCTAssertTrue(closed.cleanEOF)
            XCTAssertEqual(Set(closed.keys.filter(\.down).map(\.key)), held)
            XCTAssertEqual(Set(closed.keys.filter { !$0.down }.map(\.key)), held)
            XCTAssertEqual(closed.keys.count, held.count * 2,
                           "Backgrounding must balance held input without emitting the saved lock or logout shortcut")
            XCTAssertEqual(closed.pointers.suffix(2).map(\.mask), [1, 0])
            XCTAssertTrue(closed.pointers.suffix(2).allSatisfy { $0.x == 11 && $0.y == 12 })
            XCTAssertEqual(session.cmdState, .inactive)
            XCTAssertEqual(session.optState, .inactive)
            XCTAssertEqual(session.ctrlState, .inactive)
            XCTAssertEqual(session.shiftState, .inactive)
            XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
            XCTAssertTrue(session.hasReceivedFirstFrame)
            XCTAssertEqual(session.zoomScale, 2.5)
            XCTAssertEqual(session.viewOffset, CGSize(width: 11, height: -7))
            XCTAssertEqual(session.client.framebuffer.pixels, frame)
            session.startSession()
            XCTAssertEqual(session.client.state, .disconnected, "An explicit start while backgrounded must not open RFB")
            session.setApplicationInputActive(true)
            session.setClipboardApplicationActive(true)
            session.setForegroundSession(true)
            session.sendNativeKey(down: true, keySym: 98)
            let settled = expectation(description: "Foreground leaves the closed socket closed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
            wait(for: [settled], timeout: 1)
            XCTAssertEqual(session.client.state, .disconnected)
            XCTAssertEqual(session.sessionState, .disconnected)
            XCTAssertEqual(server.connectionCount, 1, "Activation must not automatically reconnect a background-ended session")
            XCTAssertEqual(server.keys.count, closed.keys.count)
            XCTAssertEqual(server.pointers.count, closed.pointers.count)
        }
    }

    @MainActor
    func testDefaultSessionCloseReleasesNativeDragBeforeEOF() throws {
        let ready = expectation(description: "Native close listener ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let suite = "test.aetherscreens.native-close.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = TestSession.make(device: RemoteDevice(name: "Native close QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue, sharedClipboard: false), password: nil,
            isTemporary: true, deviceStore: TestStorage.make(userDefaults: defaults, legacySources: []),
            keyboardStore: KeyboardToolbarStore(defaults: defaults))
        defer { session.endSession() }
        session.setApplicationInputActive(true)
        session.startSession()
        waitUntil { session.sessionState == .connected && session.client.state == .connected }
        session.cycleCmd()
        session.sendNativeKey(down: true, keySym: 65)
        session.client.sendKeyEvent(down: true, keySym: 99)
        session.sendNativePointer(buttonMask: .left, x: 11, y: 12)
        waitUntil { server.keys.count == 3 && server.pointers.last?.mask == 1 }
        XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty,
                      "The native drag must exercise the path outside TrackpadEngine")
        session.endSession()
        session.endSession()
        session.sendNativeKey(down: true, keySym: 98)
        session.sendNativePointer(buttonMask: .right, x: 2, y: 3)
        waitUntil { server.closedInput != nil && session.client.state == .disconnected }
        let closed = try XCTUnwrap(server.closedInput)
        XCTAssertTrue(closed.cleanEOF)
        XCTAssertEqual(closed.keys.count, 6)
        XCTAssertEqual(Set(closed.keys.filter(\.down).map(\.key)), [MacKeyMap.commandLeft, 65, 99])
        XCTAssertEqual(Set(closed.keys.filter { !$0.down }.map(\.key)), [MacKeyMap.commandLeft, 65, 99])
        XCTAssertEqual(closed.pointers.map(\.mask), [1, 0])
        XCTAssertTrue(closed.pointers.allSatisfy { $0.x == 11 && $0.y == 12 })
        XCTAssertEqual(session.cmdState, .inactive)
        XCTAssertFalse(session.hasReceivedFirstFrame)
        XCTAssertEqual(session.sessionState, .disconnected)
    }

    func testPlainDisconnectCompletionCannotCloseImmediateReplacement() throws {
        let (oldServer, client) = try connectedPair()
        defer { client.disconnect(); oldServer.stop() }
        let ready = expectation(description: "Replacement listener ready")
        let replacement = try PointerWireServer(ready: { ready.fulfill() })
        defer { replacement.stop() }
        wait(for: [ready], timeout: 3)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 5)
        waitUntil { oldServer.pointers.count == 1 }
        let connected = expectation(description: "Immediate replacement connected")
        connected.assertForOverFulfill = true
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.disconnect()
        client.connect(transportHost: "127.0.0.1", transportPort: try XCTUnwrap(replacement.listener.port).rawValue)
        wait(for: [connected], timeout: 3)
        waitUntil { oldServer.closedInput != nil }
        let closed = try XCTUnwrap(oldServer.closedInput)
        XCTAssertTrue(closed.cleanEOF)
        XCTAssertEqual(closed.pointers.map(\.mask), [1, 0])
        XCTAssertTrue(closed.pointers.allSatisfy { $0.x == 4 && $0.y == 5 })
        let timeoutExpired = expectation(description: "Old disconnect fallback elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { timeoutExpired.fulfill() }
        wait(for: [timeoutExpired], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        client.sendKeyEvent(down: true, keySym: 98)
        client.sendKeyEvent(down: false, keySym: 98)
        client.sendPointerEvent(buttonMask: [], x: 8, y: 9)
        waitUntil { replacement.keys.count == 2 && replacement.pointers.count == 1 }
        XCTAssertEqual(replacement.keys.map(\.key), [98, 98])
        XCTAssertEqual(replacement.keys.map(\.down), [true, false])
        XCTAssertEqual(replacement.pointers.first?.mask, 0)
        XCTAssertEqual(client.state, .connected)
    }

    func testFinalDisconnectTransactionReleasesInputAndSendsEachMacAction() throws {
        for action in RemoteDisconnectAction.allCases where action != .disconnectOnly {
            let (server, client) = try connectedPair()
            defer { client.disconnect(); server.stop() }
            client.sendKeyEvent(down: true, keySym: MacKeyMap.optionLeft)
            client.sendPointerEvent(buttonMask: .left, x: 4, y: 5)
            waitUntil { server.keys.count == 1 && server.pointers.last?.mask == 1 }
            let processed = expectation(description: "Final action processed: " + action.rawValue)
            processed.assertForOverFulfill = true
            client.disconnect(after: action, display: CGRect(x: 8, y: 0, width: 8, height: 16)) {
                XCTAssertTrue($0)
                processed.fulfill()
            }
            client.sendKeyEvent(down: true, keySym: 98)
            XCTAssertFalse(client.sendCutText("Cannot follow final input"))
            wait(for: [processed], timeout: 3)
            switch action {
            case .lockScreen, .logOut:
                let expectedKeys: [UInt32] = action == .lockScreen
                    ? [0xFFE3, 0xFFEB, 113, 113, 0xFFEB, 0xFFE3]
                    : [0xFFE9, 0xFFE1, 0xFFEB, 113, 113, 0xFFEB, 0xFFE1, 0xFFE9]
                waitUntil { server.keys.count == expectedKeys.count + 2 }
                XCTAssertEqual(server.keys.dropFirst(2).map(\.key), expectedKeys)
                XCTAssertEqual(server.keys.dropFirst(2).map(\.down), action == .lockScreen
                    ? [true, true, true, false, false, false]
                    : [true, true, true, true, false, false, false, false])
                XCTAssertEqual(server.pointers.last?.mask, 0)
                XCTAssertEqual(server.pointers.last?.x, 4)
                XCTAssertEqual(server.pointers.last?.y, 5)
            default:
                waitUntil { server.pointers.count == 4 }
                XCTAssertEqual(Array(server.pointers.suffix(2)).map { [$0.x, $0.y] },
                               [[12, 8], [action == .topRight || action == .bottomRight ? 15 : 8,
                                           action == .bottomLeft || action == .bottomRight ? 15 : 0]])
                XCTAssertEqual(server.keys.count, 2)
            }
            XCTAssertEqual(server.keys[1].key, MacKeyMap.optionLeft)
            XCTAssertFalse(server.keys[1].down)
            XCTAssertTrue(server.pointers.dropFirst().allSatisfy { $0.mask == 0 })
            XCTAssertEqual(client.state, .disconnected)
        }
    }

    @MainActor
    func testConfiguredDisconnectRunsOnceIncludingRetainedSessionsAndObserveOrInterruptionSkipIt() throws {
        for mode in ["control", "observe", "hidden", "interrupted"] {
            let ready = expectation(description: "Disconnect listener ready")
            let connected = expectation(description: "Disconnect connected")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let session = TestSession.make(device: RemoteDevice(name: "Disconnect QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, disconnectAction: .lockScreen), password: nil, isTemporary: true)
            session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
            session.startSession()
            wait(for: [connected], timeout: 3)
            if mode == "observe" { session.isObserveOnly = true }
            if mode == "hidden" { session.setForegroundSession(false) }
            if mode == "interrupted" { session.client.disconnect() }
            session.endSession()
            session.endSession()
            // Closing a retained control session is an explicit action; hidden
            // sessions still reject unsolicited ordinary pointer/key input.
            let performsAction = mode == "control" || mode == "hidden"
            if performsAction { waitUntil { server.keys.count == 6 } }
            let drained = expectation(description: "Ended callbacks drain")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(server.keys.count, performsAction ? 6 : 0)
            XCTAssertFalse(session.hasReceivedFirstFrame)
            XCTAssertEqual(session.client.state, .disconnected)
        }
    }

    @MainActor
    func testScreenBoundaryTargetsSelectedDisplayAndRejectsObservePanAndHidden() throws {
        let ready = expectation(description: "Boundary listener ready")
        let connected = expectation(description: "Boundary connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Boundary QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.multiDisplayManager.updateFromLayout(RFBDisplayLayout(width: 16, height: 16, screens: [
            .init(id: 0, x: 0, y: 0, width: 8, height: 16, flags: 0),
            .init(id: 1, x: 8, y: 0, width: 8, height: 16, flags: 0)]))
        session.multiDisplayManager.selectDisplay(id: 2)
        let selection = expectation(description: "Boundary display selection")
        DispatchQueue.main.async { selection.fulfill() }
        wait(for: [selection], timeout: 2)
        waitUntil { server.pointers.last?.x == 12 }
        let expected: [(ScreenEdge, UInt16, UInt16)] = [(.left, 8, 8), (.right, 15, 8), (.top, 12, 0), (.bottom, 12, 15)]
        for (edge, x, y) in expected {
            session.trackpadEngine.beginDrag(button: .left)
            session.triggerScreenBoundary(.edge(edge))
            waitUntil { server.pointers.last?.x == x && server.pointers.last?.y == y && server.pointers.last?.mask == 0 }
            XCTAssertTrue(session.trackpadEngine.activeButtons.isEmpty)
        }
        session.triggerScreenBoundary(.corner(.bottomRight))
        waitUntil { server.pointers.last?.x == 15 && server.pointers.last?.y == 15 }
        for mode in ["observe", "pan", "hidden"] {
            session.isObserveOnly = mode == "observe"
            session.isPanningViewport = mode == "pan"
            session.setForegroundSession(mode != "hidden")
            let count = server.pointers.count
            session.triggerScreenBoundary(.edge(.top))
            session.triggerScreenBoundary(.corner(.topLeft))
            let drained = expectation(description: "Boundary \(mode) rejected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(server.pointers.count, count)
        }
    }

    @MainActor
    func testLiveCursorSpeedChangesReceivedRelativeMotionButNotAbsolutePosition() throws {
        let ready = expectation(description: "Cursor speed receiver ready")
        let connected = expectation(description: "Cursor speed connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Speed QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue, cursorSpeed: 0.5), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        XCTAssertEqual(session.cursorSpeed, 0.5)
        session.trackpadEngine.remoteWidth = CGFloat(session.client.framebuffer.width)
        session.trackpadEngine.remoteHeight = CGFloat(session.client.framebuffer.height)
        session.trackpadEngine.moveCursor(to: CGPoint(x: 4, y: 4))
        session.setCursorSpeed(1)
        session.trackpadEngine.handlePanDelta(dx: 1, dy: 0)
        waitUntil { server.pointers.last?.x == 5 }
        session.trackpadEngine.moveCursor(to: CGPoint(x: 4, y: 4))
        session.setCursorSpeed(2)
        session.trackpadEngine.handlePanDelta(dx: 1, dy: 0)
        waitUntil { server.pointers.last?.x == 6 }
        session.trackpadEngine.handleAbsolutePointer(point: CGPoint(x: 50, y: 50), viewSize: CGSize(width: 100, height: 100), buttons: [], source: .pencil)
        waitUntil { server.pointers.last?.x == 8 && server.pointers.last?.y == 8 }
        session.setCursorSpeed(.nan)
        XCTAssertEqual(session.cursorSpeed, 1)
    }

    @MainActor
    func testIndividualFunctionAndNavigationToolbarKeysReachTCP() throws {
        let ready = expectation(description: "Optional toolbar keys listener ready")
        let connected = expectation(description: "Optional toolbar keys connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Optional Keys QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let expected: [UInt32] = [0xFF55, 0xFF56, 0xFF50, 0xFF57] + Array(UInt32(0xFFBE)...UInt32(0xFFC9))
        for (index, action) in KeyboardToolbarConfiguration.Action.optionalKeys.enumerated() {
            session.sendKeyTap(try XCTUnwrap(action.keySym))
            waitUntil { server.keys.count == (index + 1) * 2 }
        }
        XCTAssertEqual(server.keys.map(\.key), expected.flatMap { [$0, $0] })
        XCTAssertEqual(server.keys.map(\.down), expected.flatMap { _ in [true, false] })
    }

    @MainActor
    func testToolbarTapHoldCancellationAndObserveReachTCP() throws {
        let ready = expectation(description: "Toolbar repeat listener ready")
        let connected = expectation(description: "Toolbar repeat connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Toolbar Repeat QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.isKeyboardVisible = true
        var settings = HardwareKeyboardConfiguration()
        settings.repeatDelay = 0.2
        settings.repeatInterval = 0.05
        session.keyboardConfiguration.hardwareKeyboard = settings
        session.beginToolbarKeyHold(MacKeyMap.tab)
        session.endToolbarKeyHold(MacKeyMap.tab, activate: true)
        waitUntil { server.keys.count == 2 }
        XCTAssertEqual(server.keys.map(\.down), [true, false])
        session.beginToolbarKeyHold(MacKeyMap.return)
        session.endToolbarKeyHold(MacKeyMap.return, activate: false)
        let cancelled = expectation(description: "Cancelled short hold sends no key")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cancelled.fulfill() }
        wait(for: [cancelled], timeout: 2)
        XCTAssertEqual(server.keys.count, 2)
        session.beginToolbarKeyHold(MacKeyMap.arrowLeft)
        waitUntil { server.keys.count >= 5 }
        session.endToolbarKeyHold(MacKeyMap.arrowLeft, activate: true)
        waitUntil { server.keys.last?.key == MacKeyMap.arrowLeft && server.keys.last?.down == false }
        let releasedCount = server.keys.count
        let stopped = expectation(description: "Released repeat remains stopped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { stopped.fulfill() }
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(server.keys.count, releasedCount, "Release must not trigger an extra ordinary tap")
        session.beginToolbarKeyHold(MacKeyMap.delete)
        waitUntil { server.keys.last?.key == MacKeyMap.delete && server.keys.last?.down == true }
        session.isObserveOnly = true
        waitUntil { server.keys.last?.key == MacKeyMap.delete && server.keys.last?.down == false }
        let observeCount = server.keys.count
        let observed = expectation(description: "Observe cancels repeat task")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { observed.fulfill() }
        wait(for: [observed], timeout: 2)
        XCTAssertEqual(server.keys.count, observeCount)
    }

    @MainActor
    func testHardwareRepeatPacketsStopOnObserveAndRelease() throws {
        let ready = expectation(description: "Repeat receiver ready")
        let connected = expectation(description: "Repeat connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Repeat QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let keyboard = HardwareKeyboardState()
        keyboard.onKeyEvent = { session.handleHardwareKey(down: $0, keySym: $1) }
        keyboard.press(usage: 0x2A, characters: "", at: 0)
        keyboard.advanceRepeat(at: 0.5)
        keyboard.advanceRepeat(at: 0.6)
        keyboard.releaseAll()
        keyboard.advanceRepeat(at: 1)
        waitUntil { server.keys.count == 4 }
        XCTAssertEqual(server.keys.map(\.key), Array(repeating: MacKeyMap.backspace, count: 4))
        XCTAssertEqual(server.keys.map(\.down), [true, true, true, false])
        keyboard.press(usage: 0x50, characters: "", at: 2)
        waitUntil { server.keys.count == 5 }
        session.isObserveOnly = true
        waitUntil { server.keys.count == 6 }
        keyboard.advanceRepeat(at: 3)
        keyboard.releaseAll()
        let drained = expectation(description: "Observe blocks queued repeat")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(server.keys.count, 6)
        XCTAssertFalse(server.keys.last!.down)
    }

    @MainActor
    func testSavedUserPasswordAuthenticatesThenTypesBalancedUnicodeWithoutClipboard() throws {
        let ready = expectation(description: "Password transaction listener ready")
        let connected = expectation(description: "Password transaction connected")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let forbidden = expectation(description: "Password must never use clipboard transfer")
        forbidden.isInverted = true
        server.onCutText = { _ in forbidden.fulfill() }
        server.onAppleClipboard = { _ in forbidden.fulfill() }
        server.onExtendedClipboard = { _, _ in forbidden.fulfill() }
        let suite = "test.aetherscreens.password-command.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let device = RemoteDevice(name: "Password command QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
            authMethod: .macAccount, username: "fixture-account", sharedClipboard: false)
        store.addDevice(device)
        var authentications = 0, reads = 0
        let session = TestSession.make(device: device, password: nil, deviceStore: store,
            userPasswordReader: { _ in reads += 1; return "QA中😀" },
            userPasswordAuthentication: { authentications += 1; return true })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        // This fixture tests post-authentication command transport, not ARD.
        // Establish its None-auth socket, then supply its synthetic account identity.
        session.client.username = nil
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.username = "fixture-account"
        XCTAssertTrue(session.canTypeUserPassword)
        session.cycleCmd()
        session.typeUserPassword()
        waitUntil { server.keys.count == 14 }
        XCTAssertEqual(authentications, 1)
        XCTAssertEqual(reads, 1)
        let textKeys: [UInt32] = [81, 65, 0x01004E2D, 0x0100D83D, 0x0100DE00]
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, MacKeyMap.commandLeft]
            + textKeys.flatMap { [$0, $0] } + [MacKeyMap.return, MacKeyMap.return])
        XCTAssertEqual(server.keys.map(\.down), [true, false] + Array(repeating: [true, false], count: 6).flatMap { $0 })
        session.typeUserPassword(pressReturn: false)
        waitUntil { server.keys.count == 24 }
        XCTAssertEqual(server.keys.suffix(10).map(\.key), textKeys.flatMap { [$0, $0] })
        XCTAssertEqual(authentications, 2)
        XCTAssertEqual(reads, 2)
        XCTAssertNil(session.userPasswordError)
        XCTAssertFalse(session.isTypingUserPassword)
        XCTAssertFalse(AppLogger.shared.exportLogs().contains("QA中😀"))
        wait(for: [forbidden], timeout: 0.2)
    }

    @MainActor
    func testDeniedUserPasswordAuthenticationNeverReadsCredentialsOrSendsInput() throws {
        let ready = expectation(description: "Denied password listener ready")
        let connected = expectation(description: "Denied password connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let suite = "test.aetherscreens.password-denied.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let device = RemoteDevice(name: "Denied password QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
            authMethod: .macAccount, username: "fixture-account", sharedClipboard: false)
        store.addDevice(device)
        var reads = 0, authentications = 0
        let session = TestSession.make(device: device, password: nil, deviceStore: store,
            userPasswordReader: { _ in reads += 1; return "synthetic-only" },
            userPasswordAuthentication: { authentications += 1; return false })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        // This fixture tests post-authentication command transport, not ARD.
        // Establish its None-auth socket, then supply its synthetic account identity.
        session.client.username = nil
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.username = "fixture-account"
        session.typeUserPassword()
        waitUntil { authentications == 1 && !session.isTypingUserPassword }
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertNil(session.userPasswordError)
        session.isObserveOnly = true
        session.typeUserPassword()
        XCTAssertEqual(authentications, 1)
        session.isObserveOnly = false
        session.setForegroundSession(false)
        session.typeUserPassword()
        XCTAssertEqual(authentications, 1)
    }


    @MainActor
    func testTemporaryMacPasswordUsesCurrentCredentialAndRejectsUnsupportedText() throws {
        let ready = expectation(description: "Temporary password listener ready")
        let connected = expectation(description: "Temporary password connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let device = RemoteDevice(name: "Temporary password QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
            authMethod: .macAccount, username: "fixture-account", sharedClipboard: false)
        var reads = 0, authentications = 0
        let session = TestSession.make(device: device, password: "QA", isTemporary: true,
            userPasswordReader: { _ in reads += 1; return nil },
            userPasswordAuthentication: { authentications += 1; return true })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.client.username = nil // None-auth wire fixture; synthetic post-auth identity below.
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.username = "fixture-account"
        XCTAssertTrue(session.canTypeUserPassword)
        session.typeUserPassword(pressReturn: false)
        waitUntil { server.keys.count == 4 }
        XCTAssertEqual(server.keys.map(\.key), [81, 81, 65, 65])
        XCTAssertEqual(reads, 0, "The current session credential must take precedence over an older saved password")
        for invalid in ["", "QA\n", String(repeating: "Q", count: 4097)] {
            session.client.password = invalid
            session.typeUserPassword()
            waitUntil { !session.isTypingUserPassword }
            XCTAssertNotNil(session.userPasswordError)
            XCTAssertEqual(server.keys.count, 4)
        }
        XCTAssertEqual(authentications, 4)
        XCTAssertEqual(reads, 0)
    }

    @MainActor
    func testPhysicalKeyboardPreferencesReachTCPWithoutChangingToolbarKeys() throws {
        let ready = expectation(description: "Physical mapping listener ready")
        let connected = expectation(description: "Physical mapping connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Mapping QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        var config = HardwareKeyboardConfiguration()
        config.swapCommandControl = true
        config.commandBackslashSwitchesApps = true
        session.keyboardConfiguration.hardwareKeyboard = config
        session.handleHardwareKey(down: true, keySym: MacKeyMap.controlLeft)
        session.handleHardwareKey(down: true, keySym: 0x5C)
        session.handleHardwareKey(down: true, keySym: 0x5C)
        config.swapCommandControl = false
        config.commandBackslashSwitchesApps = false
        session.keyboardConfiguration.hardwareKeyboard = config
        session.handleHardwareKey(down: false, keySym: 0x5C)
        session.handleHardwareKey(down: false, keySym: MacKeyMap.controlLeft)
        session.sendNativeKey(down: true, keySym: MacKeyMap.commandRight)
        session.sendNativeKey(down: false, keySym: MacKeyMap.commandRight)
        config.swapCommandControl = true
        session.keyboardConfiguration.hardwareKeyboard = config
        session.cycleCmd()
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        session.handleHardwareKey(down: false, keySym: MacKeyMap.commandLeft)
        session.releaseAllModifiers()
        waitUntil { server.keys.count == 11 }
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, MacKeyMap.tab, MacKeyMap.tab, MacKeyMap.tab,
            MacKeyMap.commandLeft, MacKeyMap.commandRight, MacKeyMap.commandRight, MacKeyMap.commandLeft,
            MacKeyMap.controlLeft, MacKeyMap.controlLeft, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, true, true, false, false, true, false, true, true, false, false])
    }

    @MainActor
    func testStickyAndPhysicalModifiersRemainHeldUntilBothSourcesRelease() throws {
        let ready = expectation(description: "Shared modifier listener ready")
        let connected = expectation(description: "Shared modifier connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Shared Modifier QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.cycleCmd()
        session.cycleCmd() // Toolbar locks its own Cmd source.
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        session.handleHardwareKey(down: false, keySym: MacKeyMap.commandLeft)
        waitUntil { server.keys.count == 2 }
        XCTAssertEqual(server.keys.map(\.down), [true, true])
        XCTAssertEqual(session.cmdState, .locked)
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        session.cycleCmd() // Toolbar releases while the physical key stays down.
        session.handleHardwareKey(down: false, keySym: MacKeyMap.commandLeft)
        waitUntil { server.keys.count == 4 }
        XCTAssertEqual(server.keys.map(\.down), [true, true, true, false])
        XCTAssertEqual(session.cmdState, .inactive)
        session.cycleCmd()
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        waitUntil { server.keys.count == 6 }
        session.isObserveOnly = true
        waitUntil { server.keys.count == 7 }
        XCTAssertFalse(server.keys.last!.down, "Disabling input releases the aggregate key exactly once")
        session.isObserveOnly = false
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandLeft)
        session.handleHardwareKey(down: false, keySym: MacKeyMap.commandLeft)
        waitUntil { server.keys.count == 9 }
        XCTAssertEqual(server.keys.suffix(2).map(\.down), [true, false], "Input-disable must clear stale source owners")
    }

    @MainActor
    func testHardwareKeyboardShortcutsAndObserveBackgroundReleaseReachTCP() throws {
        let ready = expectation(description: "Hardware keyboard listener ready")
        let connected = expectation(description: "Hardware keyboard connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Keyboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let keyboard = HardwareKeyboardState()
        keyboard.onKeyEvent = { session.handleHardwareKey(down: $0, keySym: $1) }
        keyboard.press(usage: 0xE3, characters: "")
        keyboard.press(usage: 6, characters: "c")
        keyboard.press(usage: 6, characters: "C")
        keyboard.releaseAll()
        waitUntil { server.keys.count == 5 }
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, 99, 99, 99, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, true, true, false, false])
        session.handleHardwareKey(down: true, keySym: MacKeyMap.commandRight)
        waitUntil { server.keys.count == 6 }
        session.isObserveOnly = true
        waitUntil { server.keys.count == 7 }
        XCTAssertFalse(server.keys.last!.down)
        session.handleHardwareKey(down: true, keySym: 120)
        session.isObserveOnly = false
        session.handleHardwareKey(down: true, keySym: 97)
        waitUntil { server.keys.count == 8 }
        session.setForegroundSession(false)
        waitUntil { server.keys.count == 9 }
        XCTAssertEqual(server.keys.last!.key, 97)
        XCTAssertFalse(server.keys.last!.down)
        session.handleHardwareKey(down: true, keySym: 121)
        let drained = expectation(description: "Inactive hardware input suppressed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(server.keys.count, 9)
        XCTAssertFalse(server.keys.contains { $0.key == 120 || $0.key == 121 })
    }

    @MainActor
    func testPencilShortcutsUseSelectedDisplayAndGateRemoteClicksSeparatelyFromLocalToolbar() throws {
        let ready = expectation(description: "Pencil shortcuts receiver ready")
        let connected = expectation(description: "Pencil shortcuts connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Pencil QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.multiDisplayManager.updateFromLayout(RFBDisplayLayout(width: 16, height: 16, screens: [
            .init(id: 0, x: 0, y: 0, width: 8, height: 16, flags: 0),
            .init(id: 1, x: 8, y: 0, width: 8, height: 16, flags: 0)
        ]))
        session.multiDisplayManager.selectDisplay(id: 2)
        let selection = expectation(description: "Pencil selected monitor applied")
        DispatchQueue.main.async { selection.fulfill() }
        wait(for: [selection], timeout: 2)
        waitUntil { server.pointers.last?.x == 12 }
        session.keyboardConfiguration.pencilDoubleTapAction = .secondaryClick
        session.keyboardConfiguration.pencilSqueezeAction = .middleClick
        session.trackpadEngine.handleAbsolutePointer(point: CGPoint(x: 50, y: 50), viewSize: CGSize(width: 100, height: 100), buttons: .left, source: .pencil)
        waitUntil { server.pointers.last?.mask == 1 }
        session.handlePencilGesture(.doubleTap)
        waitUntil { server.pointers.suffix(2).map(\.mask) == [4, 0] }
        XCTAssertEqual(server.pointers.suffix(3).map(\.mask), [0, 4, 0], "The gesture must release Pencil contact before secondary click")
        XCTAssertTrue(server.pointers.suffix(3).allSatisfy { $0.x == 12 && $0.y == 8 })
        session.handlePencilGesture(.squeeze, location: CGPoint(x: 75, y: 25), viewSize: CGSize(width: 100, height: 100))
        waitUntil { server.pointers.suffix(2).map(\.mask) == [2, 0] }
        XCTAssertTrue(server.pointers.suffix(3).allSatisfy { $0.x == 14 && $0.y == 4 }, "Squeeze must use its reported tip on the selected display, not the old cursor")
        let beforeInvalid = server.pointers.count
        for location in [CGPoint(x: -1, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: CGFloat.nan, y: 50)] {
            session.handlePencilGesture(.squeeze, location: location, viewSize: CGSize(width: 100, height: 100))
        }
        let invalidDrained = expectation(description: "Invalid Pencil pose emits no remote input")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { invalidDrained.fulfill() }
        wait(for: [invalidDrained], timeout: 2)
        XCTAssertEqual(server.pointers.count, beforeInvalid)
        for mode in ["observe", "pan", "hidden", "disconnected"] {
            session.isObserveOnly = mode == "observe"
            session.isPanningViewport = mode == "pan"
            session.setForegroundSession(mode != "hidden")
            if mode == "disconnected" { session.client.disconnect() }
            let count = server.pointers.count
            session.handlePencilGesture(.doubleTap, location: CGPoint(x: 25, y: 25), viewSize: CGSize(width: 100, height: 100))
            session.handlePencilGesture(.squeeze, location: CGPoint(x: 25, y: 25), viewSize: CGSize(width: 100, height: 100))
            let drained = expectation(description: "Pencil \(mode) suppression")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(server.pointers.count, count)
            session.keyboardConfiguration.pencilSqueezeAction = .toggleToolbar
            let visible = session.isKeyboardVisible
            session.handlePencilGesture(.squeeze)
            XCTAssertEqual(session.isKeyboardVisible, mode == "observe" || mode == "pan" ? !visible : visible)
            session.keyboardConfiguration.pencilSqueezeAction = .middleClick
        }
    }

    @MainActor
    func testAbsoluteMouseAndPencilButtonsReachTCPAndObserveSuppressesThem() throws {
        let (server, client) = try connectedPair()
        defer { server.stop(); client.disconnect() }
        let engine = TrackpadEngine(remoteWidth: 16, remoteHeight: 16)
        engine.onPointerEvent = { client.sendPointerEvent(buttonMask: $0, x: $1, y: $2) }
        let size = CGSize(width: 100, height: 100)
        engine.handleAbsolutePointer(point: CGPoint(x: 25, y: 50), viewSize: size, buttons: .right, source: .mouse)
        engine.handleAbsolutePointer(point: CGPoint(x: 50, y: 50), viewSize: size, buttons: .left, source: .pencil)
        engine.releaseAbsolutePointer(.mouse)
        engine.releaseAbsolutePointer(.pencil)
        waitUntil { server.pointers.count == 4 }
        XCTAssertEqual(server.pointers.map(\.mask), [4, 5, 1, 0])
        XCTAssertEqual(server.pointers.map(\.x), [4, 8, 8, 8])
        client.setInputEnabled(false)
        engine.handleAbsolutePointer(point: CGPoint(x: 75, y: 25), viewSize: size, buttons: .middle, source: .mouse)
        engine.releaseAllButtons()
        let settled = expectation(description: "Observe native pointer blocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(server.pointers.count, 4)
        client.setInputEnabled(true)
        engine.handleAbsolutePointer(point: CGPoint(x: 75, y: 25), viewSize: size, buttons: .middle, source: .mouse)
        engine.releaseAbsolutePointer(.mouse)
        waitUntil { server.pointers.count == 6 }
        XCTAssertEqual(server.pointers.suffix(2).map(\.mask), [2, 0])
        XCTAssertEqual(server.pointers.suffix(2).map(\.x), [12, 12])
    }

    @MainActor
    func testSoftwareKeyboardReturnSendsCommittedTextBeforeReturnOnAppleTCP() throws {
        let ready = expectation(description: "Software keyboard receiver ready")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Keyboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.startSession()
        waitUntil { session.canSendDictation }
        session.textInputBuffer = "qa1中"
        XCTAssertTrue(session.submitTextInput(pressReturn: true))
        waitUntil { server.keys.count == 10 }
        XCTAssertEqual(server.keys.map(\.key), [113, 113, 97, 97, 49, 49, 0x01004E2D, 0x01004E2D, 0xFF0D, 0xFF0D])
        XCTAssertEqual(server.keys.map(\.down), [true, false, true, false, true, false, true, false, true, false])
        XCTAssertEqual(session.textInputBuffer, "")
    }

    @MainActor
    func testSoftwareKeyboardSendDoesNotSubmitAndEmptyReturnStillReachesTCP() throws {
        let ready = expectation(description: "Software keyboard receiver ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Keyboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.startSession()
        waitUntil { session.canSendDictation }
        session.textInputBuffer = "qa1"
        XCTAssertTrue(session.submitTextInput(pressReturn: false))
        waitUntil { server.keys.count == 6 }
        XCTAssertEqual(server.keys.map(\.key), [113, 113, 97, 97, 49, 49])
        XCTAssertEqual(session.textInputBuffer, "")
        XCTAssertFalse(session.submitTextInput(pressReturn: false))
        XCTAssertTrue(session.submitTextInput(pressReturn: true))
        waitUntil { server.keys.count == 8 }
        XCTAssertEqual(server.keys.suffix(2).map(\.key), [0xFF0D, 0xFF0D])
        XCTAssertEqual(server.keys.suffix(2).map(\.down), [true, false])
    }

    @MainActor
    func testSoftwareKeyboardSubmissionPreservesDraftWhenSessionCannotControl() throws {
        for mode in ["observe", "hidden", "disconnected", "closing"] {
            let ready = expectation(description: "Software keyboard receiver ready")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let session = TestSession.make(device: RemoteDevice(name: "Keyboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
            defer { session.endSession() }
            session.startSession()
            waitUntil { session.canSendDictation }
            if mode == "observe" { session.isObserveOnly = true }
            if mode == "hidden" { session.setForegroundSession(false) }
            if mode == "disconnected" { session.client.disconnect() }
            if mode == "closing" { session.endSession() }
            session.textInputBuffer = "unsubmitted draft"
            XCTAssertFalse(session.submitTextInput(pressReturn: true), mode)
            XCTAssertFalse(session.submitTextInput(pressReturn: false), mode)
            XCTAssertEqual(session.textInputBuffer, "unsubmitted draft", mode)
            let drained = expectation(description: "No keys sent in \(mode)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertTrue(server.keys.isEmpty, mode)
        }
    }

    @MainActor
    func testConfirmedDictationOnlyReachesCurrentControlSession() throws {
        for mode in ["control", "observe", "hidden", "disconnected", "closing"] {
            let ready = expectation(description: "Dictation receiver ready")
            let connected = expectation(description: "Dictation connected")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let session = TestSession.make(device: RemoteDevice(name: "Dictation QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
            session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
            session.startSession()
            wait(for: [connected], timeout: 3)
            if mode == "observe" { session.isObserveOnly = true }
            if mode == "hidden" { session.setForegroundSession(false) }
            if mode == "disconnected" { session.client.disconnect() }
            if mode == "closing" { session.endSession() }
            XCTAssertEqual(session.canSendDictation, mode == "control")
            session.sendDictation("  \n")
            session.sendDictation("Dictation 中文")
            if mode == "control" { waitUntil { server.keys.count == 24 } }
            let drained = expectation(description: "Dictation packets drained")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(server.keys.count, mode == "control" ? 24 : 0)
            if mode == "control" {
                let expected: [UInt32] = [68, 105, 99, 116, 97, 116, 105, 111, 110, 32, 0x01004E2D, 0x01006587]
                XCTAssertEqual(server.keys.filter(\.down).map(\.key), expected)
                XCTAssertEqual(server.keys.filter { !$0.down }.map(\.key), expected)
            }
            session.endSession()
        }
    }

    @MainActor
    func testRetainedSessionUsesCurrentPreferenceAndSkipsDeletedOrChangedTargets() throws {
        for mode in ["enabled", "disabled", "deleted", "changed", "account"] {
            let suite = "test.aetherscreens.disconnect." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = TestStorage.make(userDefaults: defaults)
            let ready = expectation(description: "Retained action listener ready")
            let connected = expectation(description: "Retained action session connected")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            var device = RemoteDevice(name: "Retained disconnect QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                                      disconnectAction: mode == "enabled" ? nil : .lockScreen)
            store.addDevice(device)
            let session = TestSession.make(device: device, password: nil, deviceStore: store)
            session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
            session.startSession()
            wait(for: [connected], timeout: 3)
            switch mode {
            case "enabled": device.disconnectAction = .lockScreen; store.updateDevice(device)
            case "disabled": device.disconnectAction = nil; store.updateDevice(device)
            case "deleted": store.deleteDevice(device)
            case "account": device.username = "different-qa-account"; store.updateDevice(device)
            default: device.host = "other-qa.invalid"; store.updateDevice(device)
            }
            session.endSession()
            if mode == "enabled" { waitUntil { server.keys.count == 6 } }
            let drained = expectation(description: "Retained session close settled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
            wait(for: [drained], timeout: 2)
            XCTAssertEqual(server.keys.count, mode == "enabled" ? 6 : 0)
            XCTAssertEqual(session.client.state, .disconnected)
        }
    }

    func testFinalDisconnectCallbackCannotCloseReplacementConnection() throws {
        let (server, client) = try connectedPair()
        defer { client.disconnect(); server.stop() }
        let settled = expectation(description: "Old close settles once")
        settled.assertForOverFulfill = true
        client.disconnect(after: .lockScreen) { _ in settled.fulfill() }
        client.disconnect()
        let connected = expectation(description: "Replacement connected")
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [settled, connected], timeout: 3)
        // Let the old operation's timeout expire before exercising the new socket.
        let timeoutExpired = expectation(description: "Old final-send timeout expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { timeoutExpired.fulfill() }
        wait(for: [timeoutExpired], timeout: 3)
        XCTAssertEqual(client.state, .connected)
        client.sendKeyEvent(down: true, keySym: 98)
        client.sendKeyEvent(down: false, keySym: 98)
        waitUntil { server.keys.last?.key == 98 && server.keys.last?.down == false }
        XCTAssertEqual(client.state, .connected)
    }

    func testConcurrentImmediateReconnectKeepsOneHandshakeReader() throws {
        for attempt in 0..<12 {
            let ready = expectation(description: "Concurrent listener ready")
            let connected = expectation(description: "Concurrent replacement connected")
            let returnReceived = expectation(description: "Replacement Return received")
            let server = try PointerWireServer(banner: attempt.isMultiple(of: 2) ? "RFB 003.008\n" : "RFB 003.889\n", ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
            defer { client.disconnect() }
            let first = RefreshReconnectFlag()
            client.onStateChanged = { state in
                guard state == .connected else { return }
                if first.take() {
                    DispatchQueue.global(qos: .userInteractive).async {
                        client.disconnect()
                        client.connect()
                    }
                } else { connected.fulfill() }
            }
            client.connect()
            wait(for: [connected], timeout: 3)
            XCTAssertEqual(client.state, .connected, "Replacement handshake \(attempt)")
            server.onKey = { key in
                if key.key == MacKeyMap.return && !key.down { returnReceived.fulfill() }
            }
            client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
            client.sendKeyEvent(down: false, keySym: MacKeyMap.return)
            wait(for: [returnReceived], timeout: 3)
            XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.return, MacKeyMap.return])
            XCTAssertEqual(server.keys.map(\.down), [true, false])
        }
    }

    #if canImport(AppKit)
    @MainActor
    func testNativeViewReplacementReleasesHeldInputWithoutClosingSession() throws {
        let ready = expectation(description: "Native lifecycle loopback ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Native lifecycle QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.startSession()
        waitUntil { session.sessionState == .connected && session.client.state == .connected }
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.remoteSize = CGSize(width: 16, height: 16)
        view.onKeyEvent = { session.sendNativeKey(down: $0, keySym: $1) }
        view.onPointerEvent = { session.sendNativePointer(buttonMask: $0, x: $1, y: $2) }
        view.onInputReset = { session.resetNativePointerInput() }
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f702}",
            charactersIgnoringModifiers: "\u{f702}", isARepeat: false, keyCode: 123))
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        view.keyDown(with: down)
        view.mouseDown(with: mouse)
        waitUntil { server.keys.count == 1 && server.pointers.count == 1 }
        let previousGeneration = session.inputGeneration
        session.toggleFullscreen()
        XCTAssertNotEqual(session.inputGeneration, previousGeneration)
        // Invoke SwiftUI's cleanup contract directly; this is not a rendered GUI run.
        MacNativeInputRepresentable.dismantleNSView(view, coordinator: ())
        waitUntil { server.keys.count == 2 && server.pointers.count == 2 }
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.arrowLeft, MacKeyMap.arrowLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, false])
        XCTAssertEqual(server.pointers.map(\.mask), [1, 0])
        XCTAssertEqual(session.client.state, .connected)
        let replacement = MacNativeInputView(frame: .zero)
        replacement.onKeyEvent = { session.sendNativeKey(down: $0, keySym: $1) }
        let up = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f702}",
            charactersIgnoringModifiers: "\u{f702}", isARepeat: false, keyCode: 123))
        replacement.keyUp(with: up)
        let returnDown = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        let returnUp = try XCTUnwrap(NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        replacement.keyDown(with: returnDown)
        replacement.keyUp(with: returnUp)
        waitUntil { server.keys.count == 4 }
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.arrowLeft, MacKeyMap.arrowLeft, MacKeyMap.return, MacKeyMap.return])
        XCTAssertEqual(server.keys.map(\.down), [true, false, true, false])
        XCTAssertEqual(session.client.state, .connected)
    }
    @MainActor
    func testReentrantNativeCleanupReleasesWirePointerOnceBeforeTransportReset() throws {
        let ready = expectation(description: "Native reentrant cleanup loopback ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Native reentrant cleanup QA", host: "127.0.0.1",
            port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.startSession()
        waitUntil { session.sessionState == .connected && session.client.state == .connected }
        let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        view.remoteSize = CGSize(width: 16, height: 16)
        view.onPointerEvent = { session.sendNativePointer(buttonMask: $0, x: $1, y: $2) }
        var resetCalls = 0
        view.onInputReset = { resetCalls += 1; session.resetNativePointerInput() }
        view.onKeyEvent = { [weak view] down, key in
            session.sendNativeKey(down: down, keySym: key)
            if !down, let view { MacNativeInputRepresentable.dismantleNSView(view, coordinator: ()) }
        }
        let down = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{f702}",
            charactersIgnoringModifiers: "\u{f702}", isARepeat: false, keyCode: 123))
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        view.keyDown(with: down)
        view.mouseDown(with: mouse)
        waitUntil { server.keys.count == 1 && server.pointers.count == 1 }
        XCTAssertTrue(view.resignFirstResponder())
        session.sendNativeKey(down: true, keySym: MacKeyMap.return)
        session.sendNativeKey(down: false, keySym: MacKeyMap.return)
        waitUntil { server.keys.count == 4 }
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.arrowLeft, MacKeyMap.arrowLeft, MacKeyMap.return, MacKeyMap.return])
        XCTAssertEqual(server.keys.map(\.down), [true, false, true, false])
        XCTAssertEqual(server.pointers.map(\.mask), [1, 0])
        XCTAssertEqual(resetCalls, 1)
        XCTAssertEqual(session.client.state, .connected)
    }

    @MainActor
    func testNativeViewCleanupCancelsQueuedWheelsAndKeepsSessionReusable() throws {
        for dismantle in [false, true] {
            let ready = expectation(description: "Native wheel lifecycle loopback ready")
            let server = try PointerWireServer(ready: { ready.fulfill() })
            defer { server.stop() }
            wait(for: [ready], timeout: 3)
            let session = TestSession.make(device: RemoteDevice(name: "Native wheel cleanup QA", host: "127.0.0.1",
                port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
            defer { session.endSession() }
            session.startSession()
            waitUntil { session.sessionState == .connected && session.client.state == .connected }
            let view = MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            view.remoteSize = CGSize(width: 16, height: 16)
            view.onPointerEvent = { session.sendNativePointer(buttonMask: $0, x: $1, y: $2) }
            view.onKeyEvent = { session.sendNativeKey(down: $0, keySym: $1) }
            view.onInputReset = { session.resetNativePointerInput() }
            let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            view.mouseDown(with: mouse)
            waitUntil { server.pointers.count == 1 }
            let cgWheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                wheel1: 64, wheel2: 0, wheel3: 0))
            let wheel = try XCTUnwrap(NSEvent(cgEvent: cgWheel))
            view.scrollWheel(with: wheel)
            waitUntil { server.pointers.contains { $0.mask & 0x78 != 0 } }
            XCTAssertLessThan(server.pointers.filter { $0.mask & 0x78 != 0 }.count, 64,
                "Cleanup must run while real transport wheel work remains queued")
            if dismantle { MacNativeInputRepresentable.dismantleNSView(view, coordinator: ()) }
            else { XCTAssertTrue(view.resignFirstResponder()) }
            // A balanced key round trip is a TCP ordering barrier after cleanup.
            session.sendNativeKey(down: true, keySym: MacKeyMap.return)
            session.sendNativeKey(down: false, keySym: MacKeyMap.return)
            waitUntil { server.keys.count == 2 }
            XCTAssertEqual(server.pointers.last?.mask, 0)
            let settledCount = server.pointers.count
            let lateWorkWindow = expectation(description: "Observe previously scheduled wheel deadlines")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { lateWorkWindow.fulfill() }
            wait(for: [lateWorkWindow], timeout: 2)
            XCTAssertEqual(server.pointers.count, settledCount, "Old queued wheels must stay cancelled")
            XCTAssertEqual(session.client.state, .connected)
            let replacement = dismantle ? MacNativeInputView(frame: CGRect(x: 0, y: 0, width: 100, height: 100)) : view
            replacement.remoteSize = CGSize(width: 16, height: 16)
            replacement.onPointerEvent = { session.sendNativePointer(buttonMask: $0, x: $1, y: $2) }
            replacement.mouseDown(with: mouse)
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 50, y: 50),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 0))
            replacement.mouseUp(with: up)
            waitUntil { server.pointers.count == settledCount + 2 }
            XCTAssertEqual(Array(server.pointers.suffix(2)).map(\.mask), [1, 0])
            XCTAssertEqual(server.keys.map(\.down), [true, false])
            XCTAssertEqual(session.client.state, .connected)
        }
    }
    #endif

    private func connectedPair(banner: String = "RFB 003.008\n") throws -> (PointerWireServer, RFBClient) {
        let ready = expectation(description: "Loopback listener ready")
        let connected = expectation(description: "RFB handshake completed")
        let server = try PointerWireServer(banner: banner, ready: { ready.fulfill() })
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        if banner == "RFB 003.008\n" { XCTAssertTrue(server.viewerInfos.isEmpty) }
        return (server, client)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ predicate: @escaping () -> Bool) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed, file: file, line: line)
    }
}

// Keep the genuine suspended-read/session-change scenarios in Swift Testing.
// XCTest's legacy async invocation repeatedly crashes on this VM in
// XCTSwiftErrorObservation/swift_task_localValuePopImpl before reporting results.
@Suite(.serialized)
@MainActor
struct ClipboardSessionTestsAsync {
    @Test
    func testAsyncClipboardPasteRevalidatesSelectionObserveAndChangedContent() async throws {
        for mode in ["paste", "observe", "hidden", "changed"] {
            let evidence = AsyncClipboardEvidence()
            let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { evidence.markReady() })
            defer { server.stop() }
            try await waitFor("Listener ready") { evidence.isReady }
            let gate = ClipboardReadGate()
            let port = try #require(server.listener.port)
            let session = TestSession.make(device: RemoteDevice(name: "Async clipboard QA", host: "127.0.0.1", port: port.rawValue), password: nil, isTemporary: true,
                clipboardAsyncReader: { await gate.read(onReady: { evidence.markReading() }) },
                clipboardCountReader: { gate.count })
            defer { session.endSession() }
            session.startSession()
            try await waitFor("Connected model and transport") {
                session.sessionState == .connected && session.client.state == .connected
            }
            server.onAppleClipboard = { evidence.record($0) }
            session.syncClipboardToMac()
            try await waitFor("Actual suspended clipboard read installed", timeout: .seconds(2)) { evidence.isReading }
            if mode == "observe" { session.isObserveOnly = true }
            if mode == "hidden" { session.setForegroundSession(false) }
            if mode == "changed" { gate.count += 1 }
            gate.finish([.init(type: "public.utf8-plain-text", data: Data("async paste 中文🙂".utf8))])
            if mode == "paste" {
                try await waitFor("Actual clipboard packet received", timeout: .seconds(2)) { !evidence.packets.isEmpty }
                let packets = evidence.packets
                #expect(packets.count == 1)
                let packet = try #require(packets.first)
                try #require(packet.count >= 16)
                let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                #expect(ApplePasteboard.decodeText(Data(packet.dropFirst(16)), uncompressedBytes: size) == "async paste 中文🙂")
            } else {
                // Preserve the former inverted expectation's observation window.
                try await Task.sleep(for: .milliseconds(200))
                #expect(evidence.packets.isEmpty)
                #expect(server.keys.isEmpty)
            }
            if mode == "changed" { #expect(session.clipboardPasteError == "Clipboard changed. Try again.") }
        }
    }

    private func waitFor(_ description: String, timeout: Duration = .seconds(3),
                         _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "\(description)")
    }
}

// Yield the main actor while the genuine biometric continuation and retry timer run.
@Suite(.serialized)
@MainActor
struct UserPasswordSessionTestsAsync {
    @Test
    func testUserPasswordRejectsLateAuthenticationAndChangedTargets() async throws {
        let evidence = AsyncClipboardEvidence()
        let server = try PointerWireServer(ready: { evidence.markReady() })
        defer { server.stop() }
        try await waitFor("Listener ready") { evidence.isReady }
        let suite = "test.aetherscreens.password-stale.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let device = RemoteDevice(name: "Late password QA", host: "127.0.0.1", port: try #require(server.listener.port).rawValue,
            authMethod: .macAccount, username: "fixture-account", sharedClipboard: false)
        store.addDevice(device)
        var authentication: CheckedContinuation<Bool, Never>?
        var reads = 0
        let session = TestSession.make(device: device, password: nil, deviceStore: store,
            userPasswordReader: { _ in reads += 1; return "synthetic-only" },
            userPasswordAuthentication: { await withCheckedContinuation { authentication = $0 } })
        defer { session.endSession() }
        // This fixture tests post-authentication command transport, not ARD.
        // Establish its None-auth socket, then supply its synthetic account identity.
        session.client.username = nil
        session.startSession()
        try await waitFor("Connected model and transport") {
            session.sessionState == .connected && session.client.state == .connected
        }
        session.client.username = "fixture-account"
        #expect(session.canTypeUserPassword, "The initial saved account must be eligible")
        session.typeUserPassword()
        try await waitFor("Authentication continuation installed") { authentication != nil }
        session.setForegroundSession(false)
        authentication?.resume(returning: true); authentication = nil
        #expect(!session.isTypingUserPassword)
        session.setForegroundSession(true)
        #expect(session.canTypeUserPassword, "Reselection must allow a fresh authentication request")
        session.typeUserPassword()
        try await waitFor("Authentication continuation installed") { authentication != nil }
        var edited = device; edited.username = "different-account"
        store.updateDevice(edited, password: nil)
        authentication?.resume(returning: true); authentication = nil
        try await waitFor("Changed target rejected and request completed") { !session.isTypingUserPassword }
        try await Task.sleep(for: .milliseconds(200))
        #expect(reads == 0)
        #expect(server.keys.isEmpty)
        #expect(!session.canTypeUserPassword)
        #expect(session.userPasswordError != nil)
        store.deleteDevice(device)
        #expect(!session.canTypeUserPassword)
        let temporary = TestSession.make(device: device, password: nil, isTemporary: true, deviceStore: store)
        #expect(!temporary.canTypeUserPassword)
    }

    @Test
    func testApplicationBackgroundCancelsPendingUserPasswordAuthentication() async throws {
        let evidence = AsyncClipboardEvidence()
        let server = try PointerWireServer(ready: { evidence.markReady() })
        defer { server.stop() }
        try await waitFor("Application password listener ready") { evidence.isReady }
        let suite = "test.aetherscreens.application-password.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let device = RemoteDevice(name: "Application password QA", host: "127.0.0.1",
            port: try #require(server.listener.port).rawValue, authMethod: .macAccount,
            username: "fixture-account", sharedClipboard: false)
        var authentication: CheckedContinuation<Bool, Never>?
        defer { authentication?.resume(returning: false) }
        var authenticationReturned = false
        var reads = 0
        let session = TestSession.make(device: device, password: nil, isTemporary: true,
            deviceStore: store, keyboardStore: KeyboardToolbarStore(defaults: defaults),
            userPasswordReader: { _ in reads += 1; return "QA" },
            userPasswordAuthentication: {
                let allowed = await withCheckedContinuation { authentication = $0 }
                authenticationReturned = true
                return allowed
            })
        defer { session.endSession() }
        // This is a synthetic post-authentication account, not ARD or a real credential.
        session.client.username = nil
        session.setApplicationInputActive(true)
        session.setClipboardApplicationActive(true)
        session.startSession()
        try await waitFor("Application password model and transport connected") {
            session.sessionState == .connected && session.client.state == .connected
        }
        session.client.username = "fixture-account"
        #expect(session.canTypeUserPassword)
        session.typeUserPassword()
        try await waitFor("Application password authentication suspended") { authentication != nil }
        session.setApplicationInputActive(false)
        #expect(!session.isTypingUserPassword, "Real background must cancel the pending password request")
        #expect(!session.canTypeUserPassword)
        authentication?.resume(returning: true)
        authentication = nil
        // Immediate activation must not revive the old authentication result.
        session.setApplicationInputActive(true)
        try await waitFor("Late background authentication returned") { authenticationReturned }
        session.sendTextString("M")
        try await waitFor("Foreground marker received on TCP") {
            server.keys.contains { $0.key == 77 && !$0.down }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(reads == 0)
        #expect(!session.isTypingUserPassword)
        #expect(server.keys.map(\.key) == [77, 77], "Only the fresh foreground marker may reach TCP")
        #expect(server.keys.map(\.down) == [true, false])
    }

    @Test
    func testTemporaryInactivePreservesPendingUserPasswordAuthentication() async throws {
        let evidence = AsyncClipboardEvidence()
        let server = try PointerWireServer(ready: { evidence.markReady() })
        defer { server.stop() }
        try await waitFor("Temporary inactive listener ready") { evidence.isReady }
        let suite = "test.aetherscreens.temporary-inactive-password.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestStorage.make(userDefaults: defaults, legacySources: [])
        let device = RemoteDevice(name: "Temporary inactive password QA", host: "127.0.0.1",
            port: try #require(server.listener.port).rawValue, authMethod: .macAccount,
            username: "fixture-account", sharedClipboard: false)
        var authentication: CheckedContinuation<Bool, Never>?
        defer { authentication?.resume(returning: false) }
        var authenticationReturned = false
        var reads = 0
        let session = TestSession.make(device: device, password: nil, isTemporary: true,
            deviceStore: store, keyboardStore: KeyboardToolbarStore(defaults: defaults),
            userPasswordReader: { _ in reads += 1; return "QA" },
            userPasswordAuthentication: {
                let allowed = await withCheckedContinuation { authentication = $0 }
                authenticationReturned = true
                return allowed
            })
        defer { session.endSession() }
        session.client.username = nil
        session.setApplicationInputActive(true)
        session.setClipboardApplicationActive(true)
        session.startSession()
        try await waitFor("Temporary inactive model and transport connected") {
            session.sessionState == .connected && session.client.state == .connected
        }
        session.client.username = "fixture-account"
        session.typeUserPassword()
        try await waitFor("Temporary inactive authentication suspended") { authentication != nil }
        // Model only willResignActive's clipboard path. No OS biometric UI is invoked.
        session.setClipboardApplicationActive(false)
        #expect(session.client.state == .connected && session.sessionState == .connected)
        #expect(server.closedInput == nil, "Temporary inactivity must leave the actual socket open")
        #expect(session.isTypingUserPassword, "Temporary inactivity must preserve the authentication request")
        authentication?.resume(returning: true)
        authentication = nil
        try await waitFor("Authentication returned while temporarily inactive") { authenticationReturned }
        #expect(session.isTypingUserPassword)
        #expect(reads == 0)
        #expect(server.keys.isEmpty, "The completed result must wait until activity returns")
        session.setClipboardApplicationActive(true)
        try await waitFor("Synthetic password transaction received after activity returns") {
            !session.isTypingUserPassword && server.keys.count == 6
        }
        #expect(reads == 1)
        #expect(server.keys.map(\.key) == [81, 81, 65, 65, MacKeyMap.return, MacKeyMap.return])
        #expect(server.keys.map(\.down) == [true, false, true, false, true, false])
        #expect(session.userPasswordError == nil)
        #expect(session.client.state == .connected && session.sessionState == .connected)
        #expect(server.closedInput == nil, "Local authentication must not take the background-close path")
    }

    private func waitFor(_ description: String, timeout: Duration = .seconds(3),
                         _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "\(description)")
    }
}

private final class AsyncClipboardEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var reading = false
    private var received: [Data] = []
    var isReady: Bool { lock.lock(); defer { lock.unlock() }; return ready }
    var isReading: Bool { lock.lock(); defer { lock.unlock() }; return reading }
    var packets: [Data] { lock.lock(); defer { lock.unlock() }; return received }
    func markReady() { lock.lock(); defer { lock.unlock() }; ready = true }
    func markReading() { lock.lock(); defer { lock.unlock() }; reading = true }
    func record(_ packet: Data) { lock.lock(); defer { lock.unlock() }; received.append(packet) }
}

@MainActor
final class ClipboardSessionTests: XCTestCase {
    func testSharedClipboardAutomaticUploadNoEchoAndManualOffObserveBackgroundGates() throws {
        let ready = expectation(description: "Shared clipboard listener")
        let connected = expectation(description: "Shared clipboard connection")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = TestSession.make(device: RemoteDevice(name: "Shared clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true,
            clipboardWriter: { _ in XCTFail("Typed content must retain all flavors") },
            clipboardFlavorsWriter: { items in
                inbox.flavors.append(items); inbox.localFlavors = items; inbox.localChangeCount += 1
                inbox.onReceived?()
            },
            clipboardReader: { inbox.reads += 1; return inbox.localFlavors },
            clipboardCountReader: { inbox.localChangeCount })
        defer { session.endSession() }
        let originalStateCallback = session.client.onStateChanged
        session.client.onStateChanged = { state in
            originalStateCallback?(state)
            if state == .connected { connected.fulfill() }
        }
        session.startSession()
        wait(for: [connected], timeout: 3)
        drainCallbacks()
        XCTAssertTrue(session.sharedClipboardEnabled)
        XCTAssertEqual(inbox.reads, 0, "Connection reads change metadata without reading clipboard bytes")
        let local: [RFBClipboardFlavor] = [.init(type: "public.utf8-plain-text", data: Data("local中".utf8))]
        let automatic = expectation(description: "Local copy automatically uploaded without paste")
        server.onAppleClipboard = { packet in
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeItems(Data(packet.dropFirst(16)), uncompressedBytes: size), local)
            automatic.fulfill()
        }
        inbox.localFlavors = local; inbox.localChangeCount += 1
        wait(for: [automatic], timeout: 3)
        XCTAssertTrue(server.keys.isEmpty)
        let noEcho = expectation(description: "Remote clipboard update must not echo back")
        noEcho.isInverted = true
        server.onAppleClipboard = { _ in noEcho.fulfill() }
        let remote: [RFBClipboardFlavor] = [.init(type: "public.png", data: Data([0, 255, 128]))]
        let received = expectation(description: "Remote update reaches writer")
        inbox.onReceived = { received.fulfill() }
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeItems(remote)))
        wait(for: [received], timeout: 3)
        wait(for: [noEcho], timeout: 0.65)
        XCTAssertEqual(inbox.flavors, [remote])
        session.setSharedClipboard(false)
        let previousReads = inbox.reads
        inbox.localFlavors = local; inbox.localChangeCount += 1
        session.pollLocalClipboardChanges()
        session.client.onClipboardFlavorsReceived?(remote)
        drainCallbacks()
        XCTAssertEqual(inbox.reads, previousReads)
        XCTAssertEqual(inbox.flavors.count, 1)
        let manual = expectation(description: "Manual Send works with sharing off")
        server.onAppleClipboard = { _ in manual.fulfill() }
        session.sendLocalClipboard()
        wait(for: [manual], timeout: 3)
        XCTAssertTrue(server.keys.isEmpty, "Send Clipboard must not issue Cmd-V")
        let fetched = expectation(description: "Manual Get applies exactly one reply with sharing off")
        inbox.onReceived = { fetched.fulfill() }
        let requests = server.appleRequests
        session.getRemoteClipboard()
        let requested = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.appleRequests > requests }, object: nil)
        wait(for: [requested], timeout: 3)
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeItems(remote)))
        wait(for: [fetched], timeout: 3)
        session.client.onClipboardFlavorsReceived?(remote)
        drainCallbacks()
        XCTAssertEqual(inbox.flavors.count, 2)
        session.isObserveOnly = true
        server.onAppleClipboard = { _ in XCTFail("Observe must block manual upload") }
        session.sendLocalClipboard()
        session.pollLocalClipboardChanges()
        XCTAssertFalse(session.canSendClipboard)
        XCTAssertTrue(session.canGetClipboard)
        session.setForegroundSession(false)
        let hiddenFetches = server.appleFetches
        session.getRemoteClipboard()
        session.sendLocalClipboard()
        session.client.onClipboardFlavorsReceived?(remote)
        drainCallbacks()
        XCTAssertEqual(server.appleFetches, hiddenFetches)
        XCTAssertEqual(inbox.flavors.count, 2)
        session.setForegroundSession(true)
        session.isObserveOnly = false
        session.setClipboardApplicationActive(false)
        let backgroundReads = inbox.reads
        session.getRemoteClipboard()
        session.sendLocalClipboard()
        session.syncClipboardToMac()
        session.pasteClipboardText("Background paste must be suppressed")
        XCTAssertEqual(inbox.reads, backgroundReads, "Background paste must not read the local clipboard")
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertFalse(session.canGetClipboard)
        XCTAssertFalse(session.canSendClipboard)
        session.isObserveOnly = false
        session.setSharedClipboard(true)
        let resumed = expectation(description: "Copy from another app uploads on foreground resume")
        let copiedElsewhere: [RFBClipboardFlavor] = [.init(type: "public.url", data: Data("https://example.com/copied-elsewhere".utf8))]
        inbox.localFlavors = copiedElsewhere
        inbox.localChangeCount += 1
        server.onAppleClipboard = { packet in
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeItems(Data(packet.dropFirst(16)), uncompressedBytes: size), copiedElsewhere)
            resumed.fulfill()
        }
        session.setClipboardApplicationActive(true)
        wait(for: [resumed], timeout: 3)
        XCTAssertTrue(server.keys.isEmpty)
        session.setSharedClipboard(false)
        server.onAppleClipboard = nil
    }

    func testTypedSessionDeliveryPasteAndForegroundObserveGates() throws {
        let ready = expectation(description: "Typed session listener")
        let connected = expectation(description: "Typed session connected")
        let received = expectation(description: "Typed clipboard delivered to platform writer")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let items: [RFBClipboardFlavor] = [.init(type: "public.png", data: Data([0, 255, 128]))]
        let session = TestSession.make(device: RemoteDevice(name: "Typed clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true,
            clipboardWriter: { _ in XCTFail("Typed Apple delivery must not overwrite rich content with text") },
            clipboardFlavorsWriter: { flavors in inbox.flavors.append(flavors); received.fulfill() })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeItems(items)))
        wait(for: [received], timeout: 3)
        XCTAssertEqual(inbox.flavors, [items])
        session.setForegroundSession(false)
        session.client.onClipboardFlavorsReceived?(items)
        session.setForegroundSession(true)
        drainCallbacks()
        XCTAssertEqual(inbox.flavors.count, 1, "Hidden-generation content cannot arrive after selection")
        let upload = expectation(description: "Typed content queued before paste shortcut")
        server.onAppleClipboard = { packet in
            XCTAssertTrue(server.keys.isEmpty)
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeItems(Data(packet.dropFirst(16)), uncompressedBytes: size), items)
            upload.fulfill()
        }
        session.pasteClipboardFlavors(items)
        wait(for: [upload], timeout: 3)
        let keys = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.keys.count == 4 }, object: nil)
        wait(for: [keys], timeout: 3)
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, 118, 118, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, true, false, false])
        session.isObserveOnly = true
        server.onAppleClipboard = { _ in XCTFail("Observe cannot upload rich content") }
        let oldKeys = server.keys.count
        session.pasteClipboardFlavors(items)
        drainCallbacks()
        XCTAssertEqual(server.keys.count, oldKeys)
        XCTAssertNil(session.clipboardPasteError)
        server.onAppleClipboard = nil
    }

    func testOversizedClipboardDoesNotSendKeysAndNextApplePasteRecovers() throws {
        let ready = expectation(description: "Bounded paste listener ready")
        let connected = expectation(description: "Bounded paste connected")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Bounded paste QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let forbidden = expectation(description: "Oversized paste emits input")
        forbidden.isInverted = true
        server.onKey = { _ in forbidden.fulfill() }
        server.onAppleClipboard = { _ in forbidden.fulfill() }
        session.pasteClipboardFlavors([.init(type: "public.utf8-plain-text", data: Data(String(repeating: "中", count: ApplePasteboard.maximumTextBytes / 3 + 1).utf8))])
        XCTAssertEqual(session.clipboardPasteError, "Clipboard text is too large. Copy a smaller selection and try again.")
        session.pasteClipboardText(String(repeating: "中", count: ApplePasteboard.maximumTextBytes / 3 + 1))
        XCTAssertEqual(session.clipboardPasteError, "Clipboard text is too large. Copy a smaller selection and try again.")
        wait(for: [forbidden], timeout: 0.15)
        XCTAssertTrue(server.keys.isEmpty)
        XCTAssertEqual(session.client.state, .connected)
        server.onKey = nil
        let uploaded = expectation(description: "Next supported paste received")
        server.onAppleClipboard = { packet in
            let size = Int(packet[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(ApplePasteboard.decodeText(Data(packet.dropFirst(16)), uncompressedBytes: size), "恢复粘贴🙂")
            uploaded.fulfill()
        }
        session.pasteClipboardText("恢复粘贴🙂")
        XCTAssertNil(session.clipboardPasteError)
        wait(for: [uploaded], timeout: 2)
        let keys = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.keys.count == 4 }, object: nil)
        wait(for: [keys], timeout: 2)
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, 118, 118, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, true, false, false])
        server.onAppleClipboard = nil
    }

    @MainActor
    func testQueuedHandshakeStatePreservesCurrentClipboardAndConnectedUI() throws {
        let ready = expectation(description: "Clipboard startup listener ready")
        let received = expectation(description: "Current clipboard survives queued handshake UI work")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = TestSession.make(device: RemoteDevice(name: "Clipboard startup QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true,
            clipboardFlavorsWriter: { items in inbox.flavors.append(items); received.fulfill() })
        defer { session.endSession() }
        session.startSession()
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            session.client.state == .connected && session.sessionState == .connected
        }, object: nil)
        wait(for: [connected], timeout: 3)
        // Reproduce the gap between a wire notification and its queued MainActor
        // UI update: the latest clipboard arrives before older UI work drains.
        session.client.onStateChanged?(.connecting)
        let items = [RFBClipboardFlavor(type: "public.utf8-plain-text", data: Data("startup 中文🙂".utf8))]
        session.client.onClipboardFlavorsReceived?(items)
        wait(for: [received], timeout: 2)
        XCTAssertEqual(inbox.flavors, [items])
        XCTAssertEqual(session.sessionState, .connected, "A queued obsolete state must not replace current connected UI")
    }

    func testAppleSessionSelectionFetchesCurrentClipboardWithoutReregisteringMonitor() throws {
        let ready = expectation(description: "Apple selection listener ready")
        let connected = expectation(description: "Apple selection connected")
        let restored = expectation(description: "Current selected clipboard delivered")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = TestSession.make(device: RemoteDevice(name: "Apple selection QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: {
            inbox.texts.append($0)
            if $0 == "后台复制🙂𠮷" { restored.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let initial = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.appleRequests == 2 }, object: nil)
        wait(for: [initial], timeout: 2)
        session.setForegroundSession(false)
        session.client.onClipboardReceived?("discarded hidden copy")
        drainCallbacks()
        XCTAssertTrue(inbox.texts.isEmpty)
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.appleMonitorSelectors == [1, 2] }, object: nil)
        wait(for: [stopped], timeout: 2)
        XCTAssertEqual(server.appleFetches, 1)
        session.setForegroundSession(true)
        let fetched = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.appleFetches == 2 }, object: nil)
        wait(for: [fetched], timeout: 2)
        server.sendFragmented(try XCTUnwrap(ApplePasteboard.encodeText("后台复制🙂𠮷")))
        wait(for: [restored], timeout: 2)
        XCTAssertEqual(inbox.texts, ["后台复制🙂𠮷"])
        session.setForegroundSession(true)
        drainCallbacks()
        XCTAssertEqual(server.appleFetches, 2, "Selection must fetch once after rearming monitoring")
        XCTAssertEqual(server.appleMonitorSelectors, [1, 2, 1])
        XCTAssertEqual(server.viewerInfos.count, 1)
    }

    func testApplePasteActionUsesClipboardShortcutAndHiddenOrObserveSessionsRejectIt() throws {
        let ready = expectation(description: "Apple paste listener ready")
        let connected = expectation(description: "Apple paste session ready")
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = TestSession.make(device: RemoteDevice(name: "Apple paste QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        let uploaded = expectation(description: "Paste action uploads archive")
        server.onAppleClipboard = { _ in uploaded.fulfill() }
        session.pasteClipboardText("应用按钮🙂")
        wait(for: [uploaded], timeout: 2)
        let keys = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.keys.count == 4 }, object: nil)
        wait(for: [keys], timeout: 2)
        XCTAssertEqual(server.keys.map(\.key), [MacKeyMap.commandLeft, 118, 118, MacKeyMap.commandLeft])
        XCTAssertEqual(server.keys.map(\.down), [true, true, false, false])
        let forbidden = expectation(description: "Hidden or Observe session uploads clipboard")
        forbidden.isInverted = true
        server.onAppleClipboard = { _ in forbidden.fulfill() }
        session.isObserveOnly = true
        session.pasteClipboardText("Observe")
        session.setForegroundSession(false)
        session.isObserveOnly = false
        session.pasteClipboardText("hidden")
        wait(for: [forbidden], timeout: 0.15)
        XCTAssertEqual(server.keys.count, 4)
        server.onAppleClipboard = nil
    }

    func testHiddenSessionRejectsInputAndClipboardUntilSelectedAgain() throws {
        let ready = expectation(description: "Hidden session listener ready")
        let connected = expectation(description: "Hidden session connected")
        let resumed = expectation(description: "Foreground clipboard delivered")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = TestSession.make(device: RemoteDevice(name: "Background QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: {
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
        let session = TestSession.make(device: RemoteDevice(name: "Clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
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
        let session = TestSession.make(device: RemoteDevice(name: "Reconnect clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
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
        let session = TestSession.make(device: RemoteDevice(name: "Extended clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "远端 😀\nsecond line" { downloaded.fulfill() }
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
        XCTAssertTrue(session.client.sendCutText("客户端 中文 😀\nsecond line\n"))
        wait(for: [uploaded], timeout: 2)
        let remotePayload = try ClipboardWireData.compress("远端 😀\r\nsecond line")
        session.isObserveOnly = true
        server.onExtendedClipboard = { flags, _ in
            if flags == 0x10000001 { forbidden.fulfill() }
            if flags == 0x02000001 { server.sendExtendedClipboard(flags: 0x10000001, payload: remotePayload) }
        }
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
        let session = TestSession.make(device: RemoteDevice(name: "Malformed clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
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
        let session = TestSession.make(device: RemoteDevice(name: "Unterminated clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
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
private final class ClipboardReadGate {
    var count = 0
    private var continuation: CheckedContinuation<[RFBClipboardFlavor]?, Never>?
    func read(onReady: () -> Void) async -> [RFBClipboardFlavor]? {
        await withCheckedContinuation {
            continuation = $0
            onReady()
        }
    }
    func finish(_ items: [RFBClipboardFlavor]) {
        continuation?.resume(returning: items)
        continuation = nil
    }
}

@MainActor
private final class ClipboardInbox {
    var texts: [String] = []
    var flavors: [[RFBClipboardFlavor]] = []
    var localFlavors: [RFBClipboardFlavor] = []
    var localChangeCount = 0
    var reads = 0
    var onReceived: (() -> Void)?
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
@Suite(.serialized)
@MainActor
struct InputDiagnosticsTCPTests {
    @Test func evidenceFollowsRealPointerAndReturnSendsWithoutRecordingTextOrClipboard() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.json")
        let recorder = InputDiagnostics(fileURL: file)
        let evidence = AsyncClipboardEvidence()
        let server = try PointerWireServer(banner: "RFB 003.889\n", ready: { evidence.markReady() })
        defer { server.stop() }
        try await waitUntil("listener ready") { evidence.isReady }
        #expect(try #require(server.listener.port).rawValue > 0)
        let client = RFBClient(host: "127.0.0.1", port: try #require(server.listener.port).rawValue,
                               password: "synthetic-auth-secret-qa", automaticClipboard: false,
                               connectionTimeoutInterval: 20, inputDiagnostics: recorder)
        defer { client.disconnect() }
        client.connect()
        try await waitUntil("client connected") { client.state == .connected }
        let text = "synthetic-secret-qa"
        client.sendText(text)
        #expect(client.sendCutText("synthetic-clipboard-qa"))
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.return)
        client.sendPointerEvent(buttonMask: .left, x: 9, y: 10)
        client.sendPointerEvent(buttonMask: [], x: 9, y: 10)
        try await waitUntil("pointer and Return received and sends processed") {
            server.keys.count == text.count * 2 + 2 && server.pointers.count == 2 &&
            recorder.snapshot.records.filter { $0.stage == .returnProcessed }.count == 2 &&
            recorder.snapshot.records.filter { $0.stage == .pointerProcessed }.count == 2
        }
        #expect(server.keys.suffix(2).map(\.key) == [0xFF0D, 0xFF0D])
        #expect(server.pointers.map(\.mask) == [1, 0])
        client.setInputEnabled(false)
        client.sendPointerEvent(buttonMask: .left, x: 9, y: 10)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        await recorder.flush()
        let bytes = try Data(contentsOf: file)
        let snapshot = try JSONDecoder().decode(InputDiagnostics.Snapshot.self, from: bytes)
        #expect(snapshot.records.contains { $0.stage == .pointerSuppressed && $0.flags & 1 == 0 })
        #expect(snapshot.records.contains { $0.stage == .returnSuppressed && $0.flags & 1 == 0 })
        let json = try #require(String(data: bytes, encoding: .utf8))
        for privateValue in [text, "synthetic-clipboard-qa", "synthetic-auth-secret-qa", "127.0.0.1"] {
            #expect(!json.contains(privateValue))
        }
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == ["schema", "records"])
        let records = try #require(object["records"] as? [[String: Any]])
        let allowed: Set<String> = ["sequence", "uptime", "session", "stage", "flags", "buttons", "down", "appleFlags", "appleCommand"]
        #expect(records.allSatisfy { Set($0.keys).isSubset(of: allowed) })
    }

    @Test func missingConnectionIsDistinguishedFromLocalSuppression() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = InputDiagnostics(fileURL: directory.appendingPathComponent("input.json"))
        let client = RFBClient(host: "unused-qa.invalid", automaticClipboard: false,
                               connectionTimeoutInterval: 20, inputDiagnostics: recorder)
        defer { client.disconnect() }
        client.sendPointerEvent(buttonMask: .left, x: 1, y: 1)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.return)
        #expect(recorder.snapshot.records.contains { $0.stage == .pointerDropped && $0.flags & 4 == 0 })
        #expect(recorder.snapshot.records.contains { $0.stage == .returnDropped && $0.flags & 4 == 0 })
        #expect(!recorder.snapshot.records.contains { $0.stage == .pointerProcessed || $0.stage == .returnProcessed })
    }

    private func waitUntil(_ phase: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(predicate(), Comment(rawValue: phase))
        guard predicate() else { throw NSError(domain: "InputDiagnosticsTCPTimeout:" + phase, code: 1) }
    }
}

private final class RefreshReconnectFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var first = true
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard first else { return false }
        first = false
        return true
    }
}

private final class PointerWireServer: @unchecked Sendable {
    enum FramebufferBehavior { case noResponses, pushAndPoll, pollOnly, empty }
    struct Pointer { let mask: UInt8; let x: UInt16; let y: UInt16 }
    struct Key { let down: Bool; let key: UInt32 }
    struct ClosedInput { let cleanEOF: Bool; let pointers: [Pointer]; let keys: [Key] }
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.pointer-wire-qa")
    private let lock = NSLock()
    private var received: [Pointer] = []
    private var receivedKeys: [Key] = []
    private var closedInputSnapshot: ClosedInput?
    var closedInput: ClosedInput? { lock.lock(); defer { lock.unlock() }; return closedInputSnapshot }
    private var connection: NWConnection?
    private let framebufferBehavior: FramebufferBehavior
    // Accessed on the fixture's connection queue only. The interval word is not a display ID.
    private var automaticFramesEnabled = false
    private var pendingFrameRequest = false
    private var dirtyFrame = false
    private var modeledPixel: UInt8 = 1
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
    private var extendedClipboardHandler: ((UInt32, Data) -> Void)?
    private var appleClipboardHandler: ((Data) -> Void)?
    private var receivedAppleRequests = 0
    private var receivedAppleFetches = 0
    private var receivedAppleMonitorSelectors: [UInt8] = []
    private var receivedViewerInfos: [Data] = []
    private var receivedAutomaticFrameRequests: [Data] = []
    private var receivedUpdateRequests: [Data] = []
    var automaticFrameRequests: [Data] { lock.lock(); defer { lock.unlock() }; return receivedAutomaticFrameRequests }
    var updateRequests: [Data] { lock.lock(); defer { lock.unlock() }; return receivedUpdateRequests }
    var viewerInfos: [Data] { lock.lock(); defer { lock.unlock() }; return receivedViewerInfos }
    var appleFetches: Int { lock.lock(); defer { lock.unlock() }; return receivedAppleFetches }
    var appleMonitorSelectors: [UInt8] { lock.lock(); defer { lock.unlock() }; return receivedAppleMonitorSelectors }
    var appleRequests: Int { lock.lock(); defer { lock.unlock() }; return receivedAppleRequests }
    var onAppleClipboard: ((Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return appleClipboardHandler }
        set { lock.lock(); appleClipboardHandler = newValue; lock.unlock() }
    }
    var onExtendedClipboard: ((UInt32, Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return extendedClipboardHandler }
        set { lock.lock(); extendedClipboardHandler = newValue; lock.unlock() }
    }
    var keys: [Key] { lock.lock(); defer { lock.unlock() }; return receivedKeys }
    var pointers: [Pointer] { lock.lock(); defer { lock.unlock() }; return received }
    private var acceptedConnections = 0
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return acceptedConnections }

    init(banner: String = "RFB 003.008\n", framebufferBehavior: FramebufferBehavior = .noResponses,
         ready: @escaping () -> Void) throws {
        self.framebufferBehavior = framebufferBehavior
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock(); self.acceptedConnections += 1; self.lock.unlock()
            self.connection = connection
            self.automaticFramesEnabled = false
            self.pendingFrameRequest = false
            self.dirtyFrame = false
            self.modeledPixel = 1
            connection.start(queue: self.queue)
            self.send(Data(banner.utf8))
            self.read(12) { _ in
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
    func stop() { onPointer = nil; onKey = nil; onCutText = nil; onExtendedClipboard = nil; onAppleClipboard = nil; connection?.cancel(); listener.cancel() }
    func sendRaw(_ data: Data) { send(data) }
    func changeDesktop() { queue.async { self.changeModeledFrame() } }
    func sendFragmented(_ data: Data) {
        for byte in data { send(Data([byte])) }
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
    private func sendModeledFrame() {
        pendingFrameRequest = false
        dirtyFrame = false
        if framebufferBehavior == .empty { send(Data([0, 0, 0, 0])); return }
        send(Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0,
                   modeledPixel, 0, 0, 255]))
    }
    private func changeModeledFrame() {
        guard framebufferBehavior == .pushAndPoll || framebufferBehavior == .pollOnly else { return }
        modeledPixel &+= 1
        dirtyFrame = true
        if pendingFrameRequest || (automaticFramesEnabled && framebufferBehavior == .pushAndPoll) {
            sendModeledFrame()
        }
    }
    private func read(_ count: Int, accumulated: Data = Data(), done: @escaping (Data) -> Void) {
        if accumulated.count == count { done(accumulated); return }
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, finished, error in
            guard let self, self.connection === connection else { return }
            guard error == nil, let data, !data.isEmpty else {
                if finished || error != nil {
                    self.lock.lock()
                    if self.closedInputSnapshot == nil {
                        self.closedInputSnapshot = ClosedInput(cleanEOF: finished && error == nil,
                                                              pointers: self.received, keys: self.receivedKeys)
                    }
                    self.lock.unlock()
                }
                return
            }
            let next = accumulated + data
            if next.count == count { done(next) }
            else if !finished { self.read(count, accumulated: next, done: done) }
        }
    }
    private func readMessage() {
        read(1) { [weak self] type in
            guard let self else { return }
            switch type[0] {
            case 0x21:
                self.read(3) { header in
                    let length = Int(header[1]) << 8 | Int(header[2])
                    guard length <= 1024 else { XCTFail("Unexpected ViewerInfo size"); return }
                    self.read(length) { body in
                        self.lock.lock(); self.receivedViewerInfos.append(Data([0x21]) + header + body); self.lock.unlock()
                        self.readMessage()
                    }
                }
            case 0x0B, 0x15:
                self.read(7) { payload in
                    self.lock.lock()
                    self.receivedAppleRequests += 1
                    if type[0] == 0x0B { self.receivedAppleFetches += 1 }
                    else { self.receivedAppleMonitorSelectors.append(payload[2]) }
                    self.lock.unlock()
                    self.readMessage()
                }
            case 0x1F:
                self.read(15) { header in
                    let length = Int(header[11..<15].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
                    guard length <= 16_777_216 else { XCTFail("Unexpected Apple archive size"); return }
                    self.read(length) { payload in
                        self.onAppleClipboard?(Data([0x1F]) + header + payload)
                        self.readMessage()
                    }
                }
            case 0: self.read(19) { _ in self.readMessage() }
            case 2:
                self.read(3) { header in
                    let count = Int(header[1]) << 8 | Int(header[2])
                    self.read(count * 4) { _ in self.readMessage() }
                }
            case 3: self.read(9) { payload in
                self.lock.lock(); self.receivedUpdateRequests.append(Data([3]) + payload); self.lock.unlock()
                if self.framebufferBehavior != .noResponses {
                    self.pendingFrameRequest = true
                    if payload[0] == 0 || self.dirtyFrame || self.framebufferBehavior == .empty {
                        self.sendModeledFrame()
                    }
                }
                self.readMessage()
            }
            case 9: self.read(15) { payload in
                self.lock.lock(); self.receivedAutomaticFrameRequests.append(Data([9]) + payload); self.lock.unlock()
                let interval = payload[3..<7].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                self.automaticFramesEnabled = interval != UInt32.max
                self.readMessage()
            }
            case 4:
                self.read(7) { body in
                    let key = Key(down: body[0] != 0, key: UInt32(body[3]) << 24 | UInt32(body[4]) << 16 | UInt32(body[5]) << 8 | UInt32(body[6]))
                    self.lock.lock(); self.receivedKeys.append(key); self.lock.unlock()
                    self.onKey?(key)
                    if key.down && key.key == MacKeyMap.return { self.changeModeledFrame() }
                    self.readMessage()
                }
            case 5:
                self.read(5) { body in
                    let pointer = Pointer(mask: body[0], x: UInt16(body[1]) << 8 | UInt16(body[2]), y: UInt16(body[3]) << 8 | UInt16(body[4]))
                    self.lock.lock(); self.received.append(pointer); self.lock.unlock()
                    self.onPointer?(pointer)
                    if pointer.mask & 1 != 0 { self.changeModeledFrame() }
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
