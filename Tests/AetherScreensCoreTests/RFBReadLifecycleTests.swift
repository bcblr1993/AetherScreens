import Foundation
import XCTest
import Network
@testable import AetherScreensCore

/// Controlled lifecycle regressions. Fixture pattern follows TransportRTTTests
/// baseline c232021587a56eab48c0e051ade8384a8e9dfaec93307e785dde3376ced12f17:
/// owned loopback listeners, fixed None authentication, and synthetic raw pixels.
final class RFBReadLifecycleTests: XCTestCase {
    func testRetiredSecurityRejectionReasonCannotFailReplacementConnection() throws {
        try verifyRetiredRead(.securityReason)
    }

    func testRetiredAuthenticationRejectionLengthCannotFailReplacementConnection() throws {
        try verifyRetiredRead(.authenticationLength)
    }

    func testRetiredAuthenticationRejectionReasonCannotFailReplacementConnection() throws {
        try verifyRetiredRead(.authenticationReason)
    }

    func testRetiredCursorPayloadCannotPublishIntoReplacementConnection() throws {
        try verifyRetiredRead(.cursorPayload)
    }

    private func verifyRetiredRead(_ stage: RetiredReadStage) throws {
        let oldReady = expectation(description: "Old staged loopback listener ready")
        let newReady = expectation(description: "Replacement loopback listener ready")
        let processedFrame = expectation(description: "Replacement frame caused the next real protocol request")
        [oldReady, newReady, processedFrame].forEach { $0.assertForOverFulfill = true }
        let oldServer = try RetiredReadServer(stage: stage, ready: { oldReady.fulfill() })
        defer { oldServer.stop() }
        let replacement = try RetiredReadServer(stage: .success, ready: { newReady.fulfill() },
                                               processedFrame: { processedFrame.fulfill() })
        defer { replacement.stop() }
        wait(for: [oldReady, newReady], timeout: 3)
        let oldPort = try XCTUnwrap(oldServer.listener.port).rawValue
        let newPort = try XCTUnwrap(replacement.listener.port).rawValue
        let paused = expectation(description: "One partial target byte reached the old read callback")
        paused.assertForOverFulfill = true
        let gate = RetiredReadGate(prefixBytes: stage.prefixBytes, partial: { oldServer.sendPartialTarget() },
                                   paused: { paused.fulfill() })
        defer { gate.release() }
        let client = RFBClient(host: "retired-read-fixture.invalid", automaticClipboard: false,
                               automaticFramebufferUpdates: false, connectionTimeoutInterval: 3)
        defer { client.disconnect() }
        let framebuffer = client.framebuffer
        let observations = RetiredReadObservations()
        let connected = expectation(description: "Replacement connection completed None authentication")
        let correctFrame = expectation(description: "Only the replacement fixed raw frame was published")
        [connected, correctFrame].forEach { $0.assertForOverFulfill = true }
        client.onBytesReceived = { gate.observe($0) }
        client.onStateChanged = { state in
            if observations.state(state) { connected.fulfill() }
        }
        // Capture the framebuffer rather than client; the callback has no client cycle.
        client.onFrameUpdated = {
            var correct = false
            framebuffer.withPixelBytes { bytes, width, height in
                correct = width == 16 && height == 16 && bytes.count == 16 * 16 * 4
                    && bytes.allSatisfy { $0 == 90 }
            }
            if observations.frame(correct: correct) { correctFrame.fulfill() }
        }
        onMain {
            client.connect(transportHost: "127.0.0.1", transportPort: oldPort,
                           usesSSHTransport: false, sshRoundTripTimeProvider: nil)
        }
        wait(for: [paused], timeout: 3)
        XCTAssertEqual(gate.totalAtPause, stage.prefixBytes + 1)
        onMain {
            observations.beginReplacement()
            client.disconnect()
            client.connect(transportHost: "127.0.0.1", transportPort: newPort,
                           usesSSHTransport: false, sshRoundTripTimeProvider: nil)
        }
        gate.release()
        wait(for: [connected, correctFrame, processedFrame], timeout: 3)
        XCTAssertFalse(gate.timedOut, "Semaphore timeout is a deadlock guard, not an interleaving delay")
        XCTAssertEqual(observations.failures, 0, "A retired nil completion must not fail the replacement")
        XCTAssertEqual(observations.frames, [true], "Retired cursor completion must not publish a blank or extra frame")
        XCTAssertEqual(client.state, .connected)
    }

