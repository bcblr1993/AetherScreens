import Foundation
import CoreGraphics
import CoreImage
import VideoToolbox
import RDPKit

/// Client managing an RDP remote desktop session using RDPKit.
public final class RDPClient: @unchecked Sendable {

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case authenticating
        case connected
        case failed(String)
    }

    public let host: String
    public let port: UInt16
    public var username: String?
    public var password: String?
    public let framebuffer: Framebuffer

    public var isNativeDisplaySession: Bool { false }
    public var fileCopyTransportGeneration: UUID? { nil }

    public private(set) var state: State = .disconnected {
        didSet {
            onStateChanged?(state)
        }
    }

    public func simulateStateForTesting(_ newState: State) {
        state = newState
    }

    public func simulateAudioSampleForTesting(_ sample: RDPAudioSample) {
        onAudioSampleReceived?(sample)
    }

    public func simulateClipboardFilesForTesting(_ urls: [URL]) {
        onClipboardFilesReceived?(urls)
    }

    // Callbacks
    public var onStateChanged: (@Sendable (State) -> Void)?
    public var onFrameUpdated: (@Sendable () -> Void)?
    public var onDisplayLayoutReceived: (@Sendable (RFBDisplayLayout?) -> Void)?
    public var onClipboardReceived: (@Sendable (String) -> Void)?
    public var onClipboardFilesReceived: (@Sendable ([URL]) -> Void)?
    public var onCursorReceived: (@Sendable (RFBRemoteCursor) -> Void)?
    public var onTransportRTT: (@Sendable (Double) -> Void)?
    public var onAudioSampleReceived: (@Sendable (RDPAudioSample) -> Void)?
    public var audioEnabled: Bool = true

    private var connectionTask: Task<Void, Never>?
    private var activeCancellation: RDPConnectionCancellation?
    private var inputSession: RDPInputSession?
    private var clipboardSession: RDPClipboardSession?
    private var displayControlSession: RDPDisplayControlSession?
    private let fileDownloader = RDPClipboardFileDownloader()
    public private(set) var lastPointerPosition: (UInt16, UInt16)?
    public private(set) var lastPublishedFiles: [RDPClipboardLocalFile] = []
    private var lastButtons: RFBConstants.ButtonMask = []
    private var keyTranslator = RDPKeyTranslator()
    private let inputLock = NSLock()
    private var inputEnabled = true
    private var pointerInputEnabled = true
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])

    public init(
        host: String,
        port: UInt16 = 3389,
        username: String? = nil,
        password: String? = nil,
        width: Int = 1920,
        height: Int = 1080,
        audioEnabled: Bool = true
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.audioEnabled = audioEnabled
        self.framebuffer = Framebuffer(width: width, height: height)
    }

    public func setInputEnabled(_ enabled: Bool) {
        inputLock.lock()
        defer { inputLock.unlock() }
        inputEnabled = enabled
    }

    public func setPointerInputEnabled(_ enabled: Bool) {
        inputLock.lock()
        defer { inputLock.unlock() }
        pointerInputEnabled = enabled
    }

    public func cancelPendingWheelEvents() {
        // Dispatched immediately in RDP
    }

    public func connect() {
        switch state {
        case .disconnected, .failed: break
        default: return
        }

        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pass = password ?? ""

        guard !user.isEmpty else {
            state = .failed("Windows RDP requires a valid username and account credential.")
            return
        }

        state = .connecting
        AppLogger.shared.info("Initiating RDP connection to \(host):\(port) as \(user)", category: "RDP")

        let cancellation = RDPConnectionCancellation()
        self.activeCancellation = cancellation
        let isAudioEnabled = self.audioEnabled

        connectionTask = Task.detached { [weak self, host, port, user, pass, isAudioEnabled] in
            guard let self else { return }

            let credentials: RDPCredentials?
            do {
                credentials = try RDPCredentials.validated(
                    username: user,
                    domain: nil,
                    password: pass
                )
            } catch {
                self.transition(to: .failed("Invalid RDP credentials: \(error.localizedDescription)"))
                return
            }

            let initialWidth = UInt16(self.framebuffer.width)
            let initialHeight = UInt16(self.framebuffer.height)

            let configuration = RDPConnectionConfiguration(
                host: host,
                port: port,
                credentials: credentials,
                timeoutSeconds: 15,
                hideCertificateWarnings: true,
                graphicsFrameCaptureLimit: nil,
                desktopWidth: initialWidth,
                desktopHeight: initialHeight,
                clipboardEnabled: true,
                audioPlaybackEnabled: isAudioEnabled,
                earlyUserAuthorizationEnabled: false,
                graphicsCapabilityProfile: .automatic
            )

            let decodeQueue = RDPLatestFrameDecodeQueue(
                shouldCancel: { cancellation.isCancelled },
                onDecoded: { [weak self] presentation, _, _, _ in
                    guard let self else { return }
                    self.processDecodedFrame(presentation.imageBuffer)
                },
                onDecodeFailed: { _, err in
                    AppLogger.shared.error("RDP decode error: \(err)", category: "RDP")
                },
                onSkippedFrames: { _, _ in }
            )

            let report = RDPPreflightClient().run(
                configuration: configuration,
                onGraphicsFrame: { frame in
                    try decodeQueue.submitAndWait(
                        frame,
                        receivedAt: Date(),
                        shouldContinue: { !cancellation.isCancelled && !Task.isCancelled }
                    ).requireDecoded()
                },
                onRemotePointer: nil,
                onInputReady: { [weak self] session in
                    guard let self else { return }
                    self.inputLock.lock()
                    self.inputSession = session
                    self.inputLock.unlock()
                    self.transition(to: .connected)
                },
                onDisplayControlReady: { [weak self] session in
                    guard let self else { return }
                    self.inputLock.lock()
                    self.displayControlSession = session
                    self.inputLock.unlock()
                },
                onClipboardReady: { [weak self] session in
                    guard let self else { return }
                    self.inputLock.lock()
                    self.clipboardSession = session
                    self.inputLock.unlock()
                },
                onClipboardText: { [weak self] text in
                    guard let self else { return }
                    self.onClipboardReceived?(text)
                },
                onClipboardFileGroupDescriptor: { [weak self] descriptor in
                    guard let self else { return }
                    self.inputLock.lock()
                    let session = self.clipboardSession
                    self.inputLock.unlock()
                    guard let session else { return }
                    self.fileDownloader.downloadFiles(descriptors: descriptor.descriptors, session: session) { [weak self] urls in
                        self?.onClipboardFilesReceived?(urls)
                    }
                },
                onClipboardFileContents: { [weak self] response in
                    self?.fileDownloader.handleFileContentsResponse(response)
                },
                onAudioSample: { [weak self] sample in
                    self?.onAudioSampleReceived?(sample)
                },
                cancellation: cancellation
            )

            if cancellation.isCancelled {
                self.transition(to: .disconnected)
            } else if report.status == "failure" {
                let errDesc = report.error ?? "Connection failed"
                self.transition(to: .failed(errDesc))
            } else {
                self.transition(to: .disconnected)
            }
        }
    }

    public func disconnect() {
        inputLock.lock()
        activeCancellation?.cancel()
        activeCancellation = nil
        inputSession = nil
        clipboardSession = nil
        displayControlSession = nil
        keyTranslator = RDPKeyTranslator()
        connectionTask?.cancel()
        connectionTask = nil
        inputLock.unlock()

        fileDownloader.cancel()

        transition(to: .disconnected)
        AppLogger.shared.info("Disconnected RDP session with \(host)", category: "RDP")
    }

    public func updateDesktopResolution(width: Int, height: Int) {
        let size = Self.displayControlSize(width: width, height: height)
        inputLock.lock()
        let dc = displayControlSession
        inputLock.unlock()
        dc?.sendSingleMonitorLayout(width: UInt32(size.width), height: UInt32(size.height))
    }

    /// MS-RDPEDISP requires 200...8192 pixels per side and an even width; other layouts are dropped silently.
    static func displayControlSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let clampedWidth = min(max(width, 200), 8192)
        let clampedHeight = min(max(height, 200), 8192)
        return (clampedWidth - clampedWidth % 2, clampedHeight)
    }

    private func transition(to newState: State) {
        if Thread.isMainThread {
            self.state = newState
        } else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = newState
            }
        }
    }

    private func processDecodedFrame(_ imageBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        guard width > 0, height > 0 else { return }

        if framebuffer.width != width || framebuffer.height != height {
            framebuffer.resize(newWidth: width, newHeight: height)
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        var bgraData = Data(count: width * height * 4)
        bgraData.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            imageContext.render(
                ciImage,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .BGRA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }

        framebuffer.updateRect(x: 0, y: 0, width: width, height: height, rawData: bgraData)
        onFrameUpdated?()
    }

    // MARK: - Input

    public func sendPointerEvent(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16, completion: (@Sendable () -> Void)? = nil) {
        inputLock.lock()
        defer {
            inputLock.unlock()
            completion?()
        }

        guard inputEnabled, pointerInputEnabled else { return }
        let positionChanged = lastPointerPosition?.0 != x || lastPointerPosition?.1 != y
        lastPointerPosition = (x, y)

        guard let session = inputSession else { return }

        var events: [RDPSlowPathInputEvent] = []

        // Movement
        if positionChanged {
            events.append(.pointerMove(x: x, y: y))
        }

        // Left button
        let wasLeft = lastButtons.contains(.left)
        let isLeft = buttonMask.contains(.left)
        if wasLeft != isLeft {
            events.append(.pointerButton(button: .left, isDown: isLeft, x: x, y: y))
        }

        // Right button
        let wasRight = lastButtons.contains(.right)
        let isRight = buttonMask.contains(.right)
        if wasRight != isRight {
            events.append(.pointerButton(button: .right, isDown: isRight, x: x, y: y))
        }

        // Middle button
        let wasMiddle = lastButtons.contains(.middle)
        let isMiddle = buttonMask.contains(.middle)
        if wasMiddle != isMiddle {
            events.append(.pointerButton(button: .middle, isDown: isMiddle, x: x, y: y))
        }

        // Wheel
        if buttonMask.contains(.scrollUp) {
            events.append(.verticalWheel(rotation: 120, x: x, y: y))
        } else if buttonMask.contains(.scrollDown) {
            events.append(.verticalWheel(rotation: -120, x: x, y: y))
        }

        lastButtons = buttonMask

        if !events.isEmpty {
            session.send(events)
        }
    }

    public func sendKeyEvent(down: Bool, keySym: UInt32) {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard inputEnabled, let session = inputSession else { return }

        let events = keyTranslator.events(keySym: keySym, down: down)
        if !events.isEmpty { session.send(events) }
    }

    public func sendText(_ text: String) {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard inputEnabled, let session = inputSession else { return }

        var events: [RDPSlowPathInputEvent] = []
        for char in text.utf16 {
            events.append(.unicode(codeUnit: char, isReleased: false))
            events.append(.unicode(codeUnit: char, isReleased: true))
        }
        session.send(events)
    }

    public func sendCutText(_ text: String) -> String? {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard let clipboard = clipboardSession else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        clipboard.publishLocalUnicodeText(normalized)
        return "Copied text to remote clipboard."
    }

    public func publishLocalFiles(_ files: [RDPClipboardLocalFile]) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }

        guard state == .connected || clipboardSession != nil else { return false }
        lastPublishedFiles = files
        clipboardSession?.publishLocalFiles(files)
        return true
    }

    static func mapKeySymToScancode(_ keySym: UInt32) -> RDPKeyboardScancode? {
        switch keySym {
        case 0xff0d: return RDPKeyboardScancode(code: 0x1C) // Return
        case 0xff1b: return RDPKeyboardScancode(code: 0x01) // Escape
        case 0xff08: return RDPKeyboardScancode(code: 0x0E) // Backspace
        case 0xff09: return RDPKeyboardScancode(code: 0x0F) // Tab
        case 0x0020: return RDPKeyboardScancode(code: 0x39) // Space
        case 0xffff: return RDPKeyboardScancode(code: 0x53, isExtended: true) // Delete
        case 0xffe1, 0xffe2: return RDPKeyboardScancode(code: 0x2A) // Shift
        case 0xffe3, 0xffe4: return RDPKeyboardScancode(code: 0x1D) // Control
        case 0xffe9, 0xffea: return RDPKeyboardScancode(code: 0x38) // Alt
        case 0xffeb, 0xffec: return RDPKeyboardScancode(code: 0x5B, isExtended: true) // Windows / Super

        // Navigation
        case 0xff51: return RDPKeyboardScancode(code: 0x4B, isExtended: true) // Left
        case 0xff52: return RDPKeyboardScancode(code: 0x48, isExtended: true) // Up
        case 0xff53: return RDPKeyboardScancode(code: 0x4D, isExtended: true) // Right
        case 0xff54: return RDPKeyboardScancode(code: 0x50, isExtended: true) // Down
        case 0xff50: return RDPKeyboardScancode(code: 0x47, isExtended: true) // Home
        case 0xff57: return RDPKeyboardScancode(code: 0x4F, isExtended: true) // End
        case 0xff55: return RDPKeyboardScancode(code: 0x49, isExtended: true) // PageUp
        case 0xff56: return RDPKeyboardScancode(code: 0x51, isExtended: true) // PageDown
        case 0xff63: return RDPKeyboardScancode(code: 0x52, isExtended: true) // Insert

        // Alphabet (lowercase & uppercase) - essential for Ctrl+C, Ctrl+V, Ctrl+A, Ctrl+Z, etc.
        case 0x0061, 0x0041: return RDPKeyboardScancode(code: 0x1E) // A
        case 0x0062, 0x0042: return RDPKeyboardScancode(code: 0x30) // B
        case 0x0063, 0x0043: return RDPKeyboardScancode(code: 0x2E) // C
        case 0x0064, 0x0044: return RDPKeyboardScancode(code: 0x20) // D
        case 0x0065, 0x0045: return RDPKeyboardScancode(code: 0x12) // E
        case 0x0066, 0x0046: return RDPKeyboardScancode(code: 0x21) // F
        case 0x0067, 0x0047: return RDPKeyboardScancode(code: 0x22) // G
        case 0x0068, 0x0048: return RDPKeyboardScancode(code: 0x23) // H
        case 0x0069, 0x0049: return RDPKeyboardScancode(code: 0x17) // I
        case 0x006a, 0x004A: return RDPKeyboardScancode(code: 0x24) // J
        case 0x006b, 0x004B: return RDPKeyboardScancode(code: 0x25) // K
        case 0x006c, 0x004C: return RDPKeyboardScancode(code: 0x26) // L
        case 0x006d, 0x004D: return RDPKeyboardScancode(code: 0x32) // M
        case 0x006e, 0x004E: return RDPKeyboardScancode(code: 0x31) // N
        case 0x006f, 0x004F: return RDPKeyboardScancode(code: 0x18) // O
        case 0x0070, 0x0050: return RDPKeyboardScancode(code: 0x19) // P
        case 0x0071, 0x0051: return RDPKeyboardScancode(code: 0x10) // Q
        case 0x0072, 0x0052: return RDPKeyboardScancode(code: 0x13) // R
        case 0x0073, 0x0053: return RDPKeyboardScancode(code: 0x1F) // S
        case 0x0074, 0x0054: return RDPKeyboardScancode(code: 0x14) // T
        case 0x0075, 0x0055: return RDPKeyboardScancode(code: 0x16) // U
        case 0x0076, 0x0056: return RDPKeyboardScancode(code: 0x2F) // V
        case 0x0077, 0x0057: return RDPKeyboardScancode(code: 0x11) // W
        case 0x0078, 0x0058: return RDPKeyboardScancode(code: 0x2D) // X
        case 0x0079, 0x0059: return RDPKeyboardScancode(code: 0x15) // Y
        case 0x007a, 0x005A: return RDPKeyboardScancode(code: 0x2C) // Z

        // Numbers
        case 0x0031: return RDPKeyboardScancode(code: 0x02) // 1
        case 0x0032: return RDPKeyboardScancode(code: 0x03) // 2
        case 0x0033: return RDPKeyboardScancode(code: 0x04) // 3
        case 0x0034: return RDPKeyboardScancode(code: 0x05) // 4
        case 0x0035: return RDPKeyboardScancode(code: 0x06) // 5
        case 0x0036: return RDPKeyboardScancode(code: 0x07) // 6
        case 0x0037: return RDPKeyboardScancode(code: 0x08) // 7
        case 0x0038: return RDPKeyboardScancode(code: 0x09) // 8
        case 0x0039: return RDPKeyboardScancode(code: 0x0A) // 9
        case 0x0030: return RDPKeyboardScancode(code: 0x0B) // 0

        // Lock, system and keypad keys
        case 0xffe5: return RDPKeyboardScancode(code: 0x3A) // Caps Lock
        case 0xff7f: return RDPKeyboardScancode(code: 0x45) // Num Lock
        case 0xff14: return RDPKeyboardScancode(code: 0x46) // Scroll Lock
        case 0xff67: return RDPKeyboardScancode(code: 0x5D, isExtended: true) // Menu
        case 0xff61: return RDPKeyboardScancode(code: 0x37, isExtended: true) // Print Screen
        case 0xff8d: return RDPKeyboardScancode(code: 0x1C, isExtended: true) // Keypad Enter
        case 0xffaf: return RDPKeyboardScancode(code: 0x35, isExtended: true) // Keypad /
        case 0xffaa: return RDPKeyboardScancode(code: 0x37) // Keypad *
        case 0xffad: return RDPKeyboardScancode(code: 0x4A) // Keypad -
        case 0xffab: return RDPKeyboardScancode(code: 0x4E) // Keypad +
        case 0xffae: return RDPKeyboardScancode(code: 0x53) // Keypad .
        case 0xffb0: return RDPKeyboardScancode(code: 0x52) // Keypad 0
        case 0xffb1: return RDPKeyboardScancode(code: 0x4F) // Keypad 1
        case 0xffb2: return RDPKeyboardScancode(code: 0x50) // Keypad 2
        case 0xffb3: return RDPKeyboardScancode(code: 0x51) // Keypad 3
        case 0xffb4: return RDPKeyboardScancode(code: 0x4B) // Keypad 4
        case 0xffb5: return RDPKeyboardScancode(code: 0x4C) // Keypad 5
        case 0xffb6: return RDPKeyboardScancode(code: 0x4D) // Keypad 6
        case 0xffb7: return RDPKeyboardScancode(code: 0x47) // Keypad 7
        case 0xffb8: return RDPKeyboardScancode(code: 0x48) // Keypad 8
        case 0xffb9: return RDPKeyboardScancode(code: 0x49) // Keypad 9

        // Function keys F1-F12
        case 0xffbe: return RDPKeyboardScancode(code: 0x3B) // F1
        case 0xffbf: return RDPKeyboardScancode(code: 0x3C) // F2
        case 0xffc0: return RDPKeyboardScancode(code: 0x3D) // F3
        case 0xffc1: return RDPKeyboardScancode(code: 0x3E) // F4
        case 0xffc2: return RDPKeyboardScancode(code: 0x3F) // F5
        case 0xffc3: return RDPKeyboardScancode(code: 0x40) // F6
        case 0xffc4: return RDPKeyboardScancode(code: 0x41) // F7
        case 0xffc5: return RDPKeyboardScancode(code: 0x42) // F8
        case 0xffc6: return RDPKeyboardScancode(code: 0x43) // F9
        case 0xffc7: return RDPKeyboardScancode(code: 0x44) // F10
        case 0xffc8: return RDPKeyboardScancode(code: 0x57) // F11
        case 0xffc9: return RDPKeyboardScancode(code: 0x58) // F12

        default: return nil
        }
    }
}
