import XCTest
import Network
@testable import AetherScreensCore

private final class SRPQAClientOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var client: RFBClient?
    private var observation: DispatchWorkItem?
    func set(_ client: RFBClient) {
        lock.lock(); self.client = client; lock.unlock()
    }
    func close() {
        lock.lock(); let previous = client; let pending = observation; client = nil; observation = nil; lock.unlock()
        pending?.cancel()
        previous?.disconnect()
    }
    func setObservation(_ item: DispatchWorkItem) {
        lock.lock(); observation = item; lock.unlock()
    }
}

private final class SRPQAStageTiming: @unchecked Sendable {
    enum Stage: String { case connected, firstRecord, firstPixelRectangle, firstPayloadLength, firstPayloadReady, firstDecodeCompleted, firstFrame, firstFullPayloadLength, firstFullPayloadReady, firstFullDecodeCompleted }
    private let lock = NSLock()
    private let started: TimeInterval
    private var times: [Stage: TimeInterval] = [:]
    private var fullDesktopRectangle = false
    private var receiveStart: TimeInterval?
    private var receiveEnd: TimeInterval?
    private var lastReceive: TimeInterval?
    private var wireBytes = 0
    private var receiveEvents = 0
    private var maximumReceiveGap: TimeInterval = 0
    func received(_ bytes: Int, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock(); defer { lock.unlock() }
        guard bytes > 0, now.isFinite, let receiveStart, receiveEnd == nil,
              now >= (lastReceive ?? receiveStart) else { return }
        maximumReceiveGap = max(maximumReceiveGap, now - (lastReceive ?? receiveStart))
        wireBytes += bytes
        receiveEvents += 1
        lastReceive = now
    }
    var receiveSummary: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        guard let receiveStart, let receiveEnd else { return [:] }
        return ["windowSeconds": receiveEnd - receiveStart, "observedWireBytes": Double(wireBytes),
                "receiveEvents": Double(receiveEvents), "maximumGapSeconds": maximumReceiveGap]
    }
    func rectangle(width: Int, height: Int, desktopWidth: Int, desktopHeight: Int) {
        lock.lock(); defer { lock.unlock() }
        fullDesktopRectangle = width == desktopWidth && height == desktopHeight && width > 0 && height > 0
    }
    func markPayload(_ stage: Stage, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard now.isFinite, now >= started else { return }
        lock.lock(); defer { lock.unlock() }
        if times[stage] == nil { times[stage] = now - started }
        guard fullDesktopRectangle else { return }
        let fullStage: Stage
        switch stage {
        case .firstPayloadLength: fullStage = .firstFullPayloadLength
        case .firstPayloadReady: fullStage = .firstFullPayloadReady
        case .firstDecodeCompleted: fullStage = .firstFullDecodeCompleted
        default: return
        }
        if times[fullStage] == nil {
            times[fullStage] = now - started
            if stage == .firstPayloadLength { receiveStart = now }
            if stage == .firstPayloadReady, let receiveStart {
                receiveEnd = now
                maximumReceiveGap = max(maximumReceiveGap, now - (lastReceive ?? receiveStart))
            }
        }
    }
    init(now: TimeInterval = ProcessInfo.processInfo.systemUptime) { started = now }
    func mark(_ stage: Stage, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard now.isFinite, now >= started else { return }
        lock.lock(); defer { lock.unlock() }
        if times[stage] == nil { times[stage] = now - started }
    }
    var elapsed: [String: TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return Dictionary(uniqueKeysWithValues: times.map { ($0.key.rawValue, $0.value) })
    }
}