    private func onMain(_ operation: () -> Void) {
        if Thread.isMainThread { operation() }
        else { DispatchQueue.main.sync(execute: operation) }
    }
}

private enum RetiredReadStage: Equatable, Sendable {
    case securityReason, authenticationLength, authenticationReason, cursorPayload, success

    // Counts include only server-to-client bytes, with zero-length server names.
    var prefixBytes: Int {
        switch self {
        case .securityReason: return 12 + 1 + 4
        case .authenticationLength: return 12 + 2 + 4
        case .authenticationReason: return 12 + 2 + 4 + 4
        case .cursorPayload: return 12 + 2 + 4 + 24 + 16
        case .success: return 0
        }
    }
}

private final class RetiredReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private let prefixBytes: Int
    private let partial: @Sendable () -> Void
    private let paused: @Sendable () -> Void
    private var total = 0
    private var requestedPartial = false
    private var didPause = false
    private var released = false
    private var timeout = false
    private var pauseTotal: Int?

    init(prefixBytes: Int, partial: @escaping @Sendable () -> Void, paused: @escaping @Sendable () -> Void) {
        self.prefixBytes = prefixBytes
        self.partial = partial
        self.paused = paused
    }

    func observe(_ bytes: Int) {
        lock.lock()
        total += bytes
        let sendPartial = !requestedPartial && total == prefixBytes
        if sendPartial { requestedPartial = true }
        let stopHere = !didPause && requestedPartial && total == prefixBytes + 1
        if stopHere { didPause = true; pauseTotal = total }
        lock.unlock()
        if sendPartial { partial() }
        if stopHere {
            paused()
            let result = resume.wait(timeout: .now() + 5)
            lock.lock(); timeout = result == .timedOut; lock.unlock()
        }
    }

    func release() {
        lock.lock()
        let signal = !released
        released = true
        lock.unlock()
        if signal { resume.signal() }
    }

    var totalAtPause: Int? { lock.lock(); defer { lock.unlock() }; return pauseTotal }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }
}

private final class RetiredReadObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var replacementStarted = false
    private var reportedConnected = false
    private var reportedCorrectFrame = false
    private var failureCount = 0
    private var frameValues: [Bool] = []

    func beginReplacement() {
        lock.lock(); defer { lock.unlock() }; replacementStarted = true
    }

    func state(_ state: RFBClient.State) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard replacementStarted else { return false }
        if case .failed = state { failureCount += 1 }
        if state == .connected && !reportedConnected {
            reportedConnected = true
            return true
        }
        return false
    }

    func frame(correct: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        frameValues.append(correct)
        if correct && replacementStarted && !reportedCorrectFrame {
            reportedCorrectFrame = true
            return true
        }
        return false
    }

    var failures: Int { lock.lock(); defer { lock.unlock() }; return failureCount }
    var frames: [Bool] { lock.lock(); defer { lock.unlock() }; return frameValues }
}

