import Foundation
import Network

/// High-level client managing an RFB 3.8 remote desktop session over TCP (Network.framework).
public final class RFBClient: @unchecked Sendable {

    public enum State: Equatable, Sendable {
        case disconnected
        case connecting
        case negotiatingVersion
        case authenticating
        case initializing
        case connected
        case failed(String)
    }

    public let host: String
    public let port: UInt16
    public var password: String?
    public let framebuffer: Framebuffer

    public private(set) var state: State = .disconnected {
        didSet {
            onStateChanged?(state)
        }
    }

    // Callbacks
    public var onStateChanged: (@Sendable (State) -> Void)?
    public var onFrameUpdated: (@Sendable () -> Void)?
    public var onClipboardReceived: (@Sendable (String) -> Void)?
    public var onRequestPassword: (@Sendable (@escaping @Sendable (String?) -> Void) -> Void)?
    public var onDownloadProgress: (@Sendable (Double, Double) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aethernative.aetherscreens.rfbclient", qos: .userInteractive)
    private var readBuffer = Data()
    private let zlibDecompressor = ZlibDecompressor()

    public init(
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        password: String? = nil,
        framebuffer: Framebuffer = Framebuffer()
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.framebuffer = framebuffer
    }

    /// Initiate connection to the remote Mac.
    public func connect() {
        switch state {
        case .disconnected, .failed:
            break
        default:
            return
        }

        state = .connecting
        AppLogger.shared.info("Initiating connection to \(host):\(port)...", category: "Network")

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable Nagle's algorithm for interactive responsiveness
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] connState in
            guard let self = self else { return }
            switch connState {
            case .ready:
                AppLogger.shared.info("TCP socket established with \(self.host):\(self.port)", category: "Network")
                self.startHandshake()
            case .failed(let error):
                AppLogger.shared.error("TCP connection failed: \(error.localizedDescription)", category: "Network")
                self.handleFailure("Connection failed: \(error.localizedDescription)")
            case .cancelled:
                AppLogger.shared.info("TCP socket cancelled", category: "Network")
                self.state = .disconnected
            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    /// Disconnect current session.
    public func disconnect() {
        AppLogger.shared.info("Disconnecting session with \(host)", category: "Network")
        connection?.cancel()
        connection = nil
        readBuffer.removeAll()
        state = .disconnected
    }

    // MARK: - Handshake Workflow

    private func startHandshake() {
        state = .negotiatingVersion
        AppLogger.shared.info("Negotiating RFB protocol version...", category: "RFB")
        // Expect 12 bytes of version: "RFB 003.008\n"
        readExact(12) { [weak self] data in
            guard let self = self, let data = data else { return }
            guard let (_, minor) = RFBDecoder.parseVersion(data) else {
                let rawStr = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                AppLogger.shared.error("Invalid RFB protocol header from server: \(rawStr)", category: "RFB")
                self.handleFailure("Invalid RFB protocol header from server")
                return
            }

            let verStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            AppLogger.shared.info("Server banner: '\(verStr)' (RFB 3.\(minor))", category: "RFB")

            // Reply with RFB 003.008
            let versionReply = Data(RFBConstants.protocolVersion38.utf8)
            AppLogger.shared.info("Sending client version: RFB 003.008", category: "RFB")
            self.sendData(versionReply) {
                self.negotiateSecurity()
            }
        }
    }

    private func negotiateSecurity() {
        state = .authenticating
        AppLogger.shared.info("Negotiating security mechanisms...", category: "Security")
        // Read 1 byte for number of security types
        readExact(1) { [weak self] countData in
            guard let self = self, let countData = countData else { return }
            let count = Int(countData[0])
            if count == 0 {
                // Server reported an error, read reason
                self.readExact(4) { lenData in
                    guard let lenData = lenData else { return }
                    let reasonLen = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                    self.readExact(reasonLen) { msgData in
                        let reason = msgData.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown server error"
                        AppLogger.shared.error("Server rejected connection: \(reason)", category: "Security")
                        self.handleFailure("Server rejected connection: \(reason)")
                    }
                }
                return
            }

            // Read the supported security types
            self.readExact(count) { typesData in
                guard let typesData = typesData else { return }
                let types = typesData.map { RFBConstants.SecurityType(rawValue: $0) }
                AppLogger.shared.info("Server offered \(types.count) security types: \(typesData.map { String($0) }.joined(separator: ", "))", category: "Security")
                self.selectSecurityType(from: types)
            }
        }
    }

    private func selectSecurityType(from types: [RFBConstants.SecurityType]) {
        if types.contains(.vncAuth) {
            AppLogger.shared.info("Selecting VNC Authentication (Type 2)", category: "Security")
            // Select VNC Auth (2)
            sendData(Data([RFBConstants.SecurityType.vncAuth.rawValue])) {
                self.performVNCAuth()
            }
        } else if types.contains(.none) {
            AppLogger.shared.info("Selecting None Authentication (Type 1)", category: "Security")
            // Select None (1)
            sendData(Data([RFBConstants.SecurityType.none.rawValue])) {
                self.handleSecurityResult(type: .none)
            }
        } else {
            let offeredStr = types.map { "\($0.rawValue)" }.joined(separator: ", ")
            AppLogger.shared.error("No compatible security type. Offered: [\(offeredStr)]", category: "Security")
            handleFailure("No compatible security type supported by server. Offered: [\(offeredStr)]")
        }
    }

    private func performVNCAuth() {
        if let pwd = password, !pwd.isEmpty {
            AppLogger.shared.info("Using configured password for VNC Auth", category: "Auth")
            self.executeVNCChallenge(withPassword: pwd)
        } else if let onRequest = self.onRequestPassword {
            AppLogger.shared.info("No saved password. Requesting user input via modal sheet...", category: "Auth")
            onRequest { [weak self] enteredPwd in
                guard let self = self else { return }
                guard let pwd = enteredPwd, !pwd.isEmpty else {
                    AppLogger.shared.warning("User cancelled password prompt", category: "Auth")
                    self.handleFailure("VNC Password required to connect")
                    return
                }
                self.password = pwd
                AppLogger.shared.info("Password entered, executing challenge...", category: "Auth")
                self.executeVNCChallenge(withPassword: pwd)
            }
        } else {
            AppLogger.shared.error("Server requires VNC password, but none was provided", category: "Auth")
            handleFailure("Server requires VNC password, but none was provided")
        }
    }

    private func executeVNCChallenge(withPassword pwd: String) {
        // Read 16-byte random challenge
        readExact(16) { [weak self] challengeData in
            guard let self = self, let challengeData = challengeData else { return }
            AppLogger.shared.info("Received 16-byte DES challenge from server", category: "Auth")
            let response = VNCAuthCrypto.encryptChallenge(challengeData, password: pwd)
            self.sendData(response) {
                AppLogger.shared.info("Sent encrypted DES response to server", category: "Auth")
                self.handleSecurityResult(type: .vncAuth)
            }
        }
    }

    private func handleSecurityResult(type: RFBConstants.SecurityType) {
        // Read 4-byte SecurityResult
        readExact(4) { [weak self] resData in
            guard let self = self, let resData = resData else { return }
            guard let code = RFBDecoder.parseSecurityResult(resData) else {
                AppLogger.shared.error("Failed to parse security result header", category: "Auth")
                self.handleFailure("Failed to parse security result")
                return
            }

            if code == 0 {
                // Auth OK, proceed to ClientInit
                AppLogger.shared.info("Authentication succeeded! Proceeding to ClientInit", category: "Auth")
                self.sendClientInit()
            } else {
                AppLogger.shared.error("Authentication rejected by server (code \(code))", category: "Auth")
                // Auth failed, read reason if 3.8
                self.readExact(4) { lenData in
                    if let lenData = lenData {
                        let len = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                        self.readExact(len) { errData in
                            let errStr = errData.flatMap { String(data: $0, encoding: .utf8) } ?? "Authentication failed (incorrect password)"
                            AppLogger.shared.error("Auth rejection detail: \(errStr)", category: "Auth")
                            self.handleFailure(errStr)
                        }
                    } else {
                        self.handleFailure("Authentication failed (incorrect password)")
                    }
                }
            }
        }
    }

    private func sendClientInit() {
        state = .initializing
        // ClientInit: 1 byte shared-flag (1 = shared, allows existing sessions to continue)
        sendData(Data([1])) { [weak self] in
            self?.readServerInit()
        }
    }

    private func readServerInit() {
        // Minimum ServerInit is 24 bytes
        readExact(24) { [weak self] headerData in
            guard let self = self, let headerData = headerData else { return }
            let nameLen = Int(headerData.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            
            self.readExact(nameLen) { nameData in
                guard let nameData = nameData else { return }
                var fullData = headerData
                fullData.append(nameData)

                guard let (serverInit, _) = RFBDecoder.parseServerInit(fullData) else {
                    AppLogger.shared.error("Failed to parse ServerInit packet", category: "RFB")
                    self.handleFailure("Failed to parse ServerInit")
                    return
                }

                AppLogger.shared.info("ServerInit received: \(serverInit.width)x\(serverInit.height) '\(serverInit.name)', serverFormat bpp=\(serverInit.pixelFormat.bitsPerPixel) depth=\(serverInit.pixelFormat.depth)", category: "RFB")

                // Update framebuffer size
                self.framebuffer.resize(newWidth: Int(serverInit.width), newHeight: Int(serverInit.height))

                // Configure encodings & pixel format
                self.setupSession(serverInit: serverInit)
            }
        }
    }

    private func setupSession(serverInit: RFBServerInit) {
        AppLogger.shared.info("Configuring session: 32-bit BGRA pixel format...", category: "RFB")
        // Request 32-bit standard BGRA format for high-speed iOS / Metal rendering
        let pixelFormatData = RFBEncoder.encodeSetPixelFormat(.standardBGRA32)
        sendData(pixelFormatData)

        // Set encodings: Zlib, CopyRect, DesktopSize, Raw (do NOT request cursor to avoid cursor desync)
        AppLogger.shared.info("Setting encodings: Zlib, CopyRect, DesktopSize, Raw...", category: "RFB")
        let encodingsData = RFBEncoder.encodeSetEncodings([
            .zlib,
            .copyRect,
            .desktopSize,
            .raw
        ])
        sendData(encodingsData)

        state = .connected
        AppLogger.shared.info("Session state -> connected! Requesting initial full-frame update (0,0,\(framebuffer.width)x\(framebuffer.height))...", category: "RFB")

        // Send initial full screen update request
        requestUpdate(incremental: false)

        // Start server message loop
        startMessageLoop()
    }

    // MARK: - Server Message Loop

    private func startMessageLoop() {
        readExact(1) { [weak self] typeData in
            guard let self = self, let typeData = typeData else { return }
            let msgType = typeData[0]

            switch msgType {
            case RFBConstants.ServerMessageType.framebufferUpdate.rawValue:
                self.handleFramebufferUpdate()
            case RFBConstants.ServerMessageType.serverCutText.rawValue:
                self.handleServerCutText()
            case RFBConstants.ServerMessageType.bell.rawValue:
                AppLogger.shared.info("Server sent bell (beep)", category: "RFB")
                self.startMessageLoop()
            default:
                AppLogger.shared.warning("Unknown server message type: \(msgType)", category: "RFB")
                self.startMessageLoop()
            }
        }
    }

    private func handleFramebufferUpdate() {
        // Header: [pad: 1 byte] [numRects: 2 bytes] = 3 bytes
        readExact(3) { [weak self] headerData in
            guard let self = self, let headerData = headerData else { return }
            let numRects = headerData.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            self.readRectangles(count: Int(numRects))
        }
    }

    private func readRectangles(count: Int) {
        guard count > 0 else {
            // All rectangles processed, notify UI and request next update
            onFrameUpdated?()
            requestUpdate(incremental: true)
            startMessageLoop()
            return
        }

        // Each rect header: 12 bytes
        readExact(12) { [weak self] rectHeaderData in
            guard let self = self, let rectHeaderData = rectHeaderData else { return }
            guard let header = RFBDecoder.parseRectangleHeader(rectHeaderData) else {
                AppLogger.shared.error("Invalid rectangle header data", category: "RFB")
                self.handleFailure("Invalid rectangle header")
                return
            }


            switch header.encoding {
            case .zlib:
                // 4 bytes: length (UInt32 big endian)
                self.readExact(4) { [weak self] lenData in
                    guard let self = self, let lenData = lenData else { return }
                    let compressedLength = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                    let expectedBytes = Int(header.width) * Int(header.height) * 4
                    self.readExact(compressedLength) { [weak self] compressedData in
                        guard let self = self, let compressedData = compressedData else { return }
                        if let decompressed = self.zlibDecompressor.decompress(data: compressedData, expectedBytes: expectedBytes) {
                            self.framebuffer.updateRect(
                                x: Int(header.x),
                                y: Int(header.y),
                                width: Int(header.width),
                                height: Int(header.height),
                                rawData: decompressed
                            )
                        } else {
                            AppLogger.shared.error("Zlib decompression failed for rect \(header.width)x\(header.height)", category: "RFB")
                        }
                        self.readRectangles(count: count - 1)
                    }
                }

            case .raw:
                let pixelBytes = Int(header.width) * Int(header.height) * 4
                self.readExact(pixelBytes) { pixelData in
                    guard let pixelData = pixelData else { return }
                    self.framebuffer.updateRect(
                        x: Int(header.x),
                        y: Int(header.y),
                        width: Int(header.width),
                        height: Int(header.height),
                        rawData: pixelData
                    )
                    self.readRectangles(count: count - 1)
                }

            case .copyRect:
                // 4 bytes: srcX (2), srcY (2)
                self.readExact(4) { srcData in
                    guard let srcData = srcData else { return }
                    let srcX = srcData.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                    let srcY = srcData.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                    self.framebuffer.copyRect(
                        srcX: Int(srcX),
                        srcY: Int(srcY),
                        dstX: Int(header.x),
                        dstY: Int(header.y),
                        width: Int(header.width),
                        height: Int(header.height)
                    )
                    self.readRectangles(count: count - 1)
                }

            case .desktopSize:
                // Screen resolution changed on remote Mac!
                AppLogger.shared.info("Remote desktop resized to \(header.width)x\(header.height)", category: "RFB")
                self.framebuffer.resize(newWidth: Int(header.width), newHeight: Int(header.height))
                self.readRectangles(count: count - 1)

            case .cursor:
                // Cursor pseudo-encoding has: width * height * 4 pixel bytes + ((width + 7) / 8) * height mask bytes
                let pixelBytes = Int(header.width) * Int(header.height) * 4
                let maskBytes = ((Int(header.width) + 7) / 8) * Int(header.height)
                let totalCursorBytes = pixelBytes + maskBytes
                if totalCursorBytes > 0 {
                    self.readExact(totalCursorBytes) { _ in
                        self.readRectangles(count: count - 1)
                    }
                } else {
                    self.readRectangles(count: count - 1)
                }

            case .lastRect:
                self.onFrameUpdated?()
                self.requestUpdate(incremental: true)
                self.startMessageLoop()
                return

            default:
                AppLogger.shared.warning("Unhandled encoding \(header.encoding.rawValue) for rect \(header.width)x\(header.height)", category: "RFB")
                self.readRectangles(count: count - 1)
            }
        }
    }

    private func handleServerCutText() {
        // [pad: 3 bytes] [length: 4 bytes]
        readExact(7) { [weak self] headerData in
            guard let self = self, let headerData = headerData else { return }
            let length = Int(headerData.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            self.readExact(length) { textData in
                if let textData = textData,
                   let text = String(data: textData, encoding: .utf8) ?? String(data: textData, encoding: .isoLatin1) {
                    self.onClipboardReceived?(text)
                }
                self.startMessageLoop()
            }
        }
    }

    // MARK: - Public Client Controls (Pointer, Keyboard, Clipboard)

    /// Request a screen update from the remote server.
    public func requestUpdate(incremental: Bool) {
        let req = RFBEncoder.encodeFramebufferUpdateRequest(
            incremental: incremental,
            x: 0,
            y: 0,
            width: UInt16(framebuffer.width),
            height: UInt16(framebuffer.height)
        )
        sendData(req)
    }

    /// Send mouse movement or button press.
    public func sendPointerEvent(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) {
        let data = RFBEncoder.encodePointerEvent(buttonMask: buttonMask, x: x, y: y)
        sendData(data)
    }

    /// Send a key press or release.
    public func sendKeyEvent(down: Bool, keySym: UInt32) {
        let data = RFBEncoder.encodeKeyEvent(down: down, keySym: keySym)
        sendData(data)
    }

    /// Send clipboard text to remote Mac.
    public func sendCutText(_ text: String) {
        let data = RFBEncoder.encodeClientCutText(text)
        sendData(data)
    }

    // MARK: - Socket Helpers

    private func sendData(_ data: Data, completion: (@Sendable () -> Void)? = nil) {
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[RFBClient] Send error: \(error)")
            }
            completion?()
        }))
    }

