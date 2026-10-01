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

    @MainActor
    func testPanCancelsQueuedWheelsWhileKeyboardAndResumedScrollStillWork() throws {
        let ready = expectation(description: "Pan listener ready")
        let connected = expectation(description: "Pan session connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let suite = "test.aetherscreens.pan.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DeviceStore(userDefaults: defaults, legacySources: [])
        let session = SessionViewModel(device: RemoteDevice(name: "Pan transport QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, deviceStore: store)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        session.trackpadEngine.beginDrag()
        for _ in 0..<300 { session.client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: 10, y: 10) }
        waitUntil { server.pointers.filter { $0.mask == 1 }.count >= 300 }
        let released = expectation(description: "Pan releases remote mouse")
        server.onPointer = { if $0.mask == 0 { server.onPointer = nil; released.fulfill() } }
        session.isPanningViewport = true
        let key = expectation(description: "Keyboard remains usable during local pan")
        server.onKey = { if $0.down && $0.key == 97 { server.onKey = nil; key.fulfill() } }
        session.client.sendKeyEvent(down: true, keySym: 97)
        session.client.sendKeyEvent(down: false, keySym: 97)
        // The key receipt is a TCP barrier after switching modes; earlier bytes
        // already transmitted before cancellation are not queued old work.
        wait(for: [released, key], timeout: 1)
        let unwanted = expectation(description: "Pointer input continues while panning")
        unwanted.isInverted = true
        server.onPointer = { _ in server.onPointer = nil; unwanted.fulfill() }
        session.trackpadEngine.handleTap()
        session.sendNativePointer(buttonMask: .left, x: 10, y: 10)
        session.client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 10)
        wait(for: [unwanted], timeout: 0.2)
        // Observe's global input flag must not reopen the pointer gate when
        // control resumes while the local Pan mode is still selected.
        session.isObserveOnly = true
        session.isObserveOnly = false
        let nestedPointer = expectation(description: "Observe exit reopens mouse during Pan")
        nestedPointer.isInverted = true
        server.onPointer = { _ in server.onPointer = nil; nestedPointer.fulfill() }
        let restoredKey = expectation(description: "Observe exit restores keyboard during Pan")
        server.onKey = { if $0.down && $0.key == 98 { server.onKey = nil; restoredKey.fulfill() } }
        session.client.sendPointerEvent(buttonMask: .scrollDown, x: 10, y: 10)
        session.client.sendKeyEvent(down: true, keySym: 98)
        session.client.sendKeyEvent(down: false, keySym: 98)
        wait(for: [restoredKey, nestedPointer], timeout: 0.2)
        session.isPanningViewport = false
        let fresh = expectation(description: "Fresh scrolling resumes without old backlog delay")
        server.onPointer = { if $0.mask == RFBConstants.ButtonMask.scrollUp.rawValue { server.onPointer = nil; fresh.fulfill() } }
        session.client.sendPointerEvent(buttonMask: .scrollUp, x: 12, y: 12)
        wait(for: [fresh], timeout: 0.5)
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
    struct Key { let down: Bool; let key: UInt32 }
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
    private var keyHandler: ((Key) -> Void)?
    var onKey: ((Key) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return keyHandler }
        set { lock.lock(); keyHandler = newValue; lock.unlock() }
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
    func stop() { onPointer = nil; onKey = nil; connection?.cancel(); listener.cancel() }
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
            case 4:
                self.read(7) { body in
                    let key = Key(down: body[0] != 0, key: UInt32(body[3]) << 24 | UInt32(body[4]) << 16 | UInt32(body[5]) << 8 | UInt32(body[6]))
                    self.onKey?(key)
                    self.readMessage()
                }
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