/// Narrow copy of the TransportRTTTests loopback/None fixture pattern. Rejection
/// stages send only fixed protocol bytes; no credentials or real pixels exist.
private final class RetiredReadServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.retired-read-fixture")
    private let stage: RetiredReadStage
    private let processedFrame: @Sendable () -> Void
    private var connections: [NWConnection] = []
    private var target: NWConnection?
    private var didSendPartial = false
    private var didSendFrame = false
    private var didSendCursor = false
    private var didReportProcessed = false
    private var didReportReady = false

    init(stage: RetiredReadStage, ready: @escaping @Sendable () -> Void,
         processedFrame: @escaping @Sendable () -> Void = {}) throws {
        self.stage = stage
        self.processedFrame = processedFrame
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, !self.didReportReady else { return }
            self.didReportReady = true
            ready()
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            self.target = connection
            connection.start(queue: self.queue)
            self.send(connection, Data("RFB 003.008\n".utf8)) {
                self.read(connection, 12) { _ in self.security(connection) }
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
            target = nil
        }
    }

    func sendPartialTarget() {
        queue.async { [weak self] in
            guard let self, !self.didSendPartial, let target = self.target else { return }
            self.didSendPartial = true
            // A length read needs four bytes; a reason/cursor needs five. One
            // byte proves the target receive is pending before cancellation.
            self.send(target, Data([self.stage == .authenticationLength ? 0 : 81])) {}
        }
    }

    private func security(_ connection: NWConnection) {
        if stage == .securityReason {
            send(connection, Data([0])) { self.send(connection, Data([0, 0, 0, 5])) {} }
            return
        }
        send(connection, Data([1, 1])) {
            self.read(connection, 1) { selection in
                guard selection == Data([1]) else { connection.cancel(); return }
                if self.stage == .authenticationLength || self.stage == .authenticationReason {
                    self.send(connection, Data([0, 0, 0, 1])) {
                        if self.stage == .authenticationReason {
                            self.send(connection, Data([0, 0, 0, 5])) {}
                        }
                    }
                    return
                }
                self.send(connection, Data([0, 0, 0, 0])) {
                    self.read(connection, 1) { shared in
                        guard shared == Data([1]) else { connection.cancel(); return }
                        let initial = Data([0, 16, 0, 16, 32, 24, 0, 1, 0, 255, 0, 255,
                                            0, 255, 16, 8, 0, 0, 0, 0, 0, 0, 0, 0])
                        self.send(connection, initial) { self.message(connection) }
                    }
                }
            }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data, then: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in if error == nil { then() } })
    }

    private func read(_ connection: NWConnection, _ count: Int, then: @escaping @Sendable (Data) -> Void) {
        if count == 0 { then(Data()); return }
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, let data, data.count == count else { return }
            then(data)
        }
    }

    private func message(_ connection: NWConnection) {
        read(connection, 1) { type in
            switch type[0] {
            case 0:
                self.read(connection, 19) { _ in self.message(connection) }
            case 2:
                self.read(connection, 3) { data in
                    self.read(connection, (Int(data[1]) << 8 | Int(data[2])) * 4) { _ in self.message(connection) }
                }
            case 3:
                self.read(connection, 9) { _ in
                    if self.stage == .cursorPayload {
                        guard !self.didSendCursor else { return }
                        self.didSendCursor = true
                        // One 1x1 Cursor rectangle (-239), with its five-byte
                        // payload deliberately held until the onBytes marker.
                        let header = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 255, 255, 255, 17])
                        self.send(connection, header) {}
                    } else if self.stage == .success && !self.didSendFrame {
                        self.didSendFrame = true
                        var frame = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 16, 0, 0, 0, 0])
                        frame.append(Data(repeating: 90, count: 16 * 16 * 4))
                        self.send(connection, frame) { self.message(connection) }
                    } else if self.stage == .success && !self.didReportProcessed {
                        self.didReportProcessed = true
                        self.processedFrame()
                    }
                }
            case 5:
                self.read(connection, 5) { _ in self.message(connection) }
            default:
                connection.cancel()
            }
        }
    }
}

