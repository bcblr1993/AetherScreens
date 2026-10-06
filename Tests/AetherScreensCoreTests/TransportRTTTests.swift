import XCTest
import Network
@testable import AetherScreensCore

final class TransportRTTTests: XCTestCase {
    func testSSHReportUsesTransportMillisecondsAndPreservesFramesAndClicks() throws {
        let ready = expectation(description: "Owned loopback fixture ready")
        let clicks = expectation(description: "Balanced click reaches fixture")
        let server = try RTTFrameServer(ready: { ready.fulfill() }, pointer: { mask, x, y in
            if mask == 0 && x == 4 && y == 5 { clicks.fulfill() }
        })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = makeClient()
        defer { client.disconnect() }
        let frame = expectation(description: "Actual raw frame decoded")
        let report = expectation(description: "SSH source RTT published")
        let observations = RTTObservations()
        client.onFrameUpdated = { if observations.frame() == 1 { frame.fulfill() } }
        client.onTransportRTT = { value in
            XCTAssertEqual(value, 32, "SSH value is already milliseconds; never use adapter RTT")
            if observations.record(value) == 1 { report.fulfill() }
        }
        connect(client, server: server, provider: { 32 })
        wait(for: [frame, report], timeout: 3)
        client.sendPointerEvent(buttonMask: .left, x: 4, y: 5)
        client.sendPointerEvent(buttonMask: [], x: 4, y: 5)
        wait(for: [clicks], timeout: 3)
        XCTAssertEqual(client.state, .connected)
    }

    func testInvalidSSHRTTSamplesNeverFallBackToAdapter() throws {
        let values = RTTValues([nil, 0, -1, .nan, .infinity])
        try verifyUnavailable(provider: { values.next() }, sampled: { XCTAssertGreaterThanOrEqual(values.count, 5) })
    }

    func testMissingSSHRTTSourceNeverFallsBackToAdapter() throws {
        try verifyUnavailable(provider: nil, sampled: {})
    }

    func testRetiredSSHRTTCompletionCannotPublishIntoReconnectedClient() throws {
        let ready = expectation(description: "Owned fixture ready")
        let server = try RTTFrameServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let sampling = expectation(description: "Old SSH sample is in flight")
        let gate = RTTSampleGate(started: { sampling.fulfill() })
        defer { gate.release(900) }
        let client = makeClient()
        defer { client.disconnect() }
        connect(client, server: server, provider: { await gate.sample() })
        wait(for: [sampling], timeout: 3)
        client.disconnect()
        let report = expectation(description: "New connection publishes its own RTT")
        let observations = RTTObservations()
        client.onTransportRTT = { value in
            if observations.record(value) == 1 { report.fulfill() }
        }
        connect(client, server: server, provider: { 42 })
        wait(for: [report], timeout: 3)
        gate.release(900)
        let drained = expectation(description: "Retired completion drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertFalse(observations.values.isEmpty)
        XCTAssertTrue(observations.values.allSatisfy { $0 == 42 })
        XCTAssertEqual(client.state, .connected)
    }

    private func verifyUnavailable(provider: (@Sendable () async -> Double?)?, sampled: () -> Void) throws {
        let ready = expectation(description: "Owned fixture ready")
        let server = try RTTFrameServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = makeClient()
        defer { client.disconnect() }
        let unexpected = expectation(description: "No fabricated or adapter latency")
        unexpected.isInverted = true
        let frames = RTTObservations()
        client.onFrameUpdated = { _ = frames.frame() }
        client.onTransportRTT = { _ in unexpected.fulfill() }
        connect(client, server: server, provider: provider)
        wait(for: [unexpected], timeout: 0.5)
        XCTAssertGreaterThan(frames.frameCount, 1, "An idle/disconnected fixture must not satisfy this test")
        XCTAssertEqual(client.state, .connected)
        sampled()
    }

    private func makeClient() -> RFBClient {
        RFBClient(host: "ssh-rtt-fixture.invalid", automaticClipboard: false,
            connectionTimeoutInterval: 3, transportReportInterval: 0.02)
    }

    private func connect(_ client: RFBClient, server: RTTFrameServer,
                         provider: (@Sendable () async -> Double?)?) {
        client.connect(transportHost: "127.0.0.1", transportPort: server.listener.port!.rawValue,
            usesSSHTransport: true, sshRoundTripTimeProvider: provider)
    }
}

private final class RTTObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var samples: [Double] = []
    func frame() -> Int { lock.lock(); defer { lock.unlock() }; frames += 1; return frames }
    func record(_ value: Double) -> Int { lock.lock(); defer { lock.unlock() }; samples.append(value); return samples.count }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return samples }
    var frameCount: Int { lock.lock(); defer { lock.unlock() }; return frames }
}

