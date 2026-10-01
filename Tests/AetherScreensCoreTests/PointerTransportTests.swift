import XCTest
import Network
import zlib
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

    @MainActor
    func testDisplaySwitchReleasesAtOriginalPositionAndCancelsScrollBacklog() throws {
        let ready = expectation(description: "Display-switch listener ready")
        let connected = expectation(description: "Display-switch connection ready")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Display switch QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true)
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        defer { session.endSession() }
        wait(for: [connected], timeout: 3)
        let layout = RFBDisplayLayout(width: 16, height: 16, screens: [
            .init(id: 0, x: 0, y: 0, width: 8, height: 16, flags: 0),
            .init(id: 1, x: 8, y: 0, width: 8, height: 16, flags: 0)
        ])
        session.multiDisplayManager.updateFromLayout(layout)
        session.multiDisplayManager.selectDisplay(id: 2)
        waitUntil { session.activeCropRect?.minX == 8 }
        session.trackpadEngine.beginDrag()
        waitUntil { server.pointers.last?.mask == 1 }
        let held = try XCTUnwrap(server.pointers.last)
        XCTAssertGreaterThanOrEqual(held.x, 8)
        for _ in 0..<300 { session.client.sendPointerEvent(buttonMask: [.left, .scrollDown], x: held.x, y: held.y) }
        waitUntil { server.pointers.filter { $0.mask == 1 }.count >= 301 }
        let beforeSwitch = server.pointers.count
        session.multiDisplayManager.selectDisplay(id: 1)
        waitUntil { session.activeCropRect?.minX == 0 }
        let barrier = expectation(description: "Keyboard barrier after display switch")
        server.onKey = { if $0.down && $0.key == 97 { server.onKey = nil; barrier.fulfill() } }
        session.client.sendKeyEvent(down: true, keySym: 97)
        session.client.sendKeyEvent(down: false, keySym: 97)
        wait(for: [barrier], timeout: 1)
        let released = try XCTUnwrap(server.pointers.dropFirst(beforeSwitch).first { $0.mask == 0 })
        XCTAssertEqual(released.x, held.x, "Release must use the last transmitted global position, before translating into the next display")
        XCTAssertEqual(released.y, held.y)
        let stale = expectation(description: "Old wheel reaches newly selected display")
        stale.isInverted = true
        let fresh = expectation(description: "New display scroll bypasses cancelled backlog")
        server.onPointer = { pointer in
            if pointer.mask & RFBConstants.ButtonMask.scrollDown.rawValue != 0 { stale.fulfill() }
            if pointer.mask == RFBConstants.ButtonMask.scrollUp.rawValue {
                XCTAssertLessThan(pointer.x, 8)
                fresh.fulfill()
            }
        }
        session.sendNativePointer(buttonMask: .scrollUp, x: 3, y: 4)
        wait(for: [fresh, stale], timeout: 0.5)
        // A duplicate layout callback must not cancel an ongoing gesture.
        server.onPointer = nil
        session.trackpadEngine.beginDrag()
        waitUntil { server.pointers.last?.mask == 1 }
        let unchangedGeneration = session.inputGeneration
        let unexpectedRelease = expectation(description: "Duplicate layout releases mouse")
        unexpectedRelease.isInverted = true
        server.onPointer = { if $0.mask == 0 { unexpectedRelease.fulfill() } }
        session.client.onDisplayLayoutReceived?(layout)
        wait(for: [unexpectedRelease], timeout: 0.2)
        XCTAssertEqual(session.inputGeneration, unchangedGeneration)
        server.onPointer = nil
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