extension RFBReadLifecycleTests {
    func testCurrentSecurityRejectionReasonFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.securityReasonComplete)
    }

    func testCurrentAuthenticationRejectionReasonFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.authenticationReasonComplete)
    }

    func testCurrentSecurityReasonEOFFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.securityReasonEOF)
    }

    func testCurrentAuthenticationLengthEOFFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.authenticationLengthEOF)
    }

    func testCurrentAuthenticationReasonEOFFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.authenticationReasonEOF)
    }

    func testCurrentCursorPayloadEOFFailsOnceAndObserverReconnects() throws {
        try verifyCurrentReadControl(.cursorPayloadEOF)
    }

    func testRetiredBytesCallbackCannotPublishOldDownloadProgress() throws {
        let oldReady = expectation(description: "Large synthetic download listener ready")
        let newReady = expectation(description: "Small replacement listener ready")
        let processedFrame = expectation(description: "Replacement frame caused the second real framebuffer request")
        let paused = expectation(description: "Old onBytes crossed the two MiB payload boundary")
        let connected = expectation(description: "Download replacement completed None authentication")
        let correctFrame = expectation(description: "Only replacement fixed pixels were published")
        [oldReady, newReady, processedFrame, paused, connected, correctFrame].forEach {
            $0.assertForOverFulfill = true
        }
        let oldServer = try CurrentReadControlServer(stage: .largeDownload, ready: { oldReady.fulfill() })
        defer { oldServer.stop() }
        let replacement = try CurrentReadControlServer(stage: .success, ready: { newReady.fulfill() },
                                                     processedFrame: { processedFrame.fulfill() })
        defer { replacement.stop() }
        wait(for: [oldReady, newReady], timeout: 3)
        let oldPort = try XCTUnwrap(oldServer.listener.port).rawValue
        let newPort = try XCTUnwrap(replacement.listener.port).rawValue
        // Header bytes precede the raw payload. TCP segmentation is unrestricted:
        // pause once at >= threshold, rather than assuming an exact receive size.
        let threshold = 58 + 2 * 1024 * 1024
        let gate = CurrentDownloadControlGate(threshold: threshold, paused: { paused.fulfill() })
        defer { gate.release() }
        let observations = CurrentDownloadControlObservations()
        let client = RFBClient(host: "download-progress-control.invalid", automaticClipboard: false,
                               automaticFramebufferUpdates: false, connectionTimeoutInterval: 3)
        defer { client.disconnect() }
        let framebuffer = client.framebuffer
        client.onBytesReceived = { gate.observe($0) }
        client.onDownloadProgress = { _, _ in observations.progress() }
        client.onStateChanged = { state in
            if observations.state(state) { connected.fulfill() }
        }
        client.onFrameUpdated = {
            var correct = false
            framebuffer.withPixelBytes { bytes, width, height in
                correct = width == 16 && height == 16 && bytes.count == 16 * 16 * 4
                    && bytes.allSatisfy { $0 == 90 }
            }
            if observations.frame(correct: correct) { correctFrame.fulfill() }
        }
        performCurrentDownloadControlOnMain {
            client.connect(transportHost: "127.0.0.1", transportPort: oldPort,
                           usesSSHTransport: false, sshRoundTripTimeProvider: nil)
        }
        wait(for: [paused], timeout: 3)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(gate.totalAtPause), threshold)
        performCurrentDownloadControlOnMain {
            observations.beginReplacement()
            client.disconnect()
            client.connect(transportHost: "127.0.0.1", transportPort: newPort,
                           usesSSHTransport: false, sshRoundTripTimeProvider: nil)
        }
        gate.release()
        wait(for: [connected, correctFrame, processedFrame], timeout: 3)
        XCTAssertFalse(gate.timedOut, "Semaphore timeout is only a deadlock guard")
        XCTAssertEqual(observations.progressCount, 0, "Retirement in onBytes must suppress the captured old progress")
        XCTAssertEqual(observations.failures, 0)
        XCTAssertEqual(observations.frames, [true])
        XCTAssertEqual(client.state, .connected)
        // This checks the identified post-onBytes retirement boundary; it does
        // not claim that every callback in the client is an atomic epoch.
    }

    private func performCurrentDownloadControlOnMain(_ operation: () -> Void) {
        if Thread.isMainThread { operation() }
        else { DispatchQueue.main.sync(execute: operation) }
    }

    private func verifyCurrentReadControl(_ stage: CurrentReadControlStage) throws {
        let oldReady = expectation(description: "Current staged listener ready")
        let newReady = expectation(description: "Observer replacement listener ready")
        let processedFrame = expectation(description: "Replacement frame caused its next real framebuffer request")
        [oldReady, newReady, processedFrame].forEach { $0.assertForOverFulfill = true }
        let oldServer = try CurrentReadControlServer(stage: stage, ready: { oldReady.fulfill() })
        defer { oldServer.stop() }
        let replacement = try CurrentReadControlServer(stage: .success, ready: { newReady.fulfill() },
                                                     processedFrame: { processedFrame.fulfill() })
        defer { replacement.stop() }
        wait(for: [oldReady, newReady], timeout: 3)
        let oldPort = try XCTUnwrap(oldServer.listener.port).rawValue
        let newPort = try XCTUnwrap(replacement.listener.port).rawValue

        let prefixReceived = expectation(description: "All fixed bytes before the target read arrived")
        let failureReceived = expectation(description: "Exactly one current failure initiated synchronous replacement")
        let connected = expectation(description: "Observer replacement completed None authentication")
        let correctFrame = expectation(description: "Observer replacement published its fixed frame")
        [prefixReceived, failureReceived, connected, correctFrame].forEach { $0.assertForOverFulfill = true }
        let partialReceived: XCTestExpectation?
        if stage.isEOF {
            partialReceived = expectation(description: "Exactly one partial target byte arrived before FIN")
            partialReceived?.assertForOverFulfill = true
        } else {
            partialReceived = nil
        }
        let marker = CurrentReadControlMarker(prefixBytes: stage.prefixBytes,
                                             prefix: { prefixReceived.fulfill() },
                                             partial: { partialReceived?.fulfill() })
        let observations = CurrentReadControlObservations()
        let client = RFBClient(host: "current-read-control.invalid", automaticClipboard: false,
                               automaticFramebufferUpdates: false, connectionTimeoutInterval: 3)
        defer { client.disconnect() }
        let framebuffer = client.framebuffer
        client.onBytesReceived = { marker.observe($0) }
        client.onStateChanged = { [weak client] state in
            if case .failed(let reason) = state {
                // Deliberately reconnect inside the failure callback, without a
                // queue hop, to exercise teardown-before-publication reentrancy.
                if observations.failure(reason) {
                    client?.connect(transportHost: "127.0.0.1", transportPort: newPort,
                                    usesSSHTransport: false, sshRoundTripTimeProvider: nil)
                    failureReceived.fulfill()
                }
            } else if state == .connected && observations.connected() {
                connected.fulfill()
            }
        }
        client.onFrameUpdated = {
            var correct = false
            framebuffer.withPixelBytes { bytes, width, height in
                correct = width == 16 && height == 16 && bytes.count == 16 * 16 * 4
                    && bytes.allSatisfy { $0 == 90 }
            }
            if observations.frame(correct: correct) { correctFrame.fulfill() }
        }
        if Thread.isMainThread {
            client.connect(transportHost: "127.0.0.1", transportPort: oldPort,
                           usesSSHTransport: false, sshRoundTripTimeProvider: nil)
        } else {
            DispatchQueue.main.sync {
                client.connect(transportHost: "127.0.0.1", transportPort: oldPort,
                               usesSSHTransport: false, sshRoundTripTimeProvider: nil)
            }
        }
        wait(for: [prefixReceived], timeout: 3)
        XCTAssertEqual(marker.totalAtPrefix, stage.prefixBytes)
        oldServer.releaseTarget()
        if let partialReceived {
            wait(for: [partialReceived], timeout: 3)
            XCTAssertEqual(marker.totalAtPartial, stage.prefixBytes + 1)
            // Send an orderly EOF only after onBytes confirms the partial byte.
            // No connection.cancel(), timer, or delay selects the EOF boundary.
            oldServer.releaseEOF()
        }
        wait(for: [failureReceived, connected, correctFrame, processedFrame], timeout: 3)
        XCTAssertEqual(observations.failureReasons, [stage.expectedFailure])
        XCTAssertEqual(observations.frames, [true], "Current cursor EOF must not publish a blank frame")
        XCTAssertEqual(client.state, .connected)
    }
}