private final class RTTValues: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [Double?]
    private var consumed = 0
    init(_ values: [Double?]) { self.values = values }
    func next() -> Double? {
        lock.lock(); defer { lock.unlock() }
        let index = consumed; consumed += 1
        return index < values.count ? values[index] : nil
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return consumed }
}

private final class RTTSampleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Double?, Never>?
    private let started: @Sendable () -> Void
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func sample() async -> Double? {
        await withCheckedContinuation { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
            started()
        }
    }
    func release(_ value: Double) {
        lock.lock(); let previous = continuation; continuation = nil; lock.unlock()
        previous?.resume(returning: value)
    }
}

/// Only fixed synthetic frames and pointer receipts; no real credentials/pixels.
private final class RTTFrameServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.rtt-frame-fixture")
    private var connections: [NWConnection] = []
    private let pointer: @Sendable (UInt8, UInt16, UInt16) -> Void
    init(ready: @escaping @Sendable () -> Void,
         pointer: @escaping @Sendable (UInt8, UInt16, UInt16) -> Void = { _, _, _ in }) throws {
        self.pointer = pointer
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.send(connection, Data("RFB 003.008\n".utf8)) {
                self.read(connection, 12) { _ in
                    self.send(connection, Data([1, 1])) {
                        self.read(connection, 1) { _ in
                            self.send(connection, Data([0, 0, 0, 0])) {
                                self.read(connection, 1) { _ in
                                    let initial = Data([0, 16, 0, 16, 32, 24, 0, 1, 0, 255, 0, 255,
                                                        0, 255, 16, 8, 0, 0, 0, 0, 0, 0, 0, 0])
                                    self.send(connection, initial) { self.message(connection) }
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
        queue.sync { listener.cancel(); connections.forEach { $0.cancel() }; connections.removeAll() }
    }
    private func send(_ connection: NWConnection, _ data: Data, then: @escaping @Sendable () -> Void) {
        connection.send(content: data, completion: .contentProcessed { error in if error == nil { then() } })
    }
    private func read(_ connection: NWConnection, _ count: Int, then: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, let data, data.count == count else { return }
            then(data)
        }
    }
    private func message(_ connection: NWConnection) {
        read(connection, 1) { type in
            switch type[0] {
            case 0: self.read(connection, 19) { _ in self.message(connection) }
            case 2:
                self.read(connection, 3) { data in
                    self.read(connection, (Int(data[1]) << 8 | Int(data[2])) * 4) { _ in self.message(connection) }
                }
            case 3:
                self.read(connection, 9) { _ in
                    var frame = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, 16, 0, 16, 0, 0, 0, 0])
                    frame.append(Data(repeating: 90, count: 16 * 16 * 4))
                    self.send(connection, frame) { self.message(connection) }
                }
            case 5:
                self.read(connection, 5) { data in
                    self.pointer(data[0], UInt16(data[1]) << 8 | UInt16(data[2]), UInt16(data[3]) << 8 | UInt16(data[4]))
                    self.message(connection)
                }
            default: connection.cancel()
            }
        }
    }
}
