import XCTest
import Network
@testable import AetherScreensCore

final class DisplayLayoutTransportTests: XCTestCase {
    func testLayoutChangesKeepPixelsAndRejectedResizeDoesNotCorruptNextFrame() throws {
        let ready = expectation(description: "Listener ready")
        let server = try DisplayLayoutServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        defer { client.disconnect() }
        let completed = expectation(description: "All wire updates decoded")
        completed.expectedFulfillmentCount = 3
        let observations = DisplayObservations()
        client.onDisplayLayoutReceived = { observations.layout($0, pixel: client.framebuffer.pixels.first) }
        client.onFrameUpdated = { observations.frame(client.framebuffer.pixels.first); completed.fulfill() }
        client.connect()
        wait(for: [completed], timeout: 5)
        let snapshot = observations.snapshot
        XCTAssertEqual(snapshot.layouts.count, 3, "Rejected resize must not replace a valid layout")
        XCTAssertEqual(snapshot.layouts[1].screens.first?.id, UInt32.max)
        XCTAssertEqual(snapshot.layouts[1].screens.first?.flags, 0x80000000)
        XCTAssertEqual(snapshot.layoutPixels, [0, 42, 0], "Same-size layout update must retain pixels")
        XCTAssertEqual(snapshot.frames, [42, 99, 77], "Layout acknowledgements must not be reported as a received pixel frame")
        XCTAssertEqual(client.framebuffer.width, 6)
        XCTAssertEqual(client.state, .connected)
    }

    func testDecoderRejectsTruncationDuplicatesAndOutOfBoundsButAllowsOverlap() {
        let valid = DisplayLayoutServer.payload(ids: [0, UInt32.max])
        XCTAssertEqual(RFBDecoder.parseDisplayLayout(valid, width: 4, height: 2)?.screens.count, 2)
        XCTAssertNil(RFBDecoder.parseDisplayLayout(Data(valid.dropLast()), width: 4, height: 2))
        XCTAssertNil(RFBDecoder.parseDisplayLayout(DisplayLayoutServer.payload(ids: [0, 0]), width: 4, height: 2))
        XCTAssertNil(RFBDecoder.parseDisplayLayout(valid, width: 1, height: 2))
        XCTAssertNil(RFBDecoder.parseDisplayLayout(valid, width: 0, height: 2))
        var zeroExtent = valid
        zeroExtent[12] = 0; zeroExtent[13] = 0
        XCTAssertNil(RFBDecoder.parseDisplayLayout(zeroExtent, width: 4, height: 2))
        XCTAssertNotNil(RFBDecoder.parseDisplayLayout(Data([0, 0, 0, 0]), width: 4, height: 2))
    }
}

private final class DisplayObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var layouts: [RFBDisplayLayout] = []
    private var layoutPixels: [UInt8] = []
    private var frames: [UInt8] = []
    func layout(_ layout: RFBDisplayLayout?, pixel: UInt8?) {
        lock.lock(); defer { lock.unlock() }
        if let layout { layouts.append(layout); layoutPixels.append(pixel ?? 255) }
    }
    func frame(_ pixel: UInt8?) { lock.lock(); frames.append(pixel ?? 255); lock.unlock() }
    var snapshot: (layouts: [RFBDisplayLayout], layoutPixels: [UInt8], frames: [UInt8]) {
        lock.lock(); defer { lock.unlock() }; return (layouts, layoutPixels, frames)
    }
}

private final class DisplayLayoutServer: @unchecked Sendable {
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.display-layout-qa")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    static func payload(ids: [UInt32]) -> Data {
        var data = Data([UInt8(ids.count), 0, 0, 0])
        for id in ids {
            data.append(contentsOf: [UInt8(truncatingIfNeeded: id >> 24), UInt8(truncatingIfNeeded: id >> 16), UInt8(truncatingIfNeeded: id >> 8), UInt8(truncatingIfNeeded: id)])
            data.append(contentsOf: [0, 0, 0, 0, 0, 2, 0, 2, 128, 0, 0, 0])
        }
        return data
    }
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
                                    var initial = Data([0, 4, 0, 2])
                                    initial.append(RFBPixelFormat.standardBGRA32.serializedData)
                                    initial.append(contentsOf: [0, 0, 0, 2, 81, 65])
                                    connection.send(content: initial, completion: .contentProcessed { _ in
                                        var updates = Self.layoutUpdate(ids: [0, UInt32.max])
                                        updates.append(Self.rawUpdate(value: 42))
                                        updates.append(Self.layoutUpdate(ids: [UInt32.max]))
                                        // Failed client resize: geometry undefined, yet payload structure is valid.
                                        var rejected = Self.layoutUpdate(ids: [12], reason: 1, status: 3)
                                        rejected[8] = 0; rejected[9] = 0
                                        updates.append(rejected)
                                        updates.append(Self.rawUpdate(value: 99))
                                        var resized = Self.layoutUpdate(ids: [7])
                                        resized[9] = 6
                                        updates.append(resized)
                                        updates.append(Self.rawUpdate(value: 77, width: 6))
                                        connection.send(content: updates, completion: .contentProcessed { _ in })
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
    private static func layoutUpdate(ids: [UInt32], reason: UInt8 = 0, status: UInt8 = 0) -> Data {
        var data = Data([0, 0, 0, 1, 0, reason, 0, status, 0, 4, 0, 2, 255, 255, 254, 204])
        data.append(payload(ids: ids)); return data
    }
    private static func rawUpdate(value: UInt8, width: UInt8 = 4) -> Data {
        var data = Data([0, 0, 0, 1, 0, 0, 0, 0, 0, width, 0, 2, 0, 0, 0, 0])
        data.append(Data(repeating: value, count: Int(width) * 2 * 4)); return data
    }
    private static func read(_ connection: NWConnection, count: Int, done: @escaping @Sendable () -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            guard error == nil, data?.count == count else { return }; done()
        }
    }
    func stop() {
        lock.lock(); let active = connections; lock.unlock()
        active.forEach { $0.cancel() }; listener.cancel()
    }
}
