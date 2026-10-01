import Foundation
import Network
import zlib

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
    public var username: String?
    public let framebuffer: Framebuffer

    public private(set) var state: State = .disconnected {
        didSet {
            onStateChanged?(state)
        }
    }

    // Callbacks
    public var onStateChanged: (@Sendable (State) -> Void)?
    public var onFrameUpdated: (@Sendable () -> Void)?
    public var onDisplayLayoutReceived: (@Sendable (RFBDisplayLayout?) -> Void)?
    public var onClipboardReceived: (@Sendable (String) -> Void)?
    public var onRequestPassword: (@Sendable (@escaping @Sendable (String?) -> Void) -> Void)?
    public var onRequestMacAccount: (@Sendable (@escaping @Sendable (String?, String?) -> Void) -> Void)?
    public var onBytesReceived: (@Sendable (Int) -> Void)?
    /// TCP transport round-trip estimate; excludes server processing and display.
    public var onTransportRTT: (@Sendable (Double) -> Void)?
    public var onDownloadProgress: (@Sendable (Double, Double) -> Void)?

    private var connection: NWConnection?
    // Accessed only on the connection queue, including teardown.
    private weak var reportConnection: NWConnection?
    private var pendingTransferReport: NWConnection.PendingDataTransferReport?
    private var lastTransferReportTime: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.aethernative.aetherscreens.rfbclient", qos: .userInteractive)
    private var readBuffer = Data()
    private var hasCompletedFramebufferUpdate = false
    private var updateHasDisplayLayout = false
    private var updateHasPixels = false
    private let zlibDecompressor = ZlibDecompressor()
    private let zrleDecoder = ZRLEDecoder()
    private let inputLock = NSRecursiveLock()
    private var inputEnabled = true
    private var pointerInputEnabled = true
    private var inputGeneration = UUID()
    private var heldKeys = Set<UInt32>()
    private var pointerPosition: (UInt16, UInt16) = (0, 0)
    private var heldPointerButtons: RFBConstants.ButtonMask = []
    private var nextWheelDeadline = DispatchTime.now()
    private var wheelScheduleGeneration: UUID?
    private var extendedClipboard = false
    private var pendingClipboard: String?

    public init(
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        password: String? = nil,
        username: String? = nil,
        framebuffer: Framebuffer = Framebuffer()
    ) {
        self.host = host
        self.port = port
        self.password = password
        self.username = username
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

        readBuffer.removeAll()
        hasCompletedFramebufferUpdate = false
        extendedClipboard = false
        pendingClipboard = nil
        state = .connecting
        AppLogger.shared.info("Initiating connection to \(host):\(port)...", category: "Network")

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable Nagle's algorithm for interactive responsiveness
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] connState in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            switch connState {
            case .ready:
                AppLogger.shared.info("TCP socket established with \(self.host):\(self.port)", category: "Network")
                // Reset on the serial connection queue, alongside decoding. Reconnect
                // can be requested by the UI while an old rectangle is still decoding.
                self.zlibDecompressor.reset()
                self.zrleDecoder.reset()
                self.reportConnection = conn
                self.pendingTransferReport = conn.startDataTransferReport()
                self.lastTransferReportTime = ProcessInfo.processInfo.systemUptime
                self.startHandshake()
            case .waiting(let error):
                AppLogger.shared.info("Waiting for network: \(error.localizedDescription)", category: "Network")
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
        queue.asyncAfter(deadline: .now() + 20) { [weak self, weak conn] in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            switch self.state {
            case .connecting, .negotiatingVersion, .authenticating, .initializing: break
            default: return
            }
            #if os(macOS)
            let settings = "System Settings"
            #else
            let settings = "Settings"
            #endif
            self.handleFailure("Connection timed out. Check the address, Screen Sharing and your LAN or Tailscale connection. Allow AetherScreens in \(settings) > Privacy & Security > Local Network.")
        }
    }

    /// Disconnect current session.
    public func disconnect() {
        inputLock.lock()
        heldKeys.removeAll()
        heldPointerButtons = []
        inputGeneration = UUID()
        inputLock.unlock()
        AppLogger.shared.info("Disconnecting session with \(host)", category: "Network")
        stopTransportReports()
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
        if let username = username, !username.isEmpty {
            guard types.contains(.ardDiffieHellman) else {
                handleFailure("Server does not support Mac account authentication. Leave Username empty to use a VNC password.")
                return
            }
            AppLogger.shared.info("Selecting Mac account authentication (Type 30)", category: "Security")
            sendData(Data([30])) { self.performARDAuth(username: username) }
        } else if types.contains(.vncAuth) {
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
        } else if types.contains(.ardDiffieHellman), let request = onRequestMacAccount {
            let pendingConnection = connection
            request { [weak self] account, password in
                guard let self else { return }
                self.queue.async {
                    guard self.connection === pendingConnection, self.state == .authenticating else { return }
                    guard let account = account?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !account.isEmpty, let password, !password.isEmpty else {
                        self.handleFailure("Mac account username and password required")
                        return
                    }
                    self.username = account
                    self.password = password
                    self.sendData(Data([30])) { self.performARDAuth(username: account) }
                }
            }
        } else {
            let offeredStr = types.map { "\($0.rawValue)" }.joined(separator: ", ")
            AppLogger.shared.error("No compatible security type. Offered: [\(offeredStr)]", category: "Security")
            handleFailure("No compatible security type supported by server. Offered: [\(offeredStr)]")
        }
    }

    private func performARDAuth(username: String) {
        let pendingConnection = connection
        let authenticate: @Sendable (String) -> Void = { [weak self] password in
            guard let self = self else { return }
            self.readExact(4) { header in
                guard let header = header else { return }
                let generator = UInt16(header[0]) << 8 | UInt16(header[1])
                let length = Int(header[2]) << 8 | Int(header[3])
                guard (16...512).contains(length) else {
                    self.handleFailure("Unsupported Mac account authentication key length")
                    return
                }
                self.readExact(length * 2) { challenge in
                    guard let challenge = challenge else { return }
                    do {
                        let response = try ARDAuthCrypto.response(generator: generator,
                            prime: Data(challenge.prefix(length)), peer: Data(challenge.suffix(length)),
                            username: username, password: password)
                        self.sendData(response) { self.handleSecurityResult(type: .ardDiffieHellman) }
                    } catch {
                        self.handleFailure("Mac account authentication challenge could not be processed")
                    }
                }
            }
        }
        if let password = password, !password.isEmpty {
            authenticate(password)
        } else if let request = onRequestPassword {
            request { [weak self] entered in
                guard let self else { return }
                self.queue.async {
                    guard self.connection === pendingConnection, self.state == .authenticating else { return }
                    guard let entered, !entered.isEmpty else {
                        self.handleFailure("Mac account password required")
                        return
                    }
                    self.password = entered
                    authenticate(entered)
                }
            }
        } else {
            handleFailure("Mac account password required")
        }
    }

    private func performVNCAuth() {
        if let pwd = password, !pwd.isEmpty {
            AppLogger.shared.info("Using configured password for VNC Auth", category: "Auth")
            self.executeVNCChallenge(withPassword: pwd)
        } else if let onRequest = self.onRequestPassword {
            let pendingConnection = connection
            AppLogger.shared.info("No saved password. Requesting user input via modal sheet...", category: "Auth")
            onRequest { [weak self] enteredPwd in
                guard let self = self else { return }
                self.queue.async {
                    guard self.connection === pendingConnection, self.state == .authenticating else { return }
                    guard let pwd = enteredPwd, !pwd.isEmpty else {
                        AppLogger.shared.warning("User cancelled password prompt", category: "Auth")
                        self.handleFailure("VNC Password required to connect")
                        return
                    }
                    self.password = pwd
                    AppLogger.shared.info("Password entered, executing challenge...", category: "Auth")
                    self.executeVNCChallenge(withPassword: pwd)
                }
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

        // Advertise only implemented formats, retaining Zlib/Raw fallbacks.
        AppLogger.shared.info("Setting encodings: ZRLE, Zlib, CopyRect, DesktopSize, Raw...", category: "RFB")
        let encodingsData = RFBEncoder.encodeSetEncodings([
            .zrle,
            .zlib,
            .copyRect,
            .desktopSize,
            .extendedDesktopSize,
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
            self.updateHasDisplayLayout = false
            self.updateHasPixels = false
            let numRects = headerData.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            self.readRectangles(count: Int(numRects))
        }
    }

    private func readRectangles(count: Int) {
        guard count > 0 else {
            // Loading progress is only useful until the first desktop is visible.
            // A display-layout acknowledgement alone is not the first visible desktop.
            if !updateHasDisplayLayout || updateHasPixels {
                hasCompletedFramebufferUpdate = true
                onFrameUpdated?()
            }
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
            case .zrle:
                guard let sourceConnection = self.connection else { return }
                let width = Int(header.width), height = Int(header.height)
                guard Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height,
                      let maximum = ZRLEDecoder.maximumTileBytes(width: width, height: height) else {
                    self.handleFailure("Invalid ZRLE rectangle size")
                    return
                }
                self.readExact(4) { [weak self] lengthData in
                    guard let self, let lengthData, self.connection === sourceConnection else { return }
                    let length = Int(lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                    guard length > 0, length <= maximum * 2 + 1024 else {
                        self.handleFailure("Invalid ZRLE compressed length")
                        return
                    }
                    self.readExact(length) { [weak self] compressed in
                        guard let self, let compressed, self.connection === sourceConnection else { return }
                        let decoded = self.zrleDecoder.decode(data: compressed, width: width, height: height)
                        guard self.connection === sourceConnection else { return }
                        guard let pixels = decoded else {
                            self.handleFailure("Invalid ZRLE pixel data")
                            return
                        }
                        self.framebuffer.updateRect(x: Int(header.x), y: Int(header.y), width: width,
                                                    height: height, rawData: pixels)
                        self.updateHasPixels = true
                        self.readRectangles(count: count - 1)
                    }
                }

            case .zlib:
                // 4 bytes: length (UInt32 big endian)
                self.readExact(4) { [weak self] lenData in
                    guard let self = self, let lenData = lenData else { return }
                    let compressedLength = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                    let expectedBytes = Int(header.width) * Int(header.height) * 4
                    self.readExact(compressedLength) { [weak self] compressedData in
                        guard let self = self, let compressedData = compressedData else { return }
                        if let decompressed = self.zlibDecompressor.decompress(data: compressedData, expectedBytes: expectedBytes) {
                            self.updateHasPixels = expectedBytes > 0 || self.updateHasPixels
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
                    self.updateHasPixels = pixelBytes > 0 || self.updateHasPixels
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
                    self.updateHasPixels = (header.width > 0 && header.height > 0) || self.updateHasPixels
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
                self.onDisplayLayoutReceived?(nil)
                self.readRectangles(count: count - 1)

            case .extendedDesktopSize:
                self.updateHasDisplayLayout = true
                self.readExact(4) { [weak self] prefix in
                    guard let self, let prefix else { return }
                    let screenBytes = Int(prefix[prefix.startIndex]) * 16
                    let consume: @Sendable (Data) -> Void = { [weak self] screens in
                        guard let self else { return }
                        // A rejected/forwarded client resize has undefined geometry, but its payload must be consumed.
                        if header.x == 1 && header.y != 0 {
                            self.readRectangles(count: count - 1)
                            return
                        }
                        guard let layout = RFBDecoder.parseDisplayLayout(prefix + screens, width: header.width, height: header.height) else {
                            self.handleFailure("Invalid remote display layout")
                            return
                        }
                        // A layout-only update must retain existing pixel contents.
                        if self.framebuffer.width != Int(layout.width) || self.framebuffer.height != Int(layout.height) {
                            self.framebuffer.resize(newWidth: Int(layout.width), newHeight: Int(layout.height))
                        }
                        self.onDisplayLayoutReceived?(layout)
                        self.readRectangles(count: count - 1)
                    }
                    if screenBytes == 0 { consume(Data()) }
                    else { self.readExact(screenBytes) { if let data = $0 { consume(data) } } }
                }

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
                self.readRectangles(count: 0)
                return

            default:
                AppLogger.shared.warning("Unhandled encoding \(header.encoding.rawValue) for rect \(header.width)x\(header.height)", category: "RFB")
                self.readRectangles(count: count - 1)
            }
        }
    }

    private func handleServerCutText() {
        readExact(7) { [weak self] header in
            guard let self = self, let header = header else { return }
            let raw = header.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let signed = Int32(bitPattern: raw)
            let length = abs(Int64(signed))
            guard length <= 1_048_576 else {
                self.handleFailure("Remote clipboard exceeds the supported size")
                return
            }
            self.readExact(Int(length)) { payload in
                guard let payload = payload else { return }
                if signed < 0 {
                    self.handleExtendedClipboard(payload)
                } else if let text = String(data: payload, encoding: .isoLatin1) {
                    self.onClipboardReceived?(text)
                }
                self.startMessageLoop()
            }
        }
    }

    private func sendExtendedClipboard(flags: UInt32, payload: Data = Data()) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard flags & 0xFF000000 != 0x10000000 || inputEnabled else { return }
        var body = Data()
        body.append(contentsOf: withUnsafeBytes(of: flags.bigEndian) { Array($0) })
        body.append(payload)
        var data = Data([6, 0, 0, 0])
        let length = Int32(-body.count).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        data.append(body)
        sendData(data)
    }

    func handleExtendedClipboard(_ payload: Data) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard payload.count >= 4 else { return }
        let flags = payload.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let action = flags & 0xFF000000
        if action & 0x01000000 != 0 {
            // Each advertised format has one size entry, including unknown formats.
            let formats = UInt16(flags & 0xFFFF)
            guard payload.count == 4 + formats.nonzeroBitCount * 4 else { return }
            extendedClipboard = formats & 1 != 0
            if !extendedClipboard { pendingClipboard = nil }
            if extendedClipboard { AppLogger.shared.info("Extended UTF-8 clipboard available", category: "RFB") }
            sendExtendedClipboard(flags: 0x1F000001, payload: Data(repeating: 0, count: 4))
        } else if action == 0x02000000, flags & 1 != 0, let text = pendingClipboard {
            let utf8 = Data(text.utf8) + Data([0])
            var plain = Data()
            plain.append(contentsOf: withUnsafeBytes(of: UInt32(utf8.count).bigEndian) { Array($0) })
            plain.append(utf8)
            var size = compressBound(uLong(plain.count))
            var compressed = [UInt8](repeating: 0, count: Int(size))
            let result = plain.withUnsafeBytes { raw in
                compress2(&compressed, &size, raw.bindMemory(to: UInt8.self).baseAddress!, uLong(plain.count), Z_DEFAULT_COMPRESSION)
            }
            if result == Z_OK {
                sendExtendedClipboard(flags: 0x10000001, payload: Data(compressed.prefix(Int(size))))
            }
        } else if action == 0x04000000 {
            sendExtendedClipboard(flags: 0x08000000 | (pendingClipboard == nil ? 0 : 1))
        } else if action == 0x08000000, flags & 1 != 0 {
            sendExtendedClipboard(flags: 0x02000001)
        } else if action == 0x10000000, flags & 1 != 0 {
            guard payload.count > 4 else { return }
            var size: uLongf = 1_048_576
            var plain = [UInt8](repeating: 0, count: Int(size))
            let compressed = Data(payload.dropFirst(4))
            let result = compressed.withUnsafeBytes { raw in
                uncompress(&plain, &size, raw.bindMemory(to: UInt8.self).baseAddress!, uLong(compressed.count))
            }
            guard result == Z_OK, size >= 4 else { return }
            let count = plain.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count > 0, Int(count) <= Int(size) - 4 else { return }
            var bytes = Data(plain[4..<(4 + Int(count))])
            guard bytes.last == 0 else { return }
            bytes.removeLast()
            if let text = String(data: bytes, encoding: .utf8) { onClipboardReceived?(RFBEncoder.clipboardText(text, extended: false)) }
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

    /// Observe mode blocks input at the transport boundary, including delayed wheel pulses.
    public func setInputEnabled(_ enabled: Bool) {
        inputLock.lock()
        defer { inputLock.unlock() }
        if inputEnabled != enabled { inputGeneration = UUID() }
        if !enabled && inputEnabled {
            for key in heldKeys { sendData(RFBEncoder.encodeKeyEvent(down: false, keySym: key)) }
            heldKeys.removeAll()
            if !heldPointerButtons.isEmpty {
                sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
            }
            heldPointerButtons = []
            pendingClipboard = nil
        }
        inputEnabled = enabled
    }

    /// Local viewport navigation suppresses mouse input without disabling keys.
    public func setPointerInputEnabled(_ enabled: Bool) {
        inputLock.lock()
        defer { inputLock.unlock() }
        if pointerInputEnabled != enabled { inputGeneration = UUID() }
        if !enabled && pointerInputEnabled {
            if !heldPointerButtons.isEmpty {
                sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
            }
            heldPointerButtons = []
        }
        pointerInputEnabled = enabled
    }

    @discardableResult
    private func sendPointerPacket(_ mask: RFBConstants.ButtonMask, x: UInt16, y: UInt16, generation: UUID? = nil) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, pointerInputEnabled else { return false }
        if let generation, generation != inputGeneration { return false }
        pointerPosition = (x, y)
        heldPointerButtons = RFBConstants.ButtonMask(rawValue: mask.rawValue & 7)
        sendData(RFBEncoder.encodePointerEvent(buttonMask: mask, x: x, y: y))
        return true
    }

    /// Delayed wheel work reads the latest pointer state under the same lock as
    /// ordinary movement. Its press/release pair cannot revive an old drag or
    /// overwrite a newer position, and releasing the wheel keeps held buttons.
    @discardableResult
    private func sendWheelPacket(_ wheel: RFBConstants.ButtonMask, generation: UUID) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, pointerInputEnabled, generation == inputGeneration else { return false }
        let (x, y) = pointerPosition
        sendData(RFBEncoder.encodePointerEvent(buttonMask: heldPointerButtons.union(wheel), x: x, y: y))
        if !wheel.isEmpty {
            sendData(RFBEncoder.encodePointerEvent(buttonMask: heldPointerButtons, x: x, y: y))
        }
        return true
    }

    /// Send mouse movement or button press.
    public func sendPointerEvent(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) {
        guard buttonMask.rawValue & 0x78 != 0 else {
            sendPointerPacket(buttonMask, x: x, y: y)
            return
        }
        // Apple's server applies wheel ticks at its current cursor position.
        // Establish that position before sending spaced press/release pulses.
        inputLock.lock()
        let generation = inputGeneration
        let enabled = inputEnabled && pointerInputEnabled
        if enabled {
            pointerPosition = (x, y)
            heldPointerButtons = RFBConstants.ButtonMask(rawValue: buttonMask.rawValue & 7)
        }
        inputLock.unlock()
        guard enabled else { return }
        queue.async { [weak self] in
            guard let self = self, let connection = self.connection else { return }
            guard self.sendWheelPacket([], generation: generation) else { return }
            if self.wheelScheduleGeneration != generation {
                // Cancelled ticks must not reserve time in the resumed session.
                self.wheelScheduleGeneration = generation
                self.nextWheelDeadline = .now()
            }
            let earliest = DispatchTime.now() + .milliseconds(25)
            let deadline = self.nextWheelDeadline > earliest ? self.nextWheelDeadline : earliest
            self.nextWheelDeadline = deadline + .milliseconds(16)
            self.queue.asyncAfter(deadline: deadline) { [weak self, weak connection] in
                guard let self = self, let connection = connection, self.connection === connection else { return }
                self.sendWheelPacket(RFBConstants.ButtonMask(rawValue: buttonMask.rawValue & 0x78), generation: generation)
            }
        }
    }

    /// Send a key press or release.
    public func sendKeyEvent(down: Bool, keySym: UInt32) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled else { return }
        if down { heldKeys.insert(keySym) } else { heldKeys.remove(keySym) }
        let data = RFBEncoder.encodeKeyEvent(down: down, keySym: keySym)
        sendData(data)
    }

    /// Send committed text as complete key strokes rather than overlapping held keys.
    public func sendText(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for scalar in normalized.unicodeScalars {
            let key: UInt32
            switch scalar.value {
            case 10, 13: key = MacKeyMap.return
            case 9: key = MacKeyMap.tab
            case 0x20...0xFF: key = scalar.value
            case 0x100...0x10FFFF: key = 0x01000000 | scalar.value
            default: continue
            }
            sendKeyEvent(down: true, keySym: key)
            sendKeyEvent(down: false, keySym: key)
        }
    }

    /// Queue supported clipboard text. Acceptance does not acknowledge a remote paste.
    @discardableResult
    public func sendCutText(_ text: String) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, state == .connected else { return false }
        let normalized = RFBEncoder.clipboardText(text, extended: extendedClipboard)
        guard normalized.utf8.count <= 1_048_000 else { return false }
        if extendedClipboard {
            pendingClipboard = normalized
            sendExtendedClipboard(flags: 0x08000001)
        } else {
            guard let data = RFBEncoder.encodeClientCutText(normalized) else { return false }
            sendData(data)
        }
        return true
    }

    // MARK: - Socket Helpers

    private func sendData(_ data: Data, completion: (@Sendable () -> Void)? = nil) {
        guard let connection else { return }
        connection.send(content: data, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self, let connection, self.connection === connection else { return }
            if let error = error {
                self.handleFailure("Connection failed: \(error.localizedDescription)")
                return
            }
            self.collectTransportReportIfDue(connection: connection)
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
            guard let self = self, self.connection === conn else {
                completion(nil)
                return
            }
            let receivedBytes = content?.count ?? 0
            if receivedBytes > 0 {
                self.readBuffer.append(content!)
                self.onBytesReceived?(receivedBytes)
            }

            if !self.hasCompletedFramebufferUpdate && count > 100000 && self.readBuffer.count % 2097152 < receivedBytes {
                let mb = Double(self.readBuffer.count) / (1024.0 * 1024.0)
                let totalMb = Double(count) / (1024.0 * 1024.0)
                self.onDownloadProgress?(mb, totalMb)
            }

            // Notifications can disconnect/reconnect synchronously. Never let an
            // old receive consume the new connection's handshake or report its failure.
            guard self.connection === conn else { completion(nil); return }

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

    private func collectTransportReportIfDue(connection: NWConnection) {
        guard state == .connected, self.connection === connection,
              reportConnection === connection, let report = pendingTransferReport else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTransferReportTime >= 1 else { return }
        lastTransferReportTime = now
        pendingTransferReport = connection.startDataTransferReport()
        report.collect(queue: queue) { [weak self, weak connection] sample in
            guard let self, let connection, self.connection === connection,
                  self.state == .connected else { return }
            let seconds = sample.aggregatePathReport.transportSmoothedRTT
            guard seconds.isFinite, seconds > 0 else { return }
            self.onTransportRTT?(seconds * 1000)
        }
    }

    private func stopTransportReports() {
        let previous = connection
        queue.async { [weak self] in
            guard let self, self.reportConnection === previous else { return }
            self.pendingTransferReport = nil
            self.reportConnection = nil
        }
    }

    private func handleFailure(_ message: String) {
        AppLogger.shared.error("Session failed: \(message)", category: "RFB")
        state = .failed(message)
        stopTransportReports()
        connection?.cancel()
        connection = nil
    }
}