    private func readExact(_ count: Int, completion: @escaping @Sendable (Data?) -> Void) {
        // First check if readBuffer already contains enough bytes
        if readBuffer.count >= count {
            let chunk = readBuffer.prefix(count)
            readBuffer.removeSubrange(0..<count)
            completion(Data(chunk))
            return
        }

        guard let conn = connection else {
            completion(nil)
            return
        }

        let needed = count - readBuffer.count
        let maxReceive = min(max(needed, 65536), 1048576) // cap at 1MB per receive
        conn.receive(minimumIncompleteLength: 1, maximumLength: maxReceive) { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            let receivedBytes = content?.count ?? 0
            if receivedBytes > 0 {
                self.readBuffer.append(content!)
            }

            if count > 100000 && self.readBuffer.count % 2097152 < receivedBytes {
                let mb = Double(self.readBuffer.count) / (1024.0 * 1024.0)
                let totalMb = Double(count) / (1024.0 * 1024.0)
                DispatchQueue.main.async { [weak self] in
                    self?.onDownloadProgress?(mb, totalMb)
                }
            }

            if let error = error {
                self.handleFailure("Socket read error: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if self.readBuffer.count >= count {
                let chunk = self.readBuffer.prefix(count)
                self.readBuffer.removeSubrange(0..<count)
                completion(Data(chunk))
            } else if isComplete {
                print("[DEBUG readExact] Connection marked isComplete=true, but only have \(self.readBuffer.count) of \(count) bytes")
                self.handleFailure("Remote host closed connection (received \(self.readBuffer.count)/\(count) bytes)")
                completion(nil)
            } else {
                // Buffer remaining bytes recursively
                self.readExact(count, completion: completion)
            }
        }
    }

    private func handleFailure(_ message: String) {
        AppLogger.shared.error("Session failed: \(message)", category: "RFB")
        state = .failed(message)
        connection?.cancel()
        connection = nil
    }
}
