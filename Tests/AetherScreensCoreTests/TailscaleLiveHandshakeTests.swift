import XCTest
import Network
@testable import AetherScreensCore

/// Counts transport activity only; no content or credentials are retained.
private final class LiveTransferEvidence: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = 0
    private var receives = 0
    private var first: TimeInterval?
    private var last: TimeInterval?
    private var frameRevision: UInt64?
    private var pixelUpdates = 0
    private var ownedRegionUpdates = 0
    func receive(_ count: Int) {
        guard count > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        bytes += count; receives += 1
        if first == nil { first = now }
        last = now
    }
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        let span = (last ?? 0) - (first ?? 0)
        let idle = last.map { ProcessInfo.processInfo.systemUptime - $0 } ?? -1
        return "bytes \(bytes), receives \(receives), activity span \(span)s, idle \(idle)s (includes handshake/metadata)"
    }
    func frameSummary(_ framebuffer: Framebuffer) -> String {
        lock.lock(); defer { lock.unlock() }
        var regionCount = 0
        var ownedChanged = false
        framebuffer.withPixelChanges(since: frameRevision) { _, width, height, regions, revision in
            regionCount = regions.count
            if width == 3840, height == 2160 {
                let ownedPatch = CGRect(x: 240, y: 1760, width: 720, height: 320)
                ownedChanged = regions.contains { $0.intersects(ownedPatch) }
            }
            frameRevision = revision
        }
        if regionCount > 0 { pixelUpdates += 1 }
        if ownedChanged { ownedRegionUpdates += 1 }
        return "changed regions \(regionCount), pixel updates \(pixelUpdates), owned-region updates \(ownedRegionUpdates), owned changed \(ownedChanged)"
    }
}
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
        try runSavedSession()
    }

    func testLiveAppleRGB565DesktopStability() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_APPLE_RGB565_DESKTOP"] == "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR"] == "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] == "1" else {
            throw XCTSkip("Requires explicit encrypted Apple reduced-color desktop acceptance opt-in")
        }
        try runSavedSession(desktopOnly: true, forcedDepth: .rgb565)
    }

    func testLiveAppleRGB565PatternPush() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_APPLE_PATTERN"] == "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR"] == "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] == "1" else {
            throw XCTSkip("Requires the owned 1920x1080/2x remote pattern and explicit native QA opt-ins")
        }
        try runSavedSession(desktopOnly: true, forcedDepth: .rgb565, validatePattern: true)
    }

    func testLiveStandardRGB565Pattern() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_STANDARD_PATTERN"] == "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR"] != "1",
              env["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] != "1" else {
            throw XCTSkip("Requires owned pattern and explicit ordinary-profile QA without native opt-ins")
        }
        try runSavedSession(desktopOnly: true, forcedDepth: .rgb565, validatePattern: true)
    }

    private func runSavedSession(desktopOnly: Bool = false, forcedDepth: RFBColorDepth? = nil, validatePattern: Bool = false) throws {
        // A QA-owned loopback SSH forward reaches the same saved target. Never
        // allow this credential alias for an arbitrary remote destination.
        let credentialHost = targetHost == "127.0.0.1"
            ? ProcessInfo.processInfo.environment["AETHERSCREENS_LIVE_CREDENTIAL_HOST"] ?? targetHost
            : targetHost
        var dev = DeviceStore.shared.devices.first(where: { $0.host == credentialHost })
        if dev == nil {
            if let appDefaults = UserDefaults(suiteName: "com.aethernative.aetherscreens"),
               let data = appDefaults.data(forKey: DeviceStore.storageKey),
               let devs = try? JSONDecoder().decode([RemoteDevice].self, from: data) {
                dev = devs.first(where: { $0.host == credentialHost })
            }
        }

        let configuredPassword = ProcessInfo.processInfo.environment["AETHERSCREENS_LIVE_PASSWORD"]
        let savedPassword = dev.flatMap { DeviceStore.shared.getPassword(for: $0) }
        guard let pwd = configuredPassword ?? savedPassword, !pwd.isEmpty else {
            throw XCTSkip("Provide AETHERSCREENS_LIVE_PASSWORD or save a password in Keychain for full live acceptance")
        }

        let requestedDepth = ProcessInfo.processInfo.environment["AETHERSCREENS_LIVE_COLOR_DEPTH"]
        guard requestedDepth == nil || requestedDepth == "fullColor" || requestedDepth == "rgb565" else {
            throw XCTSkip("Unsupported explicit live color-depth profile")
        }
        let depth: RFBColorDepth = forcedDepth ?? (requestedDepth == "rgb565" ? .rgb565 : .fullColor)
        let controlProbe = ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CONTROL_MODE"] == "1"
        guard !controlProbe || (ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR"] == "1" &&
            ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] == "1") else {
            throw XCTSkip("Normal-control mode probe requires explicit native cursor/encryption opt-ins")
        }
        print("[TailscaleLiveHandshakeTests] Using supplied or Keychain password for \(targetHost), running live session test...")
        print("Live wire color depth: \(depth.rawValue)")
        let frameExpectation = expectation(description: "Receive at least 1 screen frame from remote Mac")
        frameExpectation.assertForOverFulfill = false
        let connectedExpectation = expectation(description: "Complete live authentication and initialization")
        connectedExpectation.assertForOverFulfill = false

        let cursorProbe = ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR"] == "1"
        let cursorExpectation = cursorProbe && !desktopOnly ? XCTestExpectation(description: "Receive experimental Apple cursor shape") : nil
        cursorExpectation?.assertForOverFulfill = false
        let client = RFBClient(host: targetHost, port: targetPort, password: pwd,
            username: ProcessInfo.processInfo.environment["AETHERSCREENS_LIVE_USERNAME"], colorDepth: depth,
            decodeQueue: DispatchQueue(label: "test.live.cursor.decode"), experimentalAppleCursor: cursorProbe,
            experimentalAppleModernBootstrap: ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR_MODERN"] == "1",
            experimentalAppleEncryption: ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] == "1",
            experimentalAppleLayoutDiagnostic: ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_LAYOUT_DIAGNOSTIC"] == "1",
            experimentalAppleControlMode: controlProbe)
        if ProcessInfo.processInfo.environment["AETHERSCREENS_QA_APPLE_CURSOR_ENCRYPTION"] == "1" {
            print("Native SetMode profile: \(controlProbe ? "normal-control" : "observe"); no keyboard/pointer events sent by this probe")
            client.onAppleStatusReceived = { command in
                print("Native control status command: \(command)")
            }
            client.onNativeUpdateRequested = { incremental in
                print("Native framebuffer request: incremental \(incremental)")
            }
            client.onNativeLayoutPayload = { body in
                let bytes = Array(body.prefix(20))
                let words = stride(from: 0, to: bytes.count - bytes.count % 2, by: 2).map {
                    Int(bytes[$0]) << 8 | Int(bytes[$0 + 1])
                }
                print("Native layout diagnostic: length \(body.count), first leader words \(words)")
            }
            client.onNativePayloadLength = { length in
                print("Native ZRLE compressed payload length: \(length)")
            }
            client.onNativeRectangleReceived = { width, height, encoding in
                print("Native rectangle header: \(width)x\(height), encoding \(encoding)")
            }
            client.onNativeRecordReceived = { type, count in
                print("Native encrypted record verified: first byte \(type ?? -1), bytes \(count)")
            }
        }
        defer { client.disconnect() }
        let acceptanceStarted = ProcessInfo.processInfo.systemUptime
        let transfer = LiveTransferEvidence()
        client.onZRLETiming = { bytes, wait, decode in
            print("Live ZRLE timing: compressed bytes \(bytes), payload wait \(wait)s, CPU decode \(decode)s")
        }
        client.onBytesReceived = { transfer.receive($0) }
        client.onDownloadProgress = { received, total in
            print("Live first-frame transfer: \(received) / \(total) MiB")
        }
        client.onStateChanged = { state in
            print("[TailscaleLiveHandshakeTests] Client state changed: \(state)")
            print("Live phase elapsed: \(state), \(ProcessInfo.processInfo.systemUptime - acceptanceStarted) seconds")
            if state == .connected { connectedExpectation.fulfill() }
            if case .failed = state {
                print("Live transport evidence: \(transfer.summary)")
                connectedExpectation.fulfill()
                frameExpectation.fulfill()
            }
        }
        client.onAppleCursorReceived = { shape in
            print("[TailscaleLiveHandshakeTests] Apple cache cursor verified: \(shape.width)x\(shape.height)")
            cursorExpectation?.fulfill()
        }
        client.onCursorReceived = { shape in
            print("[TailscaleLiveHandshakeTests] Cursor shape: \(shape.width)x\(shape.height), hotspot \(shape.hotspotX),\(shape.hotspotY), hidden \(shape.isHidden)")
        }
        let pattern = validatePattern ? NativePatternAcceptance() : nil
        client.onFrameUpdated = {
            print("Live transport evidence: \(transfer.summary)")
            print("Live decoded pixel evidence: \(transfer.frameSummary(client.framebuffer))")
            if let pattern, pattern.observe(client.framebuffer) {
                print("Owned pattern matched; distinct states \(pattern.distinctCount)")
            }
            print("[TailscaleLiveHandshakeTests] Frame received! Dimensions: \(client.framebuffer.width)x\(client.framebuffer.height), elapsed \(ProcessInfo.processInfo.systemUptime - acceptanceStarted) seconds")
            frameExpectation.fulfill()
        }

        client.connect()
        guard XCTWaiter.wait(for: [connectedExpectation], timeout: 85) == .completed else {
            XCTFail("Live authentication/initialization did not finish within its acceptance window")
            return
        }
        guard client.state == .connected else {
            XCTFail("Live initialization failed: \(client.state)")
            return
        }
        // The app's bounded pixel-transfer deadline starts after initialization.
        // A timed-out waiter must not continue into a false stability acceptance.
        guard XCTWaiter.wait(for: [frameExpectation], timeout: 65) == .completed else {
            XCTFail("No genuine desktop frame within 65 seconds after initialization")
            return
        }
        guard client.state == .connected else {
            XCTFail("Live desktop did not deliver an image while connected: \(client.state)")
            return
        }
        if let cursorExpectation,
           XCTWaiter.wait(for: [cursorExpectation], timeout: 15) != .completed {
            XCTFail("Experimental Apple cursor did not arrive after desktop pixels")
            return
        }
        let stableSession = expectation(description: "Live connection remains active for 60 seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            XCTAssertEqual(client.state, .connected)
            XCTAssertGreaterThan(client.framebuffer.width, 0)
            XCTAssertGreaterThan(client.framebuffer.height, 0)
            if let pattern {
                let progress = pattern.progress(now: ProcessInfo.processInfo.systemUptime)
                XCTAssertGreaterThanOrEqual(progress.states, 3, "Owned pattern must change in received pixels; arbitrary frame callbacks are insufficient")
                XCTAssertGreaterThanOrEqual(progress.span, 30, "Pattern changes must span the observation window")
                XCTAssertLessThan(progress.age, 20, "A frozen matched frame must not count as ongoing delivery")
            }
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
}

