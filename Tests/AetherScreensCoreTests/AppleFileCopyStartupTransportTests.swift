import XCTest
@testable import AetherScreensCore

final class AppleFileCopyStartupTransportTests: XCTestCase {
    private func message(_ command: UInt16, sessionID: UInt32 = 42) -> AppleFileCopyMessage {
        .init(version: 1, command: command, sessionID: sessionID, body: Data())
    }
    private func adapter(_ harness: StartupHarness) throws -> AppleFileCopyStartupTransport {
        try .init(start: message(2), totals: message(100), transport: { packet, done in
            harness.send(packet, done: done)
        })
    }

    func testPrefixesOnceAndWaitsForEveryWriteDespiteDuplicateCallbacks() throws {
        let harness = StartupHarness(), result = StartupHarness()
        let transport = try adapter(harness)
        XCTAssertTrue(transport.send(message(101), processed: { result.record($0) }))
        XCTAssertEqual(harness.commands, [2])
        XCTAssertFalse(transport.send(message(102), processed: { result.record($0) }))
        harness.complete(0, true)
        harness.complete(0, true)
        XCTAssertEqual(harness.commands, [2, 100])
        XCTAssertEqual(result.results, [])
        harness.complete(1, true)
        XCTAssertEqual(harness.commands, [2, 100, 101])
        harness.complete(2, true)
        harness.complete(2, false)
        XCTAssertEqual(result.results, [true])
        XCTAssertTrue(transport.send(message(102), processed: { result.record($0) }))
        XCTAssertEqual(harness.commands, [2, 100, 101, 102])
        harness.complete(3, true)
        XCTAssertEqual(result.results, [true, true])
    }

    func testInitialAdmissionRejectionIsImmediateAndClosesTransport() throws {
        let harness = StartupHarness(reject: 2), result = StartupHarness()
        let transport = try adapter(harness)
        XCTAssertFalse(transport.send(message(101), processed: { result.record($0) }))
        XCTAssertFalse(transport.send(message(101), processed: { result.record($0) }))
        XCTAssertEqual(harness.commands, [2])
        XCTAssertEqual(result.results, [])
    }

    func testNestedAdmissionRejectionReportsFailureWithoutWaitingForTimeout() throws {
        for command: UInt16 in [100, 101] {
            let harness = StartupHarness(reject: command), result = StartupHarness()
            let transport = try adapter(harness)
            XCTAssertTrue(transport.send(message(101), processed: { result.record($0) }))
            harness.complete(0, true)
            if command == 101 { harness.complete(1, true) }
            XCTAssertEqual(result.results, [false])
            harness.complete(0, true)
            XCTAssertEqual(result.results, [false])
            XCTAssertFalse(transport.send(message(102), processed: { result.record($0) }))
        }
    }

    func testAsyncFailureStopsChainAndIgnoresLateSuccess() throws {
        let harness = StartupHarness(), result = StartupHarness()
        let transport = try adapter(harness)
        XCTAssertTrue(transport.send(message(101), processed: { result.record($0) }))
        harness.complete(0, false)
        harness.complete(0, true)
        XCTAssertEqual(harness.commands, [2])
        XCTAssertEqual(result.results, [false])
    }

    func testCancellationAndWrongSessionNeverAdvanceChain() throws {
        let harness = StartupHarness(), result = StartupHarness()
        let transport = try adapter(harness)
        XCTAssertFalse(transport.send(message(101, sessionID: 43), processed: { result.record($0) }))
        XCTAssertTrue(transport.send(message(101), processed: { result.record($0) }))
        transport.cancel()
        harness.complete(0, true)
        XCTAssertEqual(harness.commands, [2])
        XCTAssertEqual(result.results, [])
        XCTAssertFalse(transport.send(message(102), processed: { result.record($0) }))
    }

    func testInvalidPrefixesAreRejected() {
        XCTAssertThrowsError(try AppleFileCopyStartupTransport(start: message(1), totals: message(100), transport: { _, _ in true }))
        XCTAssertThrowsError(try AppleFileCopyStartupTransport(start: message(2), totals: message(101), transport: { _, _ in true }))
        XCTAssertThrowsError(try AppleFileCopyStartupTransport(start: message(2), totals: message(100, sessionID: 43), transport: { _, _ in true }))
        XCTAssertThrowsError(try AppleFileCopyStartupTransport(start: .init(version: 2, command: 2, sessionID: 42, body: Data()), totals: message(100), transport: { _, _ in true }))
    }
}

private final class StartupHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var packets: [AppleFileCopyMessage] = []
    private var callbacks: [@Sendable (Bool) -> Void] = []
    private var recorded: [Bool] = []
    private let reject: UInt16?
    init(reject: UInt16? = nil) { self.reject = reject }
    var commands: [UInt16] { lock.lock(); defer { lock.unlock() }; return packets.map(\.command) }
    var results: [Bool] { lock.lock(); defer { lock.unlock() }; return recorded }
    func record(_ value: Bool) { lock.lock(); recorded.append(value); lock.unlock() }
    func send(_ packet: AppleFileCopyMessage, done: @escaping @Sendable (Bool) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        packets.append(packet)
        if packet.command == reject { return false }
        callbacks.append(done)
        return true
    }
    func complete(_ index: Int, _ success: Bool) {
        lock.lock(); let callback = callbacks[index]; lock.unlock()
        callback(success)
    }
}
