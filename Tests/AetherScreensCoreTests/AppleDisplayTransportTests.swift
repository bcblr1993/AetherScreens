import XCTest
import Network
@testable import AetherScreensCore

final class AppleDisplayTransportTests: XCTestCase {
    func testImageCapabilitiesDistinguishClientDecoderGapFromAppleServerScaling() throws {
        let disconnected = RFBClient(host: "qa.invalid")
        XCTAssertEqual(disconnected.imageQualityCapabilities.progressiveAdaptiveQuality, .notConnected)
        XCTAssertFalse(disconnected.imageQualityCapabilities.supportsServerScaling)

        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.imageQualityCapabilities.supportsServerScaling)
        XCTAssertEqual(client.imageQualityCapabilities.progressiveAdaptiveQuality, .clientDecoderUnavailable)
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5)
        server.pixels()
        waitUntil { counters.scaleFinishes == [true] }
        XCTAssertEqual(client.framebuffer.width, 8)
        XCTAssertEqual(client.imageQualityCapabilities.progressiveAdaptiveQuality, .clientDecoderUnavailable,
                       "A confirmed half-size image is compression, not evidence of progressive refinement")
        client.disconnect()
        XCTAssertEqual(client.imageQualityCapabilities.progressiveAdaptiveQuality, .notConnected)
        XCTAssertFalse(client.imageQualityCapabilities.supportsServerScaling)
    }

    func testAppleNegotiationDoesNotAdvertiseUnimplementedImageCodecs() throws {
        let (server, client, _) = try connection()
        defer { client.disconnect(); server.stop() }
        let unimplemented: [Int32] = [1000, 1001, 1002, 1011]
        for encoding in unimplemented {
            XCTAssertFalse(server.encodings.contains(encoding),
                           "IANA registration alone cannot enable a client decoder for \(encoding)")
        }
        XCTAssertTrue(server.encodings.contains(16))
        XCTAssertTrue(server.encodings.contains(6))
        XCTAssertTrue(server.encodings.contains(0))
    }

    func testUnexpectedAppleImageCodecFailsWithoutGuessingPayloadFraming() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        let previousFrames = counters.frames
        server.unimplementedImageRectangle()
        waitUntil { client.state == .failed("Unsupported framebuffer encoding: 1011") }
        XCTAssertEqual(counters.frames, previousFrames, "Unknown image bytes must not be published as a frame")
        XCTAssertEqual(client.imageQualityCapabilities.progressiveAdaptiveQuality, .notConnected)
    }

    func testAppleNegotiationRequestsBothNativeDisplayReports() throws {
        let ready = expectation(description: "Native layout fixture ready")
        let server = try AppleDisplayWireServer { ready.fulfill() }
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
                               automaticClipboard: false, automaticFramebufferUpdates: true)
        defer { client.disconnect() }
        client.connect()
        waitUntil { !server.encodings.isEmpty }
        XCTAssertTrue(server.encodings.contains(0x44D), "DisplayInfo is required to make an Apple server report its monitors")
        XCTAssertTrue(server.encodings.contains(0x451), "AppleDisplayLayout selects the modern layout payload")
    }

    private func connection(apple: Bool = true, automatic: Bool = true, timeout: TimeInterval = 10, diagnostics: InputDiagnostics? = nil) throws -> (AppleDisplayWireServer, RFBClient, AppleDisplayCounters) {
        let ready = expectation(description: "Display fixture listening")
        let server = try AppleDisplayWireServer(apple: apple) { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue,
            automaticClipboard: false, automaticFramebufferUpdates: automatic, connectionTimeoutInterval: 20,
            inputDiagnostics: diagnostics, appleDisplaySelectionTimeoutInterval: timeout)
        let counters = AppleDisplayCounters()
        client.onFrameUpdated = { counters.frame() }
        client.onAppleDisplaySelectionFinished = { _, confirmed in counters.finish(confirmed) }
        client.onAppleServerScalingFinished = { _, confirmed in counters.scale(confirmed) }
        client.connect()
        waitUntil { counters.frames >= 1 }
        return (server, client, counters)
    }

    func testGenericServerDoesNotReceivePrivateDisplayEncodings() throws {
        let (server, client, _) = try connection(apple: false)
        defer { client.disconnect(); server.stop() }
        XCTAssertFalse(server.encodings.contains(0x44D))
        XCTAssertFalse(server.encodings.contains(0x451))
        XCTAssertFalse(client.selectAppleDisplay(id: 0))
        XCTAssertNil(client.currentAppleDisplayLayout)
    }

    func testFragmentedNativeLayoutAndLegacyMetadataKeepStreamAligned() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertEqual(client.currentAppleDisplayLayout?.screens.map(\.id), [0, 22])
        XCTAssertEqual(client.framebuffer.width, 16)
        server.legacyInfoThenPixels()
        server.bell()
        server.pixels()
        waitUntil { counters.frames >= 3 }
        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(client.framebuffer.width, 16)
    }

    func testSelectionReleasesHeldButtonAndWaitsForLayoutThenPixels() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        waitUntil { server.pointers.count == 1 }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        waitUntil { server.selections.count == 1 && server.pointers.count == 2 }
        XCTAssertEqual(server.pointers.map { $0[1] }, [1, 0])
        XCTAssertEqual(server.selections.first, Data([13, 0, 0, 0, 0, 0, 0, 22]))
        let oldFrames = counters.frames
        server.layout(selected: 22)
        waitUntil { client.currentAppleDisplayLayout?.selectedDisplayID == 22 }
        XCTAssertEqual(counters.frames, oldFrames, "Metadata is not a new visible desktop")
        XCTAssertTrue(counters.finishes.isEmpty)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        server.pixels()
        waitUntil { counters.finishes == [true] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 3)
        waitUntil { server.pointers.count == 4 }
        XCTAssertEqual(server.pointers.suffix(2).map { $0[1] }, [1, 0])
        XCTAssertEqual(Array(try XCTUnwrap(server.pointers.last)), [5, 0, 0, 4, 0, 3])
        XCTAssertEqual(client.framebuffer.width, 8)
    }

    func testPollingOnlyLayoutRequestsFullRepaintAfterEntireMessage() throws {
        let (server, client, _) = try connection(automatic: false)
        defer { client.disconnect(); server.stop() }
        let before = server.updateRequests.count
        server.layout(selected: 22)
        waitUntil { server.updateRequests.count > before }
        XCTAssertEqual(server.updateRequests.last?[1], 0)
        XCTAssertEqual(Array(try XCTUnwrap(server.updateRequests.last).suffix(4)), [0, 8, 0, 8])
        XCTAssertTrue(server.automaticRequests.isEmpty)
    }

    func testNativeLayoutRearmsPushAndRequestsFullRepaintWithoutIncrementalOverride() throws {
        let (server, client, _) = try connection()
        defer { client.disconnect(); server.stop() }
        // The initial pull timer may still be queued; let it complete before the
        // next layout, then prove layout cancels any replacement timer.
        let initial = server.automaticRequests.count
        server.layout(selected: 22)
        waitUntil { server.automaticRequests.count > initial }
        let packet = try XCTUnwrap(server.automaticRequests.last)
        XCTAssertEqual(Array(packet.suffix(4)), [0, 8, 0, 8])
        XCTAssertEqual(server.updateRequests.last?[1], 0)
    }

    func testUnknownIDIsRejectedAndAllDisplayFlagIsDistinctFromZero() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertFalse(client.selectAppleDisplay(id: 99))
        XCTAssertTrue(server.selections.isEmpty)
        XCTAssertTrue(client.selectAppleDisplay(id: 0))
        waitUntil { server.selections.count == 1 }
        XCTAssertEqual(server.selections.last, Data([13, 0, 0, 0, 0, 0, 0, 0]))
        server.layout(selected: 0); server.pixels()
        waitUntil { counters.finishes == [true] }
        XCTAssertTrue(client.selectAppleDisplay(id: nil))
        waitUntil { server.selections.count == 2 }
        XCTAssertEqual(server.selections.last, Data([13, 1, 0, 0, 0, 0, 0, 0]))
        server.layout(); server.pixels()
        waitUntil { counters.finishes == [true, true] }
        XCTAssertNil(client.currentAppleDisplayLayout?.selectedDisplayID)
    }

    func testConfirmedScaleAndSelectedOriginTranslateClickExactlyOnce() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        var screens = AppleDisplayTestPayload.screens
        screens[1].density = 2; screens[1].scale = 0.5
        screens[1].backing.origin.x = 100
        server.layout(selected: 22, screens: screens); server.pixels()
        waitUntil { counters.finishes == [true] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(Array(server.pointers[0]), [5, 1, 0, 8, 0, 6])
        XCTAssertEqual(Array(server.pointers[1]), [5, 0, 0, 8, 0, 6])
    }

    func testObserveCanSwitchViewButCannotSendClick() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        client.setInputEnabled(false)
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.layout(selected: 22); server.pixels()
        waitUntil { counters.finishes == [true] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 3)
        XCTAssertTrue(server.pointers.isEmpty)
        XCTAssertEqual(client.currentAppleDisplayLayout?.selectedDisplayID, 22)
    }

    func testUnansweredSelectionTimesOutAndRestoresPreviousInputGeometry() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        waitUntil { counters.finishes == [false] }
        XCTAssertNil(client.currentAppleDisplayLayout?.selectedDisplayID)
        client.sendPointerEvent(buttonMask: .left, x: 12, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 12, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(Array(server.pointers[0]), [5, 1, 0, 12, 0, 3])
    }

    func testAcknowledgementWithoutPixelsStaysInputGatedAfterTimeout() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.layout(selected: 22)
        waitUntil { counters.finishes == [false] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        XCTAssertTrue(server.pointers.isEmpty)
        server.pixels()
        waitUntil { counters.frames >= 2 }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 3)
        waitUntil { server.pointers.count == 2 }
    }

    func testLatestRapidSelectionWinsOverEarlierLayout() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 0))
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.layout(selected: 0); server.pixels()
        waitUntil { counters.frames >= 2 }
        XCTAssertTrue(counters.finishes.isEmpty)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        XCTAssertTrue(server.pointers.isEmpty)
        server.layout(selected: 22); server.pixels()
        waitUntil { counters.finishes == [true] }
        XCTAssertEqual(client.currentAppleDisplayLayout?.selectedDisplayID, 22)
    }

    func testMalformedNativeLengthFailsWithoutTreatingPayloadAsPixels() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        server.layout(malformedLength: 4097)
        waitUntil { if case .failed = client.state { return true }; return false }
        XCTAssertEqual(counters.frames, 1)
        XCTAssertNil(client.currentAppleDisplayLayout)
    }

    func testOldSelectionTimeoutCannotChangeReconnectedSession() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        client.disconnect()
        client.connect()
        waitUntil { counters.frames >= 2 }
        XCTAssertTrue(counters.finishes.isEmpty)
        XCTAssertNil(client.currentAppleDisplayLayout?.selectedDisplayID)
        client.sendPointerEvent(buttonMask: .left, x: 12, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 12, y: 3)
        waitUntil { server.pointers.count >= 2 }
        XCTAssertEqual(Array(try XCTUnwrap(server.pointers.last)), [5, 0, 0, 12, 0, 3])
    }

    func testCombinedGapReleasesDragAtLastValidPosition() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        var screens = AppleDisplayTestPayload.screens
        screens[1].backing.origin.x = 4
        server.layout(screens: screens, width: 20); server.pixels()
        waitUntil { counters.frames >= 2 }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: .left, x: 9, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 9, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(Array(server.pointers[0]), [5, 1, 0, 4, 0, 3])
        XCTAssertEqual(Array(server.pointers[1]), [5, 0, 0, 4, 0, 3])
    }

    func testWrongAcknowledgementWithoutPixelsCannotUngateInputOnTimeout() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.layout(selected: 0)
        waitUntil { counters.finishes == [false] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        XCTAssertTrue(server.pointers.isEmpty)
        server.pixels()
        waitUntil { counters.frames >= 2 }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(Array(server.pointers[0]), [5, 1, 0, 4, 0, 3])
    }

    func testDisplayDiagnosticsRecordOnlyStagesAndPendingFlag() throws {
        let recorder = InputDiagnostics(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let (server, client, counters) = try connection(diagnostics: recorder)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        server.layout(selected: 22); server.pixels()
        waitUntil { counters.finishes == [true] }
        let records = recorder.snapshot.records
        XCTAssertTrue(records.contains { $0.stage == .appleDisplayLayoutReceived })
        XCTAssertTrue(records.contains { $0.stage == .appleDisplaySelectionRequested && $0.flags & 1024 != 0 })
        XCTAssertTrue(records.contains { $0.stage == .pointerSuppressed && $0.flags & 1024 != 0 })
        XCTAssertTrue(records.contains { $0.stage == .appleDisplaySelectionConfirmed && $0.flags & 1024 == 0 })
        XCTAssertTrue(records.filter { $0.stage == .appleDisplayLayoutReceived }.allSatisfy {
            $0.buttons == nil && $0.down == nil && $0.appleFlags == nil && $0.appleCommand == nil
        })
    }

    @MainActor
    private func sessionConnection(preferred: UInt32? = nil) throws -> (AppleDisplayWireServer, SessionViewModel) {
        let ready = expectation(description: "Session native fixture ready")
        let server = try AppleDisplayWireServer { ready.fulfill() }
        wait(for: [ready], timeout: 3)
        var device = RemoteDevice(name: "Native display QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        device.preferredDisplayID = preferred
        let session = TestSession.make(device: device, password: nil, isTemporary: true)
        session.startSession()
        waitUntil { session.hasReceivedFirstFrame && session.multiDisplayManager.availableDisplays.count == 3 }
        return (server, session)
    }

    @MainActor
    func testActualSessionNativeMenuSwitchKeepsFramebufferLocalCoordinates() throws {
        let (server, session) = try sessionConnection()
        defer { session.endSession(); server.stop() }
        XCTAssertEqual(session.multiDisplayManager.availableDisplays.map(\.name), ["All Displays", "Display 1", "Display 2"])
        session.selectDisplay(id: 23)
        waitUntil { server.selections.count == 1 }
        XCTAssertEqual(session.multiDisplayManager.selectedDisplayId, 0)
        XCTAssertEqual(session.multiDisplayManager.pendingDisplayId, 23)
        server.layout(selected: 22); server.pixels()
        waitUntil { session.multiDisplayManager.pendingDisplayId == nil && session.multiDisplayManager.selectedDisplayId == 23 }
        XCTAssertNil(session.activeCropRect)
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 8)
        session.trackpadEngine.moveCursor(to: CGPoint(x: 4, y: 3))
        session.trackpadEngine.click(button: .left)
        waitUntil { server.pointers.contains { $0[1] == 1 } }
        XCTAssertEqual(Array(try XCTUnwrap(server.pointers.first { $0[1] == 1 })), [5, 1, 0, 4, 0, 3])
        session.selectDisplay(id: 0)
        server.layout(); server.pixels()
        waitUntil { session.multiDisplayManager.pendingDisplayId == nil && session.multiDisplayManager.selectedDisplayId == 0 }
        XCTAssertNil(session.activeCropRect)
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 16)
        XCTAssertNil(session.displaySelectionError)
    }

    private func halfSizeScreens() -> [AppleDisplayTestPayload.Screen] {
        AppleDisplayTestPayload.screens.map {
            var screen = $0
            screen.scale = 0.5
            screen.backing = CGRect(x: screen.backing.minX / 2, y: screen.backing.minY / 2,
                                    width: screen.backing.width / 2, height: screen.backing.height / 2)
            return screen
        }
    }

    @MainActor
    func testActualSessionCompressionPreservesZoomPanAndPointerAcrossBothResolutions() throws {
        let (server, session) = try sessionConnection()
        defer { session.endSession(); server.stop() }
        session.trackpadEngine.moveCursor(to: CGPoint(x: 12, y: 2))
        session.zoomScale = 2.25; session.viewOffset = CGSize(width: -30, height: 12)
        session.isPanningViewport = true
        session.setImageCompression(.always)
        waitUntil { server.scalings.count == 1 }
        XCTAssertEqual(session.pendingImageScale, 0.5)
        server.layout(screens: halfSizeScreens(), width: 8, height: 4)
        server.pixels()
        waitUntil { session.pendingImageScale == nil && session.trackpadEngine.remoteWidth == 8 }
        XCTAssertEqual(session.trackpadEngine.remoteHeight, 4)
        XCTAssertEqual(session.trackpadEngine.cursorX, 6); XCTAssertEqual(session.trackpadEngine.cursorY, 1)
        XCTAssertEqual(session.zoomScale, 2.25)
        XCTAssertEqual(session.viewOffset, CGSize(width: -30, height: 12))
        XCTAssertTrue(session.isPanningViewport)
        XCTAssertEqual(session.multiDisplayManager.availableDisplays.count, 3)
        session.isPanningViewport = false
        session.trackpadEngine.click(button: .left)
        waitUntil { server.pointers.contains { $0[1] == 1 } }
        XCTAssertEqual(server.pointers.first { $0[1] == 1 }, Data([5, 1, 0, 12, 0, 2]))
        session.setImageCompression(.never)
        waitUntil { server.scalings.count == 2 }
        server.layout(); server.pixels()
        waitUntil { session.pendingImageScale == nil && session.trackpadEngine.remoteWidth == 16 }
        XCTAssertEqual(session.trackpadEngine.cursorX, 12); XCTAssertEqual(session.trackpadEngine.cursorY, 2)
        XCTAssertEqual(session.zoomScale, 2.25)
        XCTAssertEqual(session.viewOffset, CGSize(width: -30, height: 12))
        XCTAssertNil(session.imageCompressionError)
    }

    @MainActor
    func testActualSessionCompressionOnDisplayTwoKeepsSelectionAndBalancedClick() throws {
        let (server, session) = try sessionConnection()
        defer { session.endSession(); server.stop() }
        session.selectDisplay(id: 23)
        server.layout(selected: 22); server.pixels()
        waitUntil { session.multiDisplayManager.pendingDisplayId == nil && session.trackpadEngine.remoteWidth == 8 }
        session.setImageCompression(.always)
        waitUntil { server.scalings.count == 1 }
        server.layout(selected: 22, screens: halfSizeScreens(), width: 4, height: 4); server.pixels()
        waitUntil { session.pendingImageScale == nil && session.trackpadEngine.remoteWidth == 4 }
        XCTAssertEqual(session.multiDisplayManager.selectedDisplayId, 23)
        XCTAssertNil(session.activeCropRect)
        session.trackpadEngine.moveCursor(to: CGPoint(x: 3, y: 1))
        session.trackpadEngine.click(button: .left)
        waitUntil { server.pointers.contains { $0[1] == 1 } }
        XCTAssertEqual(server.pointers.suffix(2), [Data([5, 1, 0, 6, 0, 2]), Data([5, 0, 0, 6, 0, 2])])
    }

    @MainActor
    func testActualLoopbackRouteKeepsRemoteOnlyUncompressedAndNeverSendsDuplicateScaling() throws {
        let (server, session) = try sessionConnection()
        defer { session.endSession(); server.stop() }
        XCTAssertEqual(session.client.isLocalConnection, true)
        session.setImageCompression(.remoteOnly)
        XCTAssertTrue(server.scalings.isEmpty)
        session.setImageCompression(.never)
        server.pixels()
        waitUntil { session.hasReceivedFirstFrame }
        XCTAssertTrue(server.scalings.isEmpty)
        XCTAssertNil(session.pendingImageScale)
    }

    @MainActor
    func testActualSessionRestoresPreferenceOnlyAfterNativeReportAndPreservesChoice() throws {
        let (server, session) = try sessionConnection(preferred: 22)
        defer { session.endSession(); server.stop() }
        waitUntil { server.selections.count == 1 }
        XCTAssertEqual(session.multiDisplayManager.selectedDisplayId, 0)
        server.layout(selected: 22); server.pixels()
        waitUntil { session.multiDisplayManager.selectedDisplayId == 23 && session.multiDisplayManager.pendingDisplayId == nil }
        XCTAssertNil(session.activeCropRect)
        XCTAssertEqual(session.trackpadEngine.remoteWidth, 8)
        session.selectDisplay(id: 999)
        XCTAssertEqual(session.multiDisplayManager.selectedDisplayId, 23)
        XCTAssertEqual(server.selections.count, 1)
    }

    func testPixelsBeforeLayoutCannotConfirmSelectionOrExposeClearedFrame() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.oldPixelsThenLayout(selected: 22)
        waitUntil { client.currentAppleDisplayLayout?.selectedDisplayID == 22 }
        XCTAssertEqual(counters.frames, 1)
        XCTAssertTrue(counters.finishes.isEmpty)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        XCTAssertTrue(server.pointers.isEmpty)
        server.pixels()
        waitUntil { counters.finishes == [true] }
    }

    func testLayoutObserverReconnectDoesNotReuseOldReaderOrSelection() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        let callbackCount = AppleDisplayCounters()
        client.onAppleDisplayLayoutReceived = { _ in
            if callbackCount.frames == 0 {
                callbackCount.frame()
                client.disconnect()
                client.connect()
            }
        }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        server.layout(selected: 22)
        waitUntil { counters.frames >= 2 }
        XCTAssertEqual(callbackCount.frames, 1)
        XCTAssertTrue(counters.finishes.isEmpty)
        XCTAssertNil(client.currentAppleDisplayLayout?.selectedDisplayID)
        XCTAssertEqual(client.framebuffer.width, 16)
        client.sendPointerEvent(buttonMask: .left, x: 12, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 12, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(Array(server.pointers[0]), [5, 1, 0, 12, 0, 3])
    }

    func testAlreadyConfirmedDisplayCompletesWithoutSendingAnotherSelection() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.selectAppleDisplay(id: nil))
        XCTAssertEqual(counters.finishes, [true], "A confirmed current view must finish a menu request immediately")
        XCTAssertTrue(server.selections.isEmpty, "No redundant server switch is needed")
        XCTAssertEqual(counters.frames, 1)
    }

    @MainActor
    func testActualSessionAlreadyConfirmedChoiceClearsPendingMenuState() throws {
        let (server, session) = try sessionConnection()
        defer { session.endSession(); server.stop() }
        session.selectDisplay(id: 23)
        server.layout(selected: 22); server.pixels()
        waitUntil { session.multiDisplayManager.selectedDisplayId == 23 && session.multiDisplayManager.pendingDisplayId == nil }
        let current = try XCTUnwrap(session.client.currentAppleDisplayLayout)
        // Represent a UI layout publication still in flight while the transport
        // already has the confirmed screen's pixels. Use the actual callback.
        session.multiDisplayManager.updateFromAppleLayout(try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body())))
        session.client.onAppleDisplayLayoutReceived?(current)
        session.selectDisplay(id: 23)
        waitUntil { session.multiDisplayManager.selectedDisplayId == 23 && session.multiDisplayManager.pendingDisplayId == nil }
        XCTAssertEqual(server.selections.count, 1)
        XCTAssertNil(session.displaySelectionError)
    }

    private func scaledLayout(_ server: AppleDisplayWireServer, factor: Double, selected: UInt32? = nil) {
        let screens = AppleDisplayTestPayload.screens.map { screen in
            var copy = screen
            copy.scale = factor
            copy.backing = CGRect(x: screen.backing.minX * factor, y: screen.backing.minY * factor,
                                  width: screen.backing.width * factor, height: screen.backing.height * factor)
            return copy
        }
        server.layout(selected: selected, screens: screens,
                      width: UInt16((selected == nil ? 16 : 8) * factor), height: UInt16(8 * factor))
    }

    func testScalingRejectsInvalidOrGenericRequestsWithoutPrivatePackets() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        for factor in [0, -1, 1.1, Double.nan, Double.infinity, 0.00001] {
            XCTAssertFalse(client.setAppleServerScaling(factor))
        }
        XCTAssertTrue(server.scalings.isEmpty)
        XCTAssertTrue(counters.scaleFinishes.isEmpty)
        let (generic, genericClient, _) = try connection(apple: false)
        defer { genericClient.disconnect(); generic.stop() }
        XCTAssertFalse(genericClient.setAppleServerScaling(0.5))
        XCTAssertTrue(generic.scalings.isEmpty)
    }

    func testScalingReleasesHeldButtonAndOldFramesDoNotConfirmHalfSize() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        waitUntil { server.pointers.count == 1 }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        waitUntil { server.scalings.count == 1 && server.pointers.count == 2 }
        XCTAssertEqual(server.pointers.map { $0[1] }, [1, 0])
        XCTAssertEqual(server.scalings[0], Data([8, 0, 0x3F, 0xE0, 0, 0, 0, 0, 0, 0]))
        server.pixels()
        waitUntil { counters.frames == 2 }
        XCTAssertTrue(counters.scaleFinishes.isEmpty)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 3)
        XCTAssertEqual(server.pointers.count, 2)
        scaledLayout(server, factor: 0.5)
        server.pixels()
        waitUntil { counters.scaleFinishes == [true] }
    }

    func testHalfLayoutNeedsFreshPixelsBeforeClicksUseUnscaledCoordinates() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5)
        waitUntil { client.currentAppleDisplayLayout?.width == 8 }
        XCTAssertTrue(counters.scaleFinishes.isEmpty)
        XCTAssertEqual(counters.frames, 1)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 2)
        XCTAssertTrue(server.pointers.isEmpty)
        server.pixels()
        waitUntil { counters.scaleFinishes == [true] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 2)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 2)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(server.pointers[0], Data([5, 1, 0, 8, 0, 4]))
        XCTAssertEqual(server.pointers[1], Data([5, 0, 0, 8, 0, 4]))
        XCTAssertEqual(client.framebuffer.height, 4)
    }

    func testUnansweredScalingRestoresPreviousInputAfterTimeout() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        waitUntil { counters.scaleFinishes == [false] }
        XCTAssertEqual(client.currentAppleDisplayLayout?.width, 16)
        client.sendPointerEvent(buttonMask: .left, x: 12, y: 3)
        client.sendPointerEvent(buttonMask: [], x: 12, y: 3)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(server.pointers[0], Data([5, 1, 0, 12, 0, 3]))
    }

    func testScalingAcknowledgementWithoutPixelsKeepsInputGatedAfterTimeout() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5)
        waitUntil { counters.scaleFinishes == [false] }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 2)
        XCTAssertTrue(server.pointers.isEmpty)
        XCTAssertFalse(client.setAppleServerScaling(1))
        server.pixels()
        waitUntil { counters.frames == 2 }
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 2)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 2)
        waitUntil { server.pointers.count == 2 }
        XCTAssertEqual(server.pointers[0], Data([5, 1, 0, 8, 0, 4]))
    }

    func testScalingAndDisplaySelectionAreSerialized() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        XCTAssertFalse(client.selectAppleDisplay(id: 22))
        XCTAssertFalse(client.setAppleServerScaling(1))
        scaledLayout(server, factor: 0.5); server.pixels()
        waitUntil { counters.scaleFinishes == [true] }
        XCTAssertTrue(client.selectAppleDisplay(id: 22))
        XCTAssertFalse(client.setAppleServerScaling(1))
        scaledLayout(server, factor: 0.5, selected: 22)
        XCTAssertFalse(client.setAppleServerScaling(1))
        server.pixels()
        waitUntil { counters.finishes == [true] }
        XCTAssertTrue(client.setAppleServerScaling(1))
        scaledLayout(server, factor: 1, selected: 22); server.pixels()
        waitUntil { counters.scaleFinishes == [true, true] }
        XCTAssertEqual(client.framebuffer.width, 8)
        XCTAssertEqual(server.selections.count, 1)
    }

    func testAlreadyConfirmedScalingFinishesWithoutAnotherWireRequest() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(1))
        XCTAssertEqual(counters.scaleFinishes, [true])
        XCTAssertTrue(server.scalings.isEmpty)
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5); server.pixels()
        waitUntil { counters.scaleFinishes == [true, true] }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        XCTAssertEqual(counters.scaleFinishes, [true, true, true])
        XCTAssertEqual(server.scalings.count, 1)
    }

    func testOldScalingTimeoutDoesNotChangeReconnectedSession() throws {
        let (server, client, counters) = try connection(timeout: 0.15)
        defer { client.disconnect(); server.stop() }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        client.disconnect(); client.connect()
        waitUntil { counters.frames == 2 }
        let quiet = expectation(description: "Original scaling timeout has expired")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertTrue(counters.scaleFinishes.isEmpty)
        XCTAssertEqual(client.currentAppleDisplayLayout?.screens.first?.serverScale, 1)
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5); server.pixels()
        waitUntil { counters.scaleFinishes == [true] }
    }

    func testScalingCompletionCanReconnectWithoutPublishingAnOldFrame() throws {
        let (server, client, counters) = try connection()
        defer { client.disconnect(); server.stop() }
        client.onAppleServerScalingFinished = { _, success in
            counters.scale(success)
            client.disconnect(); client.connect()
        }
        XCTAssertTrue(client.setAppleServerScaling(0.5))
        scaledLayout(server, factor: 0.5); server.pixels()
        waitUntil { counters.frames == 2 && client.currentAppleDisplayLayout?.width == 16 }
        XCTAssertEqual(counters.scaleFinishes, [true])
        XCTAssertEqual(client.state, .connected)
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line, _ predicate: @escaping () -> Bool) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed, file: file, line: line)
    }
}