private enum CurrentReadControlStage: Equatable, Sendable {
    case securityReasonComplete, authenticationReasonComplete
    case securityReasonEOF, authenticationLengthEOF, authenticationReasonEOF, cursorPayloadEOF
    case success, largeDownload

    var isEOF: Bool {
        switch self {
        case .securityReasonEOF, .authenticationLengthEOF, .authenticationReasonEOF, .cursorPayloadEOF: return true
        default: return false
        }
    }

    var isSecurityReason: Bool { self == .securityReasonComplete || self == .securityReasonEOF }
    var isAuthenticationRejection: Bool {
        self == .authenticationReasonComplete || self == .authenticationReasonEOF || self == .authenticationLengthEOF
    }

    var prefixBytes: Int {
        switch self {
        case .securityReasonComplete, .securityReasonEOF: return 12 + 1 + 4
        case .authenticationLengthEOF: return 12 + 2 + 4
        case .authenticationReasonComplete, .authenticationReasonEOF: return 12 + 2 + 4 + 4
        case .cursorPayloadEOF: return 12 + 2 + 4 + 24 + 16
        case .success: return 0
        case .largeDownload: return 58
        }
    }

    var expectedFailure: String {
        switch self {
        case .securityReasonComplete: return "Server rejected connection: QAREJ"
        case .authenticationReasonComplete: return "QAREJ"
        case .authenticationLengthEOF: return "Remote host closed connection (received 1/4 bytes)"
        case .securityReasonEOF, .authenticationReasonEOF, .cursorPayloadEOF:
            return "Remote host closed connection (received 1/5 bytes)"
        case .success, .largeDownload: return "Unused nonfailure fixture"
        }
    }
}

