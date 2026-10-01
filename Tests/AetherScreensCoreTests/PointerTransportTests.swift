import XCTest
import Network
@testable import AetherScreensCore

final class PointerTransportTests: XCTestCase {
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

    private func connectedPair() throws -> (PointerWireServer, RFBClient) {
        let ready = expectation(description: "Loopback listener ready")
        let connected = expectation(description: "RFB handshake completed")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        wait(for: [ready], timeout: 3)
        let client = RFBClient(host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue)
        client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        client.connect()
        wait(for: [connected], timeout: 3)
        return (server, client)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in predicate() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed)
    }
}

/// Inspects real TCP messages after a minimal RFB handshake; no client send hooks.
private final class PointerWireServer: @unchecked Sendable {
    struct Pointer { let mask: UInt8; let x: UInt16; let y: UInt16 }
    let listener: NWListener
    private let queue = DispatchQueue(label: "aetherscreens.pointer-wire-qa")
    private let lock = NSLock()
    private var received: [Pointer] = []
    private var connection: NWConnection?
    private var pointerHandler: ((Pointer) -> Void)?
    var onPointer: ((Pointer) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return pointerHandler }
        set { lock.lock(); pointerHandler = newValue; lock.unlock() }
    }
    var pointers: [Pointer] { lock.lock(); defer { lock.unlock() }; return received }

    init(ready: @escaping () -> Void) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connection = connection
            connection.start(queue: self.queue)
            self.send(Data("RFB 003.008\n".utf8))
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
    func stop() { connection?.cancel(); listener.cancel() }
    private func send(_ data: Data) { connection?.send(content: data, completion: .contentProcessed { _ in }) }
    private func read(_ count: Int, accumulated: Data = Data(), done: @escaping (Data) -> Void) {
        if accumulated.count == count { done(accumulated); return }
        connection?.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, finished, error in
            guard let self, let data, !data.isEmpty, error == nil else { return }
            let next = accumulated + data
            if next.count == count { done(next) }
            else if !finished { self.read(count, accumulated: next, done: done) }
        }
    }
    private func readMessage() {
        read(1) { [weak self] type in
            guard let self else { return }
            switch type[0] {
            case 0: self.read(19) { _ in self.readMessage() }
            case 2:
                self.read(3) { header in
                    let count = Int(header[1]) << 8 | Int(header[2])
                    self.read(count * 4) { _ in self.readMessage() }
                }
            case 3: self.read(9) { _ in self.readMessage() }
            case 4: self.read(7) { _ in self.readMessage() }
            case 5:
                self.read(5) { body in
                    let pointer = Pointer(mask: body[0], x: UInt16(body[1]) << 8 | UInt16(body[2]), y: UInt16(body[3]) << 8 | UInt16(body[4]))
                    self.lock.lock(); self.received.append(pointer); self.lock.unlock()
                    self.onPointer?(pointer)
                    self.readMessage()
                }
            default: XCTFail("Unexpected client message in pointer test: \(type[0])")
            }
        }
    }
}