private final class AppleDisplayWireServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.apple-display-wire-qa")
    private let lock = NSLock()
    private var connection: NWConnection?
    private var receivedEncodings: [Int32] = []
    private var receivedMessages: [Data] = []
    private var initialized = false
    private var wireWidth: UInt16 = 16
    private var wireHeight: UInt16 = 8
    private let apple: Bool
    var messages: [Data] { lock.lock(); defer { lock.unlock() }; return receivedMessages }
    var pointers: [Data] { messages.filter { $0.first == 5 } }
    var selections: [Data] { messages.filter { $0.first == 13 } }
    var scalings: [Data] { messages.filter { $0.first == 8 } }
    var updateRequests: [Data] { messages.filter { $0.first == 3 } }
    var automaticRequests: [Data] { messages.filter { $0.first == 9 } }
    private func record(_ data: Data) { lock.lock(); receivedMessages.append(data); lock.unlock() }

    func layout(selected: UInt32? = nil, screens: [AppleDisplayTestPayload.Screen] = AppleDisplayTestPayload.screens,
                width: UInt16? = nil, height: UInt16 = 8, malformedLength: UInt16? = nil, fragmented: Bool = false) {
        queue.async {
            let body = AppleDisplayTestPayload.body(selected: selected, screens: screens, width: width, height: height)
            self.wireWidth = width ?? (selected == nil ? 16 : 8)
            self.wireHeight = height
            let packet = Data([0, 0, 0, 1]) + Data(repeating: 0, count: 8) + AppleDisplayTestPayload.be32(0x451) +
                AppleDisplayTestPayload.be16(malformedLength ?? UInt16(body.count)) + body
            if fragmented { for byte in packet { self.send(Data([byte])) } } else { self.send(packet) }
        }
    }
    func pixels() {
        queue.async {
            var packet = Data([0, 0, 0, 1, 0, 0, 0, 0])
            packet += AppleDisplayTestPayload.be16(self.wireWidth) + AppleDisplayTestPayload.be16(self.wireHeight) + Data(repeating: 0, count: 4)
            packet += Data(repeating: 0x5A, count: Int(self.wireWidth) * Int(self.wireHeight) * 4)
            self.send(packet)
        }
    }
    func oldPixelsThenLayout(selected: UInt32) {
        queue.async {
            let body = AppleDisplayTestPayload.body(selected: selected)
            var packet = Data([0, 0, 0, 2, 0, 0, 0, 0, 0, 16, 0, 8, 0, 0, 0, 0])
            packet += Data(repeating: 0xEE, count: 16 * 8 * 4)
            packet += Data(repeating: 0, count: 8) + AppleDisplayTestPayload.be32(0x451)
            packet += AppleDisplayTestPayload.be16(UInt16(body.count)) + body
            self.wireWidth = 8
            self.send(packet)
        }
    }
    func bell() { queue.async { self.send(Data([2])) } }
    func unimplementedImageRectangle() {
        queue.async {
            // Deliberately opaque bytes following an unimplemented rectangle.
            // The client must reject the header, not infer a payload delimiter.
            let packet = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1]) +
                AppleDisplayTestPayload.be32(1011) + Data([0, 0, 0, 8, 0, 0xFF, 0xD8, 0xFF])
            self.send(packet)
        }
    }
    func legacyInfoThenPixels() {
        queue.async {
            var packet = Data([0, 0, 0, 1]) + Data(repeating: 0, count: 8) + AppleDisplayTestPayload.be32(0x44D)
            packet += AppleDisplayTestPayload.be16(16) + AppleDisplayTestPayload.be16(8) + Data(repeating: 0, count: 4) + AppleDisplayTestPayload.be16(2)
            packet += Data(repeating: 0, count: 56)
            self.send(packet)
        }
        pixels()
    }
    var encodings: [Int32] { lock.lock(); defer { lock.unlock() }; return receivedEncodings }

    init(apple: Bool = true, ready: @escaping () -> Void) throws {
        self.apple = apple
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connection = connection
            self.initialized = false
            self.wireWidth = 16
            self.wireHeight = 8
            connection.start(queue: self.queue)
            self.send(Data((self.apple ? "RFB 003.889\n" : "RFB 003.008\n").utf8))
            self.read(12) { reply in
                XCTAssertEqual(reply, Data("RFB 003.008\n".utf8))
                self.send(Data([1, 1]))
                self.read(1) { _ in
                    self.send(Data([0, 0, 0, 0]))
                    self.read(1) { shared in
                        XCTAssertEqual(shared, Data([1]))
                        var initial = Data([0, 16, 0, 8])
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
    func stop() { connection?.cancel(); listener.cancel() }
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
            case 0x0B, 0x15: self.read(7) { _ in self.readMessage() }
            case 0: self.read(19) { _ in self.readMessage() }
            case 2: self.read(3) { header in
                let count = Int(header[1]) << 8 | Int(header[2])
                self.read(count * 4) { body in
                    var encodings: [Int32] = []
                    for offset in stride(from: 0, to: body.count, by: 4) {
                        encodings.append(Int32(bitPattern: body[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }))
                    }
                    self.lock.lock(); self.receivedEncodings = encodings; self.lock.unlock()
                    self.readMessage()
                }
            }
            case 3: self.read(9) { body in
                self.record(type + body)
                if !self.initialized {
                    self.initialized = true
                    if self.apple { self.layout(fragmented: true) }
                    self.pixels()
                }
                self.readMessage()
            }
            case 9: self.read(15) { self.record(type + $0); self.readMessage() }
            case 8: self.read(9) { self.record(type + $0); self.readMessage() }
            case 13: self.read(7) { self.record(type + $0); self.readMessage() }
            case 5: self.read(5) { self.record(type + $0); self.readMessage() }
            case 4: self.read(7) { self.record(type + $0); self.readMessage() }
            case 0x21: self.read(3) { header in
                self.read(Int(header[1]) << 8 | Int(header[2])) { _ in self.readMessage() }
            }
            default: XCTFail("Unexpected message in native display fixture: \(type[0])")
            }
        }
    }
}

private final class AppleDisplayCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var values: [Bool] = []
    private var scales: [Bool] = []
    var frames: Int { lock.lock(); defer { lock.unlock() }; return count }
    var finishes: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
    var scaleFinishes: [Bool] { lock.lock(); defer { lock.unlock() }; return scales }
    func frame() { lock.lock(); count += 1; lock.unlock() }
    func finish(_ value: Bool) { lock.lock(); values.append(value); lock.unlock() }
    func scale(_ value: Bool) { lock.lock(); scales.append(value); lock.unlock() }
}