private final class CurrentReadControlMarker: @unchecked Sendable {
    private let lock = NSLock()
    private let prefixBytes: Int
    private let prefix: @Sendable () -> Void
    private let partial: @Sendable () -> Void
    private var total = 0
    private var prefixTotal: Int?
    private var partialTotal: Int?

    init(prefixBytes: Int, prefix: @escaping @Sendable () -> Void, partial: @escaping @Sendable () -> Void) {
        self.prefixBytes = prefixBytes
        self.prefix = prefix
        self.partial = partial
    }

    func observe(_ count: Int) {
        lock.lock()
        total += count
        let reportPrefix = prefixTotal == nil && total == prefixBytes
        if reportPrefix { prefixTotal = total }
        let reportPartial = partialTotal == nil && total == prefixBytes + 1
        if reportPartial { partialTotal = total }
        lock.unlock()
        if reportPrefix { prefix() }
        if reportPartial { partial() }
    }

    var totalAtPrefix: Int? { lock.lock(); defer { lock.unlock() }; return prefixTotal }
    var totalAtPartial: Int? { lock.lock(); defer { lock.unlock() }; return partialTotal }
}

private final class CurrentReadControlObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var reasons: [String] = []
    private var frameValues: [Bool] = []
    private var reportedConnected = false
    private var reportedFrame = false

    func failure(_ reason: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        reasons.append(reason)
        return reasons.count == 1
    }

    func connected() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !reasons.isEmpty, !reportedConnected else { return false }
        reportedConnected = true
        return true
    }

    func frame(correct: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        frameValues.append(correct)
        guard !reasons.isEmpty, correct, !reportedFrame else { return false }
        reportedFrame = true
        return true
    }

    var failureReasons: [String] { lock.lock(); defer { lock.unlock() }; return reasons }
    var frames: [Bool] { lock.lock(); defer { lock.unlock() }; return frameValues }
}

private final class CurrentDownloadControlGate: @unchecked Sendable {
    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private let threshold: Int
    private let paused: @Sendable () -> Void
    private var total = 0
    private var pauseTotal: Int?
    private var released = false
    private var timeout = false

    init(threshold: Int, paused: @escaping @Sendable () -> Void) {
        self.threshold = threshold
        self.paused = paused
    }

    func observe(_ count: Int) {
        lock.lock()
        total += count
        let shouldPause = pauseTotal == nil && total >= threshold
        if shouldPause { pauseTotal = total }
        lock.unlock()
        if shouldPause {
            paused()
            let result = resume.wait(timeout: .now() + 5)
            lock.lock(); timeout = result == .timedOut; lock.unlock()
        }
    }

    func release() {
        lock.lock()
        let shouldSignal = !released
        released = true
        lock.unlock()
        if shouldSignal { resume.signal() }
    }

    var totalAtPause: Int? { lock.lock(); defer { lock.unlock() }; return pauseTotal }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return timeout }
}

private final class CurrentDownloadControlObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var replacementStarted = false
    private var reportedConnected = false
    private var reportedFrame = false
    private var progressValues = 0
    private var failureValues = 0
    private var frameValues: [Bool] = []

    func beginReplacement() { lock.lock(); defer { lock.unlock() }; replacementStarted = true }
    func progress() { lock.lock(); defer { lock.unlock() }; progressValues += 1 }

    func state(_ state: RFBClient.State) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard replacementStarted else { return false }
        if case .failed = state { failureValues += 1 }
        guard state == .connected, !reportedConnected else { return false }
        reportedConnected = true
        return true
    }

    func frame(correct: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        frameValues.append(correct)
        guard replacementStarted, correct, !reportedFrame else { return false }
        reportedFrame = true
        return true
    }

    var progressCount: Int { lock.lock(); defer { lock.unlock() }; return progressValues }
    var failures: Int { lock.lock(); defer { lock.unlock() }; return failureValues }
    var frames: [Bool] { lock.lock(); defer { lock.unlock() }; return frameValues }
}