final class AppleRSA1PreludeTests: XCTestCase {
    func testStageTimingRetainsFirstArrivalAndRejectsInvalidTime() {
        let timing = SRPQAStageTiming(now: 100)
        timing.mark(.connected, now: 99)
        timing.mark(.connected, now: .infinity)
        XCTAssertTrue(timing.elapsed.isEmpty)
        timing.mark(.connected, now: 102)
        timing.mark(.firstRecord, now: 103)
        timing.mark(.firstPixelRectangle, now: 104)
        timing.mark(.firstFrame, now: 110)
        timing.mark(.firstFrame, now: 120)
        XCTAssertEqual(timing.elapsed, ["connected": 2, "firstRecord": 3,
            "firstPixelRectangle": 4, "firstFrame": 10])
    }
    func testFullDesktopTimingDoesNotMistakeTinyPatchForUsableDesktop() {
        let timing = SRPQAStageTiming(now: 100)
        timing.rectangle(width: 2, height: 2, desktopWidth: 3840, desktopHeight: 2160)
        timing.markPayload(.firstPayloadReady, now: 102)
        XCTAssertNil(timing.elapsed["firstFullPayloadReady"])
        timing.rectangle(width: 3840, height: 2160, desktopWidth: 3840, desktopHeight: 2160)
        timing.markPayload(.firstPayloadLength, now: 105)
        timing.markPayload(.firstPayloadReady, now: 110)
        timing.markPayload(.firstDecodeCompleted, now: 111)
        timing.markPayload(.firstPayloadReady, now: 120)
        XCTAssertEqual(timing.elapsed["firstPayloadReady"], 2)
        XCTAssertEqual(timing.elapsed["firstFullPayloadLength"], 5)
        XCTAssertEqual(timing.elapsed["firstFullPayloadReady"], 10)
        XCTAssertEqual(timing.elapsed["firstFullDecodeCompleted"], 11)
    }
    func testFullDesktopReceiveTimingRejectsStaleAndPostCompletionBytes() {
        let timing = SRPQAStageTiming(now: 100)
        timing.received(123, now: 101)
        timing.rectangle(width: 3840, height: 2160, desktopWidth: 3840, desktopHeight: 2160)
        timing.markPayload(.firstPayloadLength, now: 102)
        timing.received(100, now: 103)
        timing.received(500, now: 102.5)
        timing.received(-1, now: 104)
        timing.received(200, now: 106)
        timing.received(200, now: .nan)
        timing.markPayload(.firstPayloadReady, now: 108)
        timing.received(900, now: 109)
        XCTAssertEqual(timing.receiveSummary, ["windowSeconds": 6, "observedWireBytes": 300,
            "receiveEvents": 2, "maximumGapSeconds": 3])
    }
    func testLiveCredentialFreePublicKeyEnvelope() throws { try runPrelude(challengeProbe:false) }
    func testLiveEncryptedIdentityReceivesChallenge() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_RSA1_CHALLENGE"] == "1" else {
            throw XCTSkip("Requires explicit encrypted-identity challenge QA")
        }
        try runPrelude(challengeProbe:true)
    }
    func testLiveMutualSRPAuthentication() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_RSA1_PROOF"] == "1" else {
            throw XCTSkip("Requires explicit real SRP authentication QA")
        }
        try runPrelude(challengeProbe: true, authenticate: true)
    }
    func testLiveSRPClientFirstPixelFrame() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_QA_RSA1_CLIENT_STREAM"] == "1" else {
            throw XCTSkip("Requires explicit SRP RFBClient frame QA")
        }
        try runPrelude(challengeProbe: true, authenticate: true)
    }
    private func runPrelude(challengeProbe:Bool, authenticate:Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        let identity = env["AETHERSCREENS_LIVE_USERNAME"]
        guard !challengeProbe || (identity != nil && !identity!.isEmpty) else {
            throw XCTSkip("Challenge probe requires an explicit target username")
        }
        guard env["AETHERSCREENS_QA_RSA1_PUBLIC_KEY"] == "1",
              let host = env["AETHERSCREENS_LIVE_HOST"], !host.isEmpty else {
            throw XCTSkip("Requires explicit credential-free RSA1 public-key QA")
        }
        var password: String?
        if authenticate {
            let credentialHost = env["AETHERSCREENS_LIVE_CREDENTIAL_HOST"] ?? host
            guard credentialHost == host || (host == "100.64.0.3" && credentialHost == "192.168.50.226") else {
                throw XCTSkip("Credential alias must refer to the authorized Mac mini")
            }
            var store = DeviceStore.shared
            var device = store.devices.first { $0.host == credentialHost && $0.username == identity }
            if device == nil, let defaults = UserDefaults(suiteName: "com.aethernative.aetherscreens"),
               defaults.data(forKey: DeviceStore.storageKey) != nil {
                // Resolve credentials through the same store that owns the list
                // and target bindings, rather than importing a foreign device.
                store = DeviceStore(userDefaults: defaults)
                device = store.devices.first { $0.host == credentialHost && $0.username == identity }
            }
            password = device.flatMap { store.getPassword(for: $0) }
            guard let password, !password.isEmpty else { throw XCTSkip("Requires saved credentials bound to the target account") }
        }
        let authenticationPassword = password
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 5900, using: .tcp)
        let identityConnection = NWConnection(host:NWEndpoint.Host(host),port:5900,using:.tcp)
        let clientOwner = SRPQAClientOwner()
        let pattern = NativePatternAcceptance()
        defer { clientOwner.close(); connection.stateUpdateHandler=nil; identityConnection.stateUpdateHandler=nil; connection.cancel(); identityConnection.cancel() }
        let done = expectation(description: challengeProbe ? "Bounded SRP challenge" : "Bounded public-key envelope")
        done.assertForOverFulfill = false
        let fail: @Sendable () -> Void = {
            XCTFail("RSA1 prelude probe did not reach its expected bounded response")
            connection.cancel(); identityConnection.cancel(); done.fulfill()
        }
        connection.stateUpdateHandler = { state in
            if case .failed = state { fail() }
            guard case .ready = state else { return }
            Self.read(connection, 12, fail: fail) { banner in
                guard banner == Data("RFB 003.889\n".utf8) else { fail(); return }
                connection.send(content: banner, completion: .contentProcessed { error in
                    guard error == nil else { fail(); return }
                    Self.read(connection, 1, fail: fail) { count in
                        guard count[0] > 0 else { fail(); return }
                        Self.read(connection, Int(count[0]), fail: fail) { offers in
                            guard offers.contains(33) else { fail(); return }
                            connection.send(content: Data([33]) + AppleRSA1Prelude.publicKeyRequest,
                                completion: .contentProcessed { error in
                                guard error == nil else { fail(); return }
                                Self.read(connection, 4, fail: fail) { prefix in
                                    let length = prefix.reduce(0) { $0 << 8 | Int($1) }
                                    guard (7...AppleRSA1Prelude.maximumResponseBytes).contains(length) else { fail(); return }
                                    Self.read(connection, length, fail: fail) { body in
                                        do {
                                            let der = try AppleRSA1Prelude.extractSubjectPublicKeyInfo(prefix + body)
                                            let validated = try AppleRSA1Identity.validateSubjectPublicKeyInfo(der)
                                            XCTAssertEqual(validated.fingerprint.count,32)
                                            print("Actual RSA1 public-key stage valid: DER bytes \(der.count); key trust not established")
                                            if env["AETHERSCREENS_QA_RSA1_CLIENT_STREAM"] == "1", let identity, let authenticationPassword {
                                                connection.cancel()
                                                let framebuffer = Framebuffer()
                                                let client = RFBClient(host: host, password: authenticationPassword, username: identity,
                                                    framebuffer: framebuffer, colorDepth: .rgb565,
                                                    decodeQueue: DispatchQueue(label: "qa.rsa1.client.decode"),
                                                    experimentalAppleCursor: true, experimentalAppleEncryption: true,
                                                    experimentalAppleControlMode: env["AETHERSCREENS_QA_RSA1_CONTROL_MODE"] == "1",
                                                    experimentalAppleSRPKey: der,
                                                    experimentalAppleLogicalSize: env["AETHERSCREENS_QA_RSA1_HIDPI"] == "1" ? (1920, 1080) : nil,
                                                    experimentalAppleCombinedDisplay: env["AETHERSCREENS_QA_RSA1_COMBINED_DISPLAY"] == "1",
                                                    experimentalApplePhysicalSize: env["AETHERSCREENS_QA_RSA1_PHYSICAL_SIZE"] == "1" ? (598.380359111388, 340.770181217549) : nil)
                                                clientOwner.set(client)
                                                let timing = SRPQAStageTiming()
                                                client.onBytesReceived = { timing.received($0) }
                                                client.onNativeRecordReceived = { type, length in
                                                    timing.mark(.firstRecord)
                                                    print("SRP record first byte \(type ?? -1), body bytes \(length)")
                                                }
                                                client.onNativeRectangleReceived = { width, height, encoding in
                                                    if width > 0, height > 0, [Int32(0), 1, 6, 16].contains(encoding) {
                                                        timing.mark(.firstPixelRectangle)
                                                    }
                                                    timing.rectangle(width: width, height: height, desktopWidth: framebuffer.width, desktopHeight: framebuffer.height)
                                                    print("SRP rectangle \(width)x\(height), encoding \(encoding)")
                                                }
                                                client.onNativePayloadLength = { length in
                                                    timing.markPayload(.firstPayloadLength)
                                                    print("SRP declared ZRLE payload bytes \(length)")
                                                }
                                                client.onNativePixelPayloadReady = { length in
                                                    timing.markPayload(.firstPayloadReady)
                                                    print("SRP complete ZRLE payload bytes \(length)")
                                                }
                                                client.onNativePixelDecodeCompleted = { elapsed in
                                                    timing.markPayload(.firstDecodeCompleted)
                                                    print("SRP ZRLE decode worker elapsed \(elapsed)s; excludes receive and presentation")
                                                }
                                                client.onAppleStatusReceived = { command in
                                                    print("SRP native status command \(command)")
                                                }
                                                let requirePattern = env["AETHERSCREENS_QA_RSA1_PATTERN"] == "1"
                                                client.onStateChanged = { state in
                                                    if case .connected = state { timing.mark(.connected) }
                                                    if case .failed(let reason) = state {
                                                        print("SRP RFBClient failure: \(reason)")
                                                        fail()
                                                    }
                                                }
                                                client.onFrameUpdated = { [weak client] in
                                                    // The client publishes the first frame only after pixels,
                                                    // never for a layout/cursor acknowledgement alone.
                                                    timing.mark(.firstFrame)
                                                    if requirePattern {
                                                        _ = pattern.observe(framebuffer)
                                                        return
                                                    }
                                                    var pixels = false
                                                    framebuffer.withPixelChanges(since: nil) { _, width, height, regions, _ in
                                                        pixels = width > 0 && height > 0 && !regions.isEmpty
                                                    }
                                                    guard pixels else { return }
                                                    print("Actual SRP RFBClient decoded pixel frame; no native continuous-push or UI fluidity claim")
                                                    client?.onFrameUpdated = nil
                                                    client?.disconnect()
                                                    done.fulfill()
                                                }
                                                let streamStarted = ProcessInfo.processInfo.systemUptime
                                                client.connect()
                                                if requirePattern {
                                                    let observation = DispatchWorkItem { [weak client] in
                                                        guard client?.state == .connected else { return }
                                                        let progress = pattern.progress(now: ProcessInfo.processInfo.systemUptime)
                                                        if let data = try? JSONSerialization.data(withJSONObject: timing.elapsed, options: .sortedKeys),
                                                           let stages = String(data: data, encoding: .utf8) {
                                                            print("SRP client-stage elapsed seconds \(stages); rectangle-to-frame includes receive and decode")
                                                            if let receiveData = try? JSONSerialization.data(withJSONObject: timing.receiveSummary, options: .sortedKeys),
                                                               let summary = String(data: receiveData, encoding: .utf8) {
                                                                print("Full-desktop receive window \(summary); wire observation excludes previously prefetched bytes and is not exact payload throughput")
                                                            }
                                                        }
                                                        print("Actual SRP owned-pattern states \(progress.states), change span \(progress.span)s, last change age \(progress.age)s")
                                                        print("Known-pattern arrival transitions \(progress.transitions), mean gap \(progress.meanGap)s, maximum gap \(progress.maxGap)s; not rendered FPS")
                                                        if let firstArrival = progress.firstArrival {
                                                            print("First known-pattern arrival after client connect \(firstArrival - streamStarted)s")
                                                        }
                                                        client?.disconnect()
                                                        done.fulfill()
                                                    }
                                                    clientOwner.setObservation(observation)
                                                    DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: observation)
                                                }
                                                return
                                            }
                                            guard challengeProbe, let identity else { done.fulfill(); return }
                                            let identityPacket = try AppleRSA1Identity.identityPacket(username:identity,key:validated)
                                            connection.cancel()
                                            identityConnection.stateUpdateHandler = { state in
                                                if case .failed = state { fail() }
                                                guard case .ready = state else { return }
                                                Self.read(identityConnection,12,fail:fail) { banner in
                                                    guard banner == Data("RFB 003.889\n".utf8) else { fail(); return }
                                                    identityConnection.send(content:banner,completion:.contentProcessed { error in
                                                        guard error == nil else { fail(); return }
                                                        Self.read(identityConnection,1,fail:fail) { count in
                                                            guard count[0]>0 else { fail(); return }
                                                            Self.read(identityConnection,Int(count[0]),fail:fail) { offers in
                                                                guard offers.contains(33) else { fail(); return }
                                                                identityConnection.send(content:Data([33])+identityPacket,completion:.contentProcessed { error in
                                                                    guard error == nil else { fail(); return }
                                                                    Self.read(identityConnection,4,fail:fail) { prefix in
                                                                        let length=prefix.reduce(0) { $0<<8|Int($1) }
                                                                        print("SRP announced frame body bytes: \(length)")
                                                                        guard (10...(AppleSRPChallenge.maximumFrameBytes-4)).contains(length) else { fail(); return }
                                                                        Self.read(identityConnection,length,fail:fail) { body in
                                                                            do {
                                                                                let challenge=try AppleSRPChallenge(frame:prefix+body)
                                                                                XCTAssertEqual(challenge.generator,Data([5]))
                                                                                XCTAssertEqual(challenge.modulus.count,512)
                                                                                XCTAssertTrue(challenge.modulus==AppleSRP6aProof.group,"Actual server must match the trusted RFC group")
                                                                                XCTAssertTrue(challenge.options==AppleSRP6aProof.supportedOptions,"Actual algorithms must match the implemented profile")
                                                                                print("Actual SRP challenge: step \(challenge.step), modulus bytes \(challenge.modulus.count), generator bytes \(challenge.generator.count), salt bytes \(challenge.salt.count), public bytes \(challenge.serverPublic.count), iterations \(challenge.iterations), options bytes \(challenge.options.utf8.count); no password/proof sent")
                                                                                guard authenticate, let authenticationPassword else { done.fulfill(); return }
                                                                                let padding: AppleSRP6aProof.TokenPadding = env["AETHERSCREENS_QA_SRP_PADDED_TOKEN"] == "1" ? .groupWidth : .minimalGenerator
                                                                                let proof = try AppleSRP6aProof.compute(challenge: challenge, password: authenticationPassword, tokenPadding: padding)
                                                                                let packet = try AppleSRPProofPacket.encode(clientPublic: proof.clientPublic, clientProof: proof.clientProof, options: challenge.options)
                                                                                identityConnection.send(content: packet, completion: .contentProcessed { error in
                                                                                    guard error == nil else { fail(); return }
                                                                                    Self.read(identityConnection, 4, fail: fail) { prefix in
                                                                                        let size = prefix.reduce(0) { $0 << 8 | Int($1) }
                                                                                        print("SRP final announced body bytes: \(size)")
                                                                                        guard (2...8192).contains(size) else { fail(); return }
                                                                                        Self.read(identityConnection, size, fail: fail) { body in
                                                                                            if body.count >= 10 {
                                                                                                let stage = body.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                                                                                                print("SRP final stage word: \(stage)")
                                                                                            }
                                                                                            if body.count == 6 {
                                                                                                let stage = body.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                                                                                                let code = body.suffix(2).reduce(UInt16(0)) { $0 << 8 | UInt16($1) }
                                                                                                print("SRP short response: stage word \(stage), final word \(code); semantics unverified")
                                                                                                Self.read(identityConnection, 4, fail: fail) { next in
                                                                                                    let value = next.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                                                                                                    print("SRP word after short response: \(value); not accepted as proof or SecurityResult")
                                                                                                    fail()
                                                                                                }
                                                                                                return
                                                                                            }
                                                                                            do {
                                                                                                let final = try AppleSRPServerProof(frame: prefix + body, expectedStep: 2)
                                                                                                let key = try proof.verifiedWrapKey(serverProof: final.proof)
                                                                                                XCTAssertEqual(key.count, 16)
                                                                                                Self.read(identityConnection, 4, fail: fail) { result in
                                                                                                    guard result == Data(repeating: 0, count: 4) else { fail(); return }
                                                                                                    print("Actual SRP M2 and SecurityResult verified; no ClientInit or session entered")
                                                                                                    guard env["AETHERSCREENS_QA_RSA1_SERVER_INIT"] == "1" else { done.fulfill(); return }
                                                                                                    identityConnection.send(content: Data([0xc1]), completion: .contentProcessed { error in
                                                                                                        guard error == nil else { fail(); return }
                                                                                                        Self.read(identityConnection, 24, fail: fail) { header in
                                                                                                            let nameLength = header.suffix(4).reduce(0) { $0 << 8 | Int($1) }
                                                                                                            guard (1...4096).contains(nameLength) else { fail(); return }
                                                                                                            Self.read(identityConnection, nameLength, fail: fail) { name in
                                                                                                                guard let (initialization, consumed) = RFBDecoder.parseServerInit(header + name), consumed == 24 + nameLength,
                                                                                                                      initialization.width > 0, initialization.height > 0 else { fail(); return }
                                                                                                                print("Actual type33 ServerInit: \(initialization.width)x\(initialization.height), bpp \(initialization.pixelFormat.bitsPerPixel), depth \(initialization.pixelFormat.depth); name content not logged, no framebuffer stream configured")
                                                                                                                done.fulfill()
                                                                                                            }
                                                                                                        }
                                                                                                    })
                                                                                                }
                                                                                            } catch { fail() }
                                                                                        }
                                                                                    }
                                                                                })
                                                                            } catch { print("SRP bounded decode rejected: \(error)"); fail() }
                                                                        }
                                                                    }
                                                                })
                                                            }
                                                        }
                                                    })
                                                }
                                            }
                                            identityConnection.start(queue:DispatchQueue(label:"qa.rsa1.identity"))
                                        } catch { fail() }
                                    }
                                }
                            })
                        }
                    }
                })
            }
        }
        connection.start(queue: DispatchQueue(label: "qa.rsa1.public-key"))
        wait(for: [done], timeout: env["AETHERSCREENS_QA_RSA1_PATTERN"] == "1" ? 90 : (authenticate ? 60 : 20))
        if env["AETHERSCREENS_QA_RSA1_PATTERN"] == "1" {
            let progress = pattern.progress(now: ProcessInfo.processInfo.systemUptime)
            XCTAssertGreaterThanOrEqual(progress.states, 3, "Received owned pattern must change")
            XCTAssertGreaterThanOrEqual(progress.span, 30, "Changes must span the observation window")
            XCTAssertLessThan(progress.age, 20, "Repeated frozen frames must not count as progress")
        }
    }

    private static func read(_ connection: NWConnection, _ count: Int,
        fail: @escaping @Sendable () -> Void, completion: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, let data, data.count == count else { fail(); return }
            completion(data)
        }
    }
    func testBoundedMixedEndianEnvelopeAndCredentialFreeRequest() throws {
        XCTAssertEqual(AppleRSA1Prelude.publicKeyRequest,
            Data([0,0,0,10,1,0,82,83,65,49,0,0,0,0]))
        // Envelope fixture only: this is deliberately not a trusted RSA key.
        let frame = Data([0,0,0,11,0,1,0,0,0,4,0x30,2,5,0,0])
        XCTAssertEqual(try AppleRSA1Prelude.extractSubjectPublicKeyInfo(frame), Data([0x30,2,5,0]))
        for index in [3,4,5,6,7,8,9,10,14] {
            var changed = frame; changed[index] ^= 1
            XCTAssertThrowsError(try AppleRSA1Prelude.extractSubjectPublicKeyInfo(changed))
        }
        for length in 0..<frame.count {
            XCTAssertThrowsError(try AppleRSA1Prelude.extractSubjectPublicKeyInfo(Data(frame.prefix(length))))
        }
        XCTAssertThrowsError(try AppleRSA1Prelude.extractSubjectPublicKeyInfo(frame + Data([0])))
        XCTAssertThrowsError(try AppleRSA1Prelude.extractSubjectPublicKeyInfo(Data(repeating:0, count:8197)))
    }
}