// Only samples the expected owned fixture region; no image or user content is saved.
final class NativePatternAcceptance: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures = Set<[UInt8]>()
    private var lastSignature: [UInt8]?
    private var firstChange: TimeInterval?
    private var lastChange: TimeInterval?
    private var transitionCount = 0
    private var totalGap: TimeInterval = 0
    private var maximumGap: TimeInterval = 0
    // Known-pattern arrival cadence; this is not rendered FPS or input latency.
    func progress(now: TimeInterval) -> (states: Int, span: TimeInterval, age: TimeInterval,
                                         transitions: Int, meanGap: TimeInterval, maxGap: TimeInterval,
                                         firstArrival: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        return (signatures.count, (lastChange ?? now) - (firstChange ?? now), now - (lastChange ?? -Double.infinity),
                transitionCount, transitionCount > 0 ? totalGap / Double(transitionCount) : 0, maximumGap, firstChange)
    }
    var distinctCount: Int { lock.lock(); defer { lock.unlock() }; return signatures.count }
    func observe(_ framebuffer: Framebuffer, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard now.isFinite else { return false }
        var signature: [UInt8]?
        framebuffer.withPixelChanges(since: nil) { bytes, width, height, _, _ in
            guard width == 3840, height == 2160 else { return }
            func color(_ x: Int, _ y: Int) -> UInt8 {
                let offset = (y * width + x) * 4
                guard bytes[offset + 3] == 255 else { return 3 }
                let b = Int(bytes[offset]), g = Int(bytes[offset + 1]), r = Int(bytes[offset + 2])
                if max(r, g, b) < 20 { return 0 }
                if r < 100, g > 100, b > 100 { return 1 }
                if r > 160, g > 50, b < 100 { return 2 }
                return 3
            }
            guard color(264, 2056) == 0, color(936, 2056) == 0, color(264, 1784) == 0 else { return }
            let samples = (0..<8).map { color(352 + $0 * 64, 1968) }
            guard samples.contains(1) || samples.contains(2), !samples.contains(3) else { return }
            signature = samples
        }
        guard let signature else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard lastChange.map({ now >= $0 }) ?? true else { return false }
        signatures.insert(signature)
        if lastSignature != signature {
            if let lastChange {
                let gap = now - lastChange
                transitionCount += 1
                totalGap += gap
                maximumGap = max(maximumGap, gap)
            }
            firstChange = firstChange ?? now
            lastChange = now
            lastSignature = signature
        }
        return true
    }
}

