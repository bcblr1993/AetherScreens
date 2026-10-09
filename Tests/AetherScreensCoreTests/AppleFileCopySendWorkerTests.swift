import XCTest
@testable import AetherScreensCore

final class AppleFileCopySendWorkerTests: XCTestCase {
    func testRemoteSuccessCannotHideMissingFinalLocalWrite() throws {
        let (url, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "send-worker-final-write-timeout")
        let transport = Transport()
        let failed = expectation(description: "Last local write expires despite remote success")
        let endAdmitted = expectation(description: "End packet is waiting for its local write")
        let worker = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 5,
            writeTimeout: 0.05, resultTimeout: 1, queue: queue,
            transport: { packet, done in
                _ = transport.send(packet, done: done)
                if packet.command != 104 { done(true) }
                else { endAdmitted.fulfill() }
                return true
            }, onCompleted: { _ in XCTFail("Unprocessed end packet cannot complete") },
            onFailure: { failed.fulfill() })
        XCTAssertTrue(worker.start())
        wait(for: [endAdmitted], timeout: 2)
        XCTAssertEqual(transport.commands, [101, 102, 104])
        XCTAssertTrue(worker.enqueue(result))
        wait(for: [failed], timeout: 2)
        transport.finish(2)
        queue.sync {}
        XCTAssertFalse(worker.enqueue(result))
        XCTAssertEqual(try Data(contentsOf: url), Data([0, 1, 2, 3, 4]))
    }

    func testMissingLocalWriteOrFinalServerResultTimesOutOnce() throws {
        for stallWrite in [true, false] {
            let (url, source) = try fixture()
            defer { try? FileManager.default.removeItem(at: url) }
            let failure = expectation(description: "Stalled upload expires once")
            let transport = Transport()
            let worker = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 5,
                writeTimeout: 0.05, resultTimeout: 0.05,
                transport: { packet, done in
                    _ = transport.send(packet, done: done)
                    if !stallWrite { done(true) }
                    return true
                }, onCompleted: { _ in XCTFail("No server result") },
                onFailure: { failure.fulfill() })
            XCTAssertTrue(worker.start())
            wait(for: [failure], timeout: 2)
            XCTAssertEqual(transport.commands, stallWrite ? [101] : [101, 102, 104])
            transport.finish(0) // late success cannot revive the expired attempt
            XCTAssertFalse(worker.enqueue(result))
            XCTAssertFalse(worker.start())
            XCTAssertEqual(try Data(contentsOf: url), Data([0, 1, 2, 3, 4]))
        }
    }

    private final class Transport: @unchecked Sendable {
        let lock = NSLock()
        var packets: [AppleFileCopyMessage] = []
        var callbacks: [@Sendable (Bool) -> Void] = []
        func send(_ packet: AppleFileCopyMessage, done: @escaping @Sendable (Bool) -> Void) -> Bool {
            lock.lock(); defer { lock.unlock() }
            packets.append(packet); callbacks.append(done)
            return true
        }
        func finish(_ index: Int, success: Bool = true) {
            lock.lock(); let callback = callbacks[index]; lock.unlock()
            callback(success)
        }
        var commands: [UInt16] { lock.lock(); defer { lock.unlock() }; return packets.map(\.command) }
    }
    private func fixture() throws -> (URL, AppleFileCopySendSession.Source) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("send-worker-\(UUID())")
        try Data([0, 1, 2, 3, 4]).write(to: url)
        var header = Data(repeating: 0, count: 104)
        header[0] = 1; header[49] = 5
        let item = AppleFileCopyItem(catalogHeader: header, level: 0, wireName: "QA",
            symbolicLinkTarget: nil, extensions: Data())
        return (url, .init(item: item, dataURL: url, resourceURL: nil))
    }
    private var result: AppleFileCopyMessage {
        .init(version: 1, command: 200, sessionID: 7, body: Data([0, 0, 0, 0, 0]))
    }

    func testOnePacketInFlightAndCompletionRequiresRemoteResultAndFinalWrite() throws {
        let (url, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "send-worker-test")
        let transport = Transport()
        let completed = expectation(description: "Remote result plus last local write")
        let worker = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 5,
            blockSize: 2, queue: queue, transport: transport.send,
            onCompleted: { name in XCTAssertEqual(name, Data()); completed.fulfill() },
            onFailure: { XCTFail("Unexpected send failure") })
        XCTAssertTrue(worker.start())
        XCTAssertFalse(worker.start())
        queue.sync {}
        XCTAssertEqual(transport.commands, [101])
        for index in 0..<4 {
            transport.finish(index)
            queue.sync {}
            XCTAssertEqual(transport.commands.count, index + 2)
            transport.finish(index) // duplicate completion must not read another block
            queue.sync {}
            XCTAssertEqual(transport.commands.count, index + 2)
        }
        XCTAssertEqual(transport.commands, [101, 102, 102, 102, 104])
        XCTAssertTrue(worker.enqueue(result))
        queue.sync {}
        XCTAssertTrue(worker.enqueue(.init(version: 1, command: 300, sessionID: 7,
            body: Data(repeating: 0, count: 8)))) // remains open until last local write
        transport.finish(4)
        wait(for: [completed], timeout: 2)
        XCTAssertFalse(worker.enqueue(result))
        XCTAssertEqual(try Data(contentsOf: url), Data([0, 1, 2, 3, 4]))
    }

    func testFailedWriteStopsReadingAndCancelSuppressesLateCallbacks() throws {
        for cancel in [false, true] {
            let (url, source) = try fixture()
            defer { try? FileManager.default.removeItem(at: url) }
            let queue = DispatchQueue(label: "send-worker-failure-test")
            let transport = Transport()
            let failure = expectation(description: "Only active write failure reports failure")
            failure.isInverted = cancel
            let worker = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 5,
                writeTimeout: 0.02, resultTimeout: 0.02, queue: queue, transport: transport.send,
                onCompleted: { _ in XCTFail("Unexpected completion") }, onFailure: { failure.fulfill() })
            XCTAssertTrue(worker.start()); queue.sync {}
            if cancel { worker.cancel(); queue.sync {} }
            transport.finish(0, success: false); queue.sync {}
            transport.finish(0); queue.sync {}
            wait(for: [failure], timeout: cancel ? 0.05 : 2)
            XCTAssertEqual(transport.commands, [101])
            XCTAssertFalse(worker.enqueue(result))
            XCTAssertEqual(try Data(contentsOf: url), Data([0, 1, 2, 3, 4]))
        }
    }

    func testRejectedAdmissionWinsOverSynchronousCompletion() throws {
        let (url, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = DispatchQueue(label: "send-worker-rejected-test")
        let failure = expectation(description: "Rejected admission")
        let worker = try AppleFileCopySendWorker(sessionID: 7, sources: [source], maximumBytes: 5,
            queue: queue, transport: { packet, done in
                XCTAssertEqual(packet.command, 101)
                done(true)
                return false
            }, onCompleted: { _ in XCTFail("Rejected upload cannot complete") },
            onFailure: { failure.fulfill() })
        XCTAssertTrue(worker.start())
        wait(for: [failure], timeout: 2)
        queue.sync {}
        XCTAssertFalse(worker.start())
        XCTAssertFalse(worker.enqueue(result))
    }
}