/// Independent prefixed fixture: no dependency on the canonical private helpers.
private final class CurrentReadControlServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.current-read-control")
    private let stage: CurrentReadControlStage
    private let processedFrame: @Sendable () -> Void
    private var connections: [NWConnection] = []
    private var target: NWConnection?
    private var didReportReady = false
    private var didReleaseTarget = false
    private var didReleaseEOF = false
    private var didSendFrame = false
    private var didSendCursor = false
    private var didReportProcessed = false

    init(stage: CurrentReadControlStage, ready: @escaping @Sendable () -> Void,
         processedFrame: @escaping @Sendable () -> Void = {}) throws {
        self.stage = stage
        self.processedFrame = processedFrame
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, !self.didReportReady else { return }
            self.didReportReady = true
            ready()
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            self.target = connection
            connection.start(queue: self.queue)
            self.send(connection, Data("RFB 003.008\n".utf8)) {
                self.read(connection, 12) { _ in self.security(connection) }
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
            target = nil
        }
    }

    func releaseTarget() {
        queue.async { [weak self] in
            guard let self, !self.didReleaseTarget, let target = self.target else { return }
            self.didReleaseTarget = true
            let data = self.stage.isEOF
                ? Data([self.stage == .authenticationLengthEOF ? 0 : 81])
                : Data("QAREJ".utf8)
            self.send(target, data) {}
        }
    }

    func releaseEOF() {
        queue.async { [weak self] in
            guard let self, self.stage.isEOF, self.didReleaseTarget,
                  !self.didReleaseEOF, let target = self.target else { return }
            self.didReleaseEOF = true
            target.send(content: nil, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in })
        }
    }

    private func security(_ connection: NWConnection) {
        if stage.isSecurityReason {
            send(connection, Data([0])) { self.send(connection, Data([0, 0, 0, 5])) {} }
            return
        }
        send(connection, Data([1, 1])) {
            self.read(connection, 1) { selection in
                guard selection == Data([1]) else { connection.cancel(); return }
                if self.stage.isAuthenticationRejection {
                    self.send(connection, Data([0, 0, 0, 1])) {
                        if self.stage != .authenticationLengthEOF {
                            self.send(connection, Data([0, 0, 0, 5])) {}
                        }
                    }
                    return
                }
                self.send(connection, Data([0, 0, 0, 0])) {
                    self.read(connection, 1) { shared in
                        guard shared == Data([1]) else { connection.cancel(); return }
                        let dimensions: [UInt8] = self.stage == .largeDownload ? [4, 0, 3, 0] : [0, 16, 0, 16]
                        var initial = Data(dimensions)
                        initial.append(Data([32, 24, 0, 1, 0, 255, 0, 255,
                                             0, 255, 16, 8, 0, 0, 0, 0, 0, 0, 0, 0]))
                        self.send(connection, initial) { self.message(connection) }
                    }
                }
            }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data, then: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in if error == nil { then() } })
    }

    private func read(_ connection: NWConnection, _ count: Int, then: @escaping @Sendable (Data) -> Void) {
        if count == 0 { then(Data()); return }
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, let data, data.count == count else { return }
            then(data)
        }
    }

    private func message(_ connection: NWConnection) {
        read(connection, 1) { type in
            switch type[0] {
            case 0:
                self.read(connection, 19) { _ in self.message(connection) }
            case 2:
                self.read(connection, 3) { data in
                    self.read(connection, (Int(data[1]) << 8 | Int(data[2])) * 4) { _ in self.message(connection) }
                }
            case 3:
                self.read(connection, 9) { _ in
                    if self.stage == .cursorPayloadEOF {
                        guard !self.didSendCursor else { return }
                        self.didSendCursor = true
                        self.send(connection, Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 255, 255, 255, 17])) {}
                    } else if (self.stage == .success || self.stage == .largeDownload) && !self.didSendFrame {
                        self.didSendFrame = true
                        let dimensions: [UInt8] = self.stage == .largeDownload ? [4, 0, 3, 0] : [0, 16, 0, 16]
                        var frame = Data([0, 0, 0, 1, 0, 0, 0, 0])
                        frame.append(Data(dimensions))
                        frame.append(Data([0, 0, 0, 0]))
                        frame.append(Data(repeating: self.stage == .largeDownload ? 81 : 90,
                                          count: self.stage == .largeDownload ? 1024 * 768 * 4 : 16 * 16 * 4))
                        self.send(connection, frame) {
                            if self.stage == .success { self.message(connection) }
                            // The large old fixture sends only this one frame.
                        }
                    } else if self.stage == .success && !self.didReportProcessed {
                        self.didReportProcessed = true
                        self.processedFrame()
                        // This is the completion marker; do not continue a send loop.
                    }
                }
            case 5:
                self.read(connection, 5) { _ in self.message(connection) }
            default:
                connection.cancel()
            }
        }
    }
}