final class NativePatternAcceptanceTests: XCTestCase {
    func testKnownOpaquePatternAndDistinctChangesAreRequired() {
        let buffer = Framebuffer()
        buffer.resize(newWidth: 3840, newHeight: 2160)
        let matcher = NativePatternAcceptance()
        XCTAssertFalse(matcher.observe(buffer))
        func put(_ x: Int, _ y: Int, _ color: [UInt8]) {
            buffer.updateRect(x: x, y: y, width: 1, height: 1, rawData: Data(color))
        }
        let black: [UInt8] = [0,0,0,255], teal: [UInt8] = [200,200,0,255]
        for (x,y) in [(264,2056),(936,2056),(264,1784)] { put(x,y,black) }
        for slot in 0..<8 { put(352 + slot * 64,1968,black) }
        XCTAssertFalse(matcher.observe(buffer))
        put(352,1968,[0,255,0,255])
        XCTAssertFalse(matcher.observe(buffer))
        put(352,1968,teal)
        XCTAssertTrue(matcher.observe(buffer, now: 100))
        XCTAssertEqual(matcher.distinctCount,1)
        XCTAssertTrue(matcher.observe(buffer, now: 110))
        XCTAssertEqual(matcher.distinctCount,1)
        put(352,1968,black); put(416,1968,teal)
        XCTAssertTrue(matcher.observe(buffer, now: 120))
        put(416,1968,[0,140,240,255])
        XCTAssertTrue(matcher.observe(buffer, now: 140))
        XCTAssertEqual(matcher.distinctCount,3)
        XCTAssertEqual(matcher.progress(now: 145).span,40)
        XCTAssertEqual(matcher.progress(now: 145).age,5)
        XCTAssertTrue(matcher.observe(buffer, now: 160))
        XCTAssertEqual(matcher.progress(now: 170).age,30)
        XCTAssertEqual(matcher.progress(now: 170).transitions, 2)
        XCTAssertEqual(matcher.progress(now: 170).meanGap, 20)
        XCTAssertEqual(matcher.progress(now: 170).maxGap, 20)
        XCTAssertEqual(matcher.progress(now: 170).firstArrival, 100)
        put(416,1968,teal)
        XCTAssertFalse(matcher.observe(buffer, now: 139))
        XCTAssertFalse(matcher.observe(buffer, now: .infinity))
        XCTAssertTrue(matcher.observe(buffer, now: 170))
        XCTAssertEqual(matcher.progress(now: 175).transitions, 3)
        XCTAssertEqual(matcher.progress(now: 175).meanGap, 70.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(matcher.progress(now: 175).maxGap, 30)
    }
}
