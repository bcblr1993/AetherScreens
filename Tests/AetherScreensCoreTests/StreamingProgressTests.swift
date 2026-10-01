import XCTest
import Network
@testable import AetherScreensCore

final class StreamingProgressTests: XCTestCase {
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
    init(ready: @escaping () -> Void) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue)
            connection.send(content: Data("RFB 003.008\n".utf8), completion: .contentProcessed { _ in
                Self.read(connection, count: 12) {
                    connection.send(content: Data([1, 1]), completion: .contentProcessed { _ in
                        Self.read(connection, count: 1) {
                            connection.send(content: Data([0, 0, 0, 0]), completion: .contentProcessed { _ in
                                Self.read(connection, count: 1) {
                                    var initial = Data([4, 0, 4, 0])
                                    initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                                    initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                                    connection.send(content: initial, completion: .contentProcessed { _ in
                                        // Announce the initial display layout before any visible pixels.
                                        var frames = Data([0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 4, 0, 255, 255, 254, 204,
                                                           1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0])
                                        for _ in 0..<2 {
                                            frames.append(contentsOf: [0, 0, 0, 1, 0, 0, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0])
                                            frames.append(Data(repeating: 42, count: 1024 * 1024 * 4))
                                        }
                                        connection.send(content: frames, completion: .contentProcessed { _ in })
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
    private static func read(_ connection: NWConnection, count: Int, done: @escaping @Sendable () -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, data?.count == count else { return }
            done()
        }
    }
    func stop() {
        lock.lock(); let active = connections; lock.unlock()
        active.forEach { $0.cancel() }; listener.cancel()
    }
}