@MainActor
final class ClipboardSessionTests: XCTestCase {
    func testEndedSessionRejectsQueuedAndLaterClipboardDelivery() throws {
        let ready = expectation(description: "Clipboard listener ready")
        let connected = expectation(description: "Clipboard session connected")
        let delivered = expectation(description: "Actual server clipboard delivered")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "actual server clipboard café" { delivered.fulfill() }
        })
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.sendClipboard("actual server clipboard café")
        wait(for: [delivered], timeout: 2)
        let uploaded = expectation(description: "Actual Latin-1 client clipboard received")
        server.onCutText = { bytes in
            XCTAssertEqual(Array(bytes), [99, 97, 102, 233, 10, 110, 97, 239, 118, 101])
            uploaded.fulfill()
        }
        XCTAssertTrue(session.client.sendCutText("café\r\nnaïve"))
        XCTAssertFalse(session.client.sendCutText("中文 😀"), "A legacy-only server must not receive corrupt UTF-8 as Latin-1")
        session.client.setInputEnabled(false)
        XCTAssertFalse(session.client.sendCutText("blocked during Observe"))
        session.client.setInputEnabled(true)
        wait(for: [uploaded], timeout: 2)
        session.client.onClipboardReceived?("queued before end")
        session.endSession()
        session.client.onClipboardReceived?("delivered after end")
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["actual server clipboard café"])
    }

    func testReconnectRejectsOldClipboardButAcceptsNewServerText() throws {
        let ready = expectation(description: "Reconnect clipboard listener ready")
        let connected = expectation(description: "First clipboard session connected")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let delivered = expectation(description: "New server clipboard delivered")
        let session = SessionViewModel(device: RemoteDevice(name: "Reconnect clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "new session text" { delivered.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        session.client.onClipboardReceived?("queued before reconnect")
        let reconnected = expectation(description: "New clipboard session connected")
        session.client.onStateChanged = { if $0 == .connected { reconnected.fulfill() } }
        session.reconnectSession()
        wait(for: [reconnected], timeout: 3)
        server.sendClipboard("new session text")
        wait(for: [delivered], timeout: 2)
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["new session text"])
    }

    func testExtendedUnicodeClipboardRoundTripAndObserveRequestSuppression() throws {
        let ready = expectation(description: "Extended clipboard listener ready")
        let connected = expectation(description: "Extended clipboard session ready")
        let caps = expectation(description: "Client capabilities received on TCP")
        let uploaded = expectation(description: "Compressed Unicode uploaded on TCP")
        let downloaded = expectation(description: "Compressed Unicode downloaded through session")
        let forbidden = expectation(description: "Observe provides clipboard after delayed request")
        forbidden.isInverted = true
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Extended clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "远端 😀\nsecond line" { downloaded.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.onExtendedClipboard = { (flags: UInt32, payload: Data) in
            if flags == 0x1F000001 {
                XCTAssertEqual(payload, Data([0, 0, 0, 0]))
                caps.fulfill()
            } else if flags == 0x08000001 {
                server.sendExtendedClipboard(flags: 0x02000001)
            } else if flags == 0x10000001 {
                do {
                    let plain = try ClipboardWireData.decompress(payload)
                    let expected = Data("客户端 中文 😀\r\nsecond line\r\n".utf8) + Data([0])
                    let declaredSize = plain.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    XCTAssertEqual(declaredSize, UInt32(expected.count))
                    XCTAssertEqual(Data(plain.dropFirst(4)), expected)
                    uploaded.fulfill()
                } catch { XCTFail("Cannot read actual compressed clipboard: \(error)") }
            }
        }
        server.sendExtendedClipboard(flags: 0x1F000001, payload: Data([0, 0, 0, 0]))
        wait(for: [caps], timeout: 2)
        XCTAssertTrue(session.client.sendCutText("客户端 中文 😀\nsecond line\n"))
        wait(for: [uploaded], timeout: 2)
        let remotePayload = try ClipboardWireData.compress("远端 😀\r\nsecond line")
        session.isObserveOnly = true
        server.onExtendedClipboard = { flags, _ in
            if flags == 0x10000001 { forbidden.fulfill() }
            if flags == 0x02000001 { server.sendExtendedClipboard(flags: 0x10000001, payload: remotePayload) }
        }
        XCTAssertFalse(session.client.sendCutText("Observe must not upload"))
        server.sendExtendedClipboard(flags: 0x02000001)
        server.sendExtendedClipboard(flags: 0x08000001)
        // The received download is a barrier after the delayed server request.
        wait(for: [downloaded], timeout: 2)
        wait(for: [forbidden], timeout: 0.15)
        XCTAssertEqual(inbox.texts, ["远端 😀\nsecond line"])
    }

    func testTruncatedCapabilityMessageDoesNotEnableUnicodeUploads() throws {
        let ready = expectation(description: "Malformed capabilities listener ready")
        let connected = expectation(description: "Malformed capabilities connection ready")
        let barrier = expectation(description: "Following legacy clipboard decoded")
        let nonTextBarrier = expectation(description: "Non-text capabilities followed by legacy text")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let session = SessionViewModel(device: RemoteDevice(name: "Malformed clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            if text == "capability barrier" { barrier.fulfill() }
            else if text == "non-text capability barrier" { nonTextBarrier.fulfill() }
            else { XCTFail("Unexpected fixture clipboard text") }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        // Text capabilities require a four-byte size after their flags.
        server.sendExtendedClipboard(flags: 0x1F000001)
        server.sendClipboard("capability barrier")
        wait(for: [barrier], timeout: 2)
        XCTAssertFalse(session.client.sendCutText("中文 😀"))
        server.sendExtendedClipboard(flags: 0x1F000002, payload: Data([0, 0, 0, 0]))
        server.sendClipboard("non-text capability barrier")
        wait(for: [nonTextBarrier], timeout: 2)
        XCTAssertFalse(session.client.sendCutText("中文 😀"), "RTF-only capabilities cannot enable UTF-8 text uploads")
    }

    func testUnterminatedExtendedTextDoesNotOverwriteClipboardOrBreakNextMessage() throws {
        let ready = expectation(description: "Unterminated clipboard listener ready")
        let connected = expectation(description: "Unterminated clipboard connection ready")
        let barrier = expectation(description: "Valid clipboard after malformed payload received")
        let server = try PointerWireServer(ready: { ready.fulfill() })
        defer { server.stop() }
        wait(for: [ready], timeout: 3)
        let inbox = ClipboardInbox()
        let session = SessionViewModel(device: RemoteDevice(name: "Unterminated clipboard QA", host: "127.0.0.1", port: try XCTUnwrap(server.listener.port).rawValue), password: nil, isTemporary: true, clipboardWriter: { text in
            inbox.texts.append(text)
            if text == "valid clipboard barrier" { barrier.fulfill() }
        })
        defer { session.endSession() }
        session.client.onStateChanged = { if $0 == .connected { connected.fulfill() } }
        session.startSession()
        wait(for: [connected], timeout: 3)
        server.sendExtendedClipboard(flags: 0x1F000001, payload: Data([0, 0, 0, 0]))
        server.sendExtendedClipboard(flags: 0x10000001, payload: try ClipboardWireData.compress("malformed 中文", terminated: false))
        server.sendClipboard("valid clipboard barrier")
        wait(for: [barrier], timeout: 2)
        drainCallbacks()
        XCTAssertEqual(inbox.texts, ["valid clipboard barrier"])
    }

    private func drainCallbacks() {
        let drained = expectation(description: "Clipboard UI tasks drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

@MainActor
private final class ClipboardInbox {
    var texts: [String] = []
}

private enum ClipboardWireData {
    static func compress(_ text: String, terminated: Bool = true) throws -> Data {
        let bytes = Data(text.utf8) + (terminated ? Data([0]) : Data())
        var plain = Data()
        plain.append(contentsOf: withUnsafeBytes(of: UInt32(bytes.count).bigEndian) { Array($0) })
        plain.append(bytes)
        var length = compressBound(uLong(plain.count))
        var compressed = [UInt8](repeating: 0, count: Int(length))
        let status = plain.withUnsafeBytes { compress2(&compressed, &length, $0.bindMemory(to: UInt8.self).baseAddress!, uLong(plain.count), Z_DEFAULT_COMPRESSION) }
        XCTAssertEqual(status, Z_OK)
        return Data(compressed.prefix(Int(length)))
    }
    static func decompress(_ compressed: Data) throws -> Data {
        var length: uLongf = 1_048_576
        var bytes = [UInt8](repeating: 0, count: Int(length))
        let status = compressed.withUnsafeBytes { uncompress(&bytes, &length, $0.bindMemory(to: UInt8.self).baseAddress!, uLong(compressed.count)) }
        guard status == Z_OK else { throw NSError(domain: "ClipboardWireFixture", code: Int(status)) }
        return Data(bytes.prefix(Int(length)))
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
    private var cutTextHandler: ((Data) -> Void)?
    var onCutText: ((Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return cutTextHandler }
        set { lock.lock(); cutTextHandler = newValue; lock.unlock() }
    }
    private var extendedClipboardHandler: ((UInt32, Data) -> Void)?
    var onExtendedClipboard: ((UInt32, Data) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return extendedClipboardHandler }
        set { lock.lock(); extendedClipboardHandler = newValue; lock.unlock() }
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
    func stop() { onPointer = nil; onKey = nil; onCutText = nil; onExtendedClipboard = nil; connection?.cancel(); listener.cancel() }
    func sendClipboard(_ text: String) {
        guard let body = text.data(using: .isoLatin1, allowLossyConversion: false) else { XCTFail("Legacy fixture text must be Latin-1"); return }
        var packet = Data([3, 0, 0, 0])
        packet.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) })
        packet.append(body)
        send(packet)
    }
    func sendExtendedClipboard(flags: UInt32, payload: Data = Data()) {
        var body = Data()
        body.append(contentsOf: withUnsafeBytes(of: flags.bigEndian) { Array($0) })
        body.append(payload)
        var packet = Data([3, 0, 0, 0])
        packet.append(contentsOf: withUnsafeBytes(of: Int32(-body.count).bigEndian) { Array($0) })
        packet.append(body)
        send(packet)
    }
    private func send(_ data: Data) { connection?.send(content: data, completion: .contentProcessed { _ in }) }
    private func read(_ count: Int, accumulated: Data = Data(), done: @escaping (Data) -> Void) {
        if accumulated.count == count { done(accumulated); return }
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, finished, error in
            guard let self, self.connection === connection, let data, !data.isEmpty, error == nil else { return }
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
            case 6:
                self.read(7) { header in
                    let length = header.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    let signed = Int32(bitPattern: length)
                    let size = abs(Int64(signed))
                    guard size <= 1_048_576 else { XCTFail("Unexpected clipboard size"); return }
                    self.read(Int(size)) { bytes in
                        if signed < 0 {
                            guard bytes.count >= 4 else { XCTFail("Truncated clipboard flags"); return }
                            let flags = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                            self.onExtendedClipboard?(flags, Data(bytes.dropFirst(4)))
                        } else { self.onCutText?(bytes) }
                        self.readMessage()
                    }
                }
            default: XCTFail("Unexpected client message in pointer test: \(type[0])")
            }
        }
    }
}
