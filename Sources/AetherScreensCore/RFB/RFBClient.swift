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
    public private(set) var colorDepth: RFBColorDepth
    public let framebuffer: Framebuffer
    public var isNativeDisplaySession: Bool { appleRecordCodec != nil }

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
    // Internal hook identifies vendor-wire acceptance separately from standard Cursor.
    var onNativeUpdateRequested: (@Sendable (Bool) -> Void)?
    var onNativeLayoutPayload: (@Sendable (Data) -> Void)?
    var onNativePayloadLength: (@Sendable (Int) -> Void)?
    // Numeric ZRLE diagnostics only; no desktop payload is exposed.
    var onNativePixelPayloadReady: (@Sendable (Int) -> Void)?
    var onNativePixelDecodeCompleted: (@Sendable (TimeInterval) -> Void)?
    /// Compressed bytes, payload wait, and CPU decode; no pixels or credentials.
    var onZRLETiming: (@Sendable (Int, TimeInterval, TimeInterval) -> Void)?
    /// Completed pixel payload bytes and receive duration, excluding idle
    /// framebuffer wait and CPU decode. Delivery is guarded by socket identity.
    var onPixelTransferSample: (@Sendable (Int, TimeInterval) -> Void)?
    var onNativeRectangleReceived: (@Sendable (Int, Int, Int32) -> Void)?
    var onNativeRecordReceived: (@Sendable (Int?, Int) -> Void)?
    /// Control-command metadata only; never exposes clipboard contents.
    var onAppleStatusReceived: (@Sendable (UInt16) -> Void)?
    // Internal receive hook only; it neither advertises capability nor opens files.
    var onAppleFileCopyReceived: (@Sendable (AppleFileCopyMessage) -> Void)?
    var onAppleCursorReceived: (@Sendable (RFBRemoteCursor) -> Void)?
    public var onCursorReceived: (@Sendable (RFBRemoteCursor) -> Void)?
    public var onRequestPassword: (@Sendable (@escaping @Sendable (String?) -> Void) -> Void)?
    public var onRequestMacAccount: (@Sendable (@escaping @Sendable (String?, String?) -> Void) -> Void)?
    public var onBytesReceived: (@Sendable (Int) -> Void)?
    /// TCP transport round-trip estimate; excludes server processing and display.
    public var onTransportRTT: (@Sendable (Double) -> Void)?
    public var onDownloadProgress: (@Sendable (Double, Double) -> Void)?

    private var connection: NWConnection?
    private var loopbackForwardingPort: UInt16?
    private let requiresLoopbackForwarding: Bool
    private weak var closingConnection: NWConnection?
    // Accessed only on the connection queue, including teardown.
    private weak var reportConnection: NWConnection?
    private var pendingTransferReport: NWConnection.PendingDataTransferReport?
    private var lastTransferReportTime: TimeInterval = 0
    private let queue = DispatchQueue(label: "com.aethernative.aetherscreens.rfbclient", qos: .userInteractive)
    private var readBuffer = Data()
    private var hasCompletedFramebufferUpdate = false
    private var hasReceivedPixelUpdate = false
    private var updateHasDisplayLayout = false
    private var updateHasPixels = false
    private var updateHasCursorShape = false
    // Parsing stays on the transport queue; compression dictionaries are used
    // only on this serial worker, with a fresh context for each connection.
    private let decodeQueue: DispatchQueue
    private var frameDecoders = RFBFrameDecoders()
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
    private var appleServerBanner = false
    private let experimentalAppleCursor: Bool
    private let experimentalAppleModernBootstrap: Bool
    private let experimentalAppleLayoutDiagnostic: Bool
    private let experimentalAppleEncryption: Bool
    private let experimentalAppleControlMode: Bool
    // QA-supplied key belongs to this client's fixed target; trust/pinning is
    // not established, so this branch is deliberately absent from public init.
    private let experimentalAppleSRPKey: Data?
    private let experimentalAppleLogicalSize: (width: Int, height: Int)?
    private let experimentalAppleCombinedDisplay: Bool
    private let experimentalApplePhysicalSize: (width: Float, height: Float)?
    private var appleWrapKey: Data?
    private var appleRecordCodec: AppleRFBRecordLayer?
    private var decryptedReadBuffer = Data()
    private var firstFrameDeadline: NativeFirstFrameDeadline?
    private var appleClipboard = false
    private var appleFileCopyReceiver: AppleFileCopyReceiveWorker?
    private var appleFileCopySender: AppleFileCopySendWorker?
    private var appleClipboardRequestPending = false
    private var appleClipboardRefetchRequested = false
    private var appleClipboardReadID: UUID?
    // At most one encoding operation plus one latest pending text. Protected
    // by inputLock; encoding itself runs outside that lock on decodeQueue.
    private var appleClipboardSendActive = false
    private var appleClipboardSendGeneration = UUID()
    private var appleClipboardSendPending: (text: String, connection: NWConnection, generation: UUID)?

    public convenience init(
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        password: String? = nil,
        username: String? = nil,
        framebuffer: Framebuffer = Framebuffer(),
        colorDepth: RFBColorDepth = .fullColor,
        requiresLoopbackForwarding: Bool = false
    ) {
        self.init(host: host, port: port, password: password, username: username,
                  framebuffer: framebuffer, colorDepth: colorDepth,
                  requiresLoopbackForwarding: requiresLoopbackForwarding,
                  decodeQueue: DispatchQueue(label: "com.aethernative.aetherscreens.decode", qos: .userInitiated))
    }

    // Internal queue injection lets transport tests hold the serial worker without
    // depending on image size or Debug/Release decoding speed.
    init(host: String, port: UInt16 = RFBConstants.defaultPort, password: String? = nil,
         username: String? = nil, framebuffer: Framebuffer = Framebuffer(),
         colorDepth: RFBColorDepth = .fullColor, requiresLoopbackForwarding: Bool = false,
         decodeQueue: DispatchQueue, experimentalAppleCursor: Bool = false, experimentalAppleModernBootstrap: Bool = false, experimentalAppleEncryption: Bool = false, experimentalAppleLayoutDiagnostic: Bool = false, experimentalAppleControlMode: Bool = false, experimentalAppleSRPKey: Data? = nil, experimentalAppleLogicalSize: (width: Int, height: Int)? = nil, experimentalAppleCombinedDisplay: Bool = false, experimentalApplePhysicalSize: (width: Float, height: Float)? = nil) {
        self.experimentalApplePhysicalSize = experimentalApplePhysicalSize
        self.experimentalAppleCombinedDisplay = experimentalAppleCombinedDisplay
        self.experimentalAppleLogicalSize = experimentalAppleLogicalSize
        self.experimentalAppleSRPKey = experimentalAppleSRPKey
        self.experimentalAppleControlMode = experimentalAppleControlMode
        self.experimentalAppleLayoutDiagnostic = experimentalAppleLayoutDiagnostic
        self.experimentalAppleEncryption = experimentalAppleEncryption
        self.experimentalAppleModernBootstrap = experimentalAppleModernBootstrap
        self.experimentalAppleCursor = experimentalAppleCursor
        self.decodeQueue = decodeQueue
        self.host = host
        self.port = port
        self.password = password
        self.username = username
        self.framebuffer = framebuffer
        self.colorDepth = colorDepth
        self.requiresLoopbackForwarding = requiresLoopbackForwarding
    }

    /// Initiate connection to the remote Mac.
    /// Pixel format is negotiated once per socket; never change an active decoder.
    @discardableResult
    public func configureColorDepth(_ depth: RFBColorDepth) -> Bool {
        switch state {
        case .disconnected, .failed:
            colorDepth = depth
            return true
        default: return false
        }
    }

    public func connect() {
        switch state {
        case .disconnected, .failed:
            break
        default:
            return
        }

        // A secure session must fail closed even after a tunnel is cleared or
        // setup fails. Resetting its port never changes this lifetime policy.
        guard !requiresLoopbackForwarding || loopbackForwardingPort != nil else {
            state = .failed("SSH forwarding is not ready")
            return
        }
        readBuffer.removeAll()
        hasCompletedFramebufferUpdate = false
        hasReceivedPixelUpdate = false
        extendedClipboard = false
        pendingClipboard = nil
        appleServerBanner = false
        appleClipboard = false
        appleClipboardRequestPending = false
        appleClipboardRefetchRequested = false
        appleClipboardReadID = nil
        state = .connecting
        // An observer can cancel or replace the attempt synchronously.
        guard state == .connecting, connection == nil else { return }
        AppLogger.shared.info("Initiating connection to \(host):\(port)...", category: "Network")

        let nwHost = NWEndpoint.Host(loopbackForwardingPort == nil ? host : "127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: loopbackForwardingPort ?? port)!

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable Nagle's algorithm for interactive responsiveness
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] connState in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            switch connState {
            case .ready:
                AppLogger.shared.info(self.loopbackForwardingPort == nil
                    ? "TCP socket established with \(self.host):\(self.port)"
                    : "Local forwarding socket established for \(self.host):\(self.port)", category: "Network")
                // Old decoding can finish in the worker after reconnect. Keep its
                // dictionary separate and reject its result by socket identity.
                self.inputLock.lock()
                self.frameDecoders.cancel()
                self.frameDecoders = RFBFrameDecoders(colorDepth: self.colorDepth)
                self.inputLock.unlock()
                if self.loopbackForwardingPort == nil {
                    self.reportConnection = conn
                    self.pendingTransferReport = conn.startDataTransferReport()
                    self.lastTransferReportTime = ProcessInfo.processInfo.systemUptime
                }
                self.startHandshake()
            case .waiting(let error):
                AppLogger.shared.info("Waiting for network: \(error.localizedDescription)", category: "Network")
                if case .posix(.ECONNREFUSED) = error {
                    self.handleFailure(Self.transportFailureMessage(error, state: self.state))
                }
            case .failed(let error):
                AppLogger.shared.error("TCP connection failed: \(error.localizedDescription)", category: "Network")
                self.handleFailure(Self.transportFailureMessage(error, state: self.state))
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
            self.handleFailure(Self.timeoutMessage(for: self.state))
        }
    }

    /// Route a disconnected client's next socket through a local forwarding
    /// listener. This never changes the logical remote host or RFB credentials.
    /// Local TCP RTT cannot represent the remote path and is not reported.
    @discardableResult
    public func configureLoopbackForwarding(port: UInt16?) -> Bool {
        guard port != 0 else { return false }
        switch state {
        case .disconnected, .failed:
            loopbackForwardingPort = port
            return true
        default: return false
        }
    }

    /// Disconnect current session.
    public func disconnect() {
        inputLock.lock()
        appleFileCopyReceiver?.cancel()
        appleFileCopyReceiver = nil
        appleFileCopySender?.cancel()
        appleFileCopySender = nil
        heldKeys.removeAll()
        heldPointerButtons = []
        inputGeneration = UUID()
        frameDecoders.cancel()
        appleClipboardSendPending = nil
        appleClipboardSendGeneration = UUID()
        appleRecordCodec?.close()
        appleRecordCodec = nil
        appleWrapKey = nil
        decryptedReadBuffer.removeAll()
        firstFrameDeadline = nil
        inputLock.unlock()
        AppLogger.shared.info("Disconnecting session with \(host)", category: "Network")
        stopTransportReports()
        let previous = connection
        connection = nil
        closingConnection = nil
        readBuffer.removeAll()
        appleClipboardReadID = nil
        // Invalidate callbacks before cancellation can deliver a terminal receive.
        previous?.cancel()
        state = .disconnected
    }

    /// Send a final complete chord before ending this socket's outgoing stream.
    /// Completion and timeout are scoped to the captured socket, never its replacement.
    public func disconnect(afterSendingKeySequence sequence: [(key: UInt32, down: Bool)]) {
        var packet = Data()
        for event in sequence { packet.append(RFBEncoder.encodeKeyEvent(down: event.down, keySym: event.key)) }
        disconnect(afterSendingFinalPacket: packet)
    }

    public func disconnect(performing action: DisconnectAction, deviceType: RemoteDevice.DeviceType) {
        let packet = action.encodedPacket(type: deviceType, width: framebuffer.width, height: framebuffer.height)
        if packet.isEmpty { disconnect() }
        else { disconnect(afterSendingFinalPacket: packet) }
    }

    private func disconnect(afterSendingFinalPacket packet: Data) {
        inputLock.lock()
        defer { inputLock.unlock() }
        if let current = connection, closingConnection === current { return }
        guard let current = connection, state == .connected, inputEnabled else {
            disconnect()
            return
        }
        guard closingConnection !== current else { return }
        closingConnection = current
        setInputEnabled(false)
        if appleRecordCodec != nil {
            sendData(packet) { [self, weak current] in
                guard let current, self.connection === current else { return }
                self.disconnect()
            }
            queue.asyncAfter(deadline: .now() + 2) { [self, weak current] in
                guard let current, self.connection === current else { return }
                self.disconnect()
            }
            return
        }
        current.send(content: packet, isComplete: true, completion: .contentProcessed { [self, weak current] _ in
            guard let current, self.connection === current else { return }
            self.disconnect()
        })
        queue.asyncAfter(deadline: .now() + 2) { [self, weak current] in
            guard let current, self.connection === current else { return }
            self.disconnect()
        }
    }

    // MARK: - Handshake Workflow

    /// A state observer may synchronously replace the connection. The caller's
    /// handshake work belongs only to the socket that published this state.
    private func transitionCurrentConnection(to newState: State) -> Bool {
        guard let current = connection else { return false }
        state = newState
        return connection === current
    }

    private func startHandshake() {
        guard transitionCurrentConnection(to: .negotiatingVersion) else { return }
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
            self.appleServerBanner = data == Data("RFB 003.889\n".utf8)

            let modernProbe = self.experimentalAppleCursor && (self.experimentalAppleModernBootstrap || self.experimentalAppleEncryption) && self.appleServerBanner
            let reply = modernProbe ? "RFB 003.889\n" : RFBConstants.protocolVersion38
            let versionReply = Data(reply.utf8)
            AppLogger.shared.info("Sending client version: \(reply.trimmingCharacters(in: .whitespacesAndNewlines))", category: "RFB")
            self.sendData(versionReply) {
                self.negotiateSecurity()
            }
        }
    }

    private func negotiateSecurity() {
        guard transitionCurrentConnection(to: .authenticating) else { return }
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
        if let key = experimentalAppleSRPKey {
            guard appleServerBanner, experimentalAppleCursor, experimentalAppleEncryption,
                  types.contains(.ardAuth33), let username, !username.isEmpty,
                  let password, !password.isEmpty else {
                handleFailure("Experimental SRP requires the native profile and configured account")
                return
            }
            performAppleSRP(username: username, password: password, subjectPublicKeyInfo: key)
            return
        }
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

    private func performAppleSRP(username: String, password: String, subjectPublicKeyInfo: Data) {
        let pendingConnection = connection
        do {
            let key = try AppleRSA1Identity.validateSubjectPublicKeyInfo(subjectPublicKeyInfo)
            let identity = try AppleRSA1Identity.identityPacket(username: username, key: key)
            sendData(Data([33]) + identity) { [weak self] in
                guard let self else { return }
                self.readExact(4) { prefix in
                    guard let prefix else { return }
                    let length = prefix.reduce(0) { $0 << 8 | Int($1) }
                    guard (10...(AppleSRPChallenge.maximumFrameBytes - 4)).contains(length) else {
                        self.handleFailure("Invalid SRP challenge length"); return
                    }
                    self.readExact(length) { body in
                        guard let body else { return }
                        do {
                            let challenge = try AppleSRPChallenge(frame: prefix + body)
                            self.decodeQueue.async { [weak self] in
                                guard let self else { return }
                                do {
                                    let proof = try AppleSRP6aProof.compute(challenge: challenge,
                                        password: password, tokenPadding: .groupWidth)
                                    let packet = try AppleSRPProofPacket.encode(clientPublic: proof.clientPublic,
                                        clientProof: proof.clientProof, options: challenge.options)
                                    self.queue.async {
                                        guard self.connection === pendingConnection, self.state == .authenticating else { return }
                                        self.sendData(packet) {
                                            self.readExact(4) { prefix in
                                                guard let prefix else { return }
                                                guard prefix == Data([0, 0, 0, 98]) else {
                                                    self.handleFailure("SRP server proof was not returned"); return
                                                }
                                                self.readExact(98) { body in
                                                    guard let body else { return }
                                                    do {
                                                        let final = try AppleSRPServerProof(frame: prefix + body, expectedStep: 2)
                                                        self.appleWrapKey = try proof.verifiedWrapKey(serverProof: final.proof)
                                                        self.handleSecurityResult(type: .ardAuth33)
                                                    } catch { self.handleFailure("SRP server proof verification failed") }
                                                }
                                            }
                                        }
                                    }
                                } catch {
                                    self.queue.async {
                                        guard self.connection === pendingConnection, self.state == .authenticating else { return }
                                        self.handleFailure("SRP challenge could not be processed")
                                    }
                                }
                            }
                        } catch { self.handleFailure("Invalid SRP challenge") }
                    }
                }
            }
        } catch { handleFailure("Invalid SRP server public key") }
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
                        let exchange = try ARDAuthCrypto.exchange(generator: generator,
                            prime: Data(challenge.prefix(length)), peer: Data(challenge.suffix(length)),
                            username: username, password: password)
                        if self.experimentalAppleEncryption { self.appleWrapKey = exchange.wrapKey }
                        self.sendData(exchange.response) { self.handleSecurityResult(type: .ardDiffieHellman) }
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
                // Verified only for Apple's banner plus Mac-account branch.
                // Standard 3.8 transport remains unchanged; this is not a
                // high-performance or encrypted-session capability claim.
                self.appleClipboard = self.appleServerBanner && type == .ardDiffieHellman
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
        guard transitionCurrentConnection(to: .initializing) else { return }
        // ClientInit: 1 byte shared-flag (1 = shared, allows existing sessions to continue)
        let modernProbe = experimentalAppleCursor && (experimentalAppleModernBootstrap || experimentalAppleEncryption) && appleServerBanner
        sendData(Data([modernProbe ? 0xc1 : 1])) { [weak self] in
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
                if self.experimentalAppleEncryption && self.experimentalAppleCursor && self.appleServerBanner {
                    self.setupAppleEncryptedSession(serverInit: serverInit)
                } else { self.setupSession(serverInit: serverInit) }
            }
        }
    }

    private func setupAppleEncryptedSession(serverInit: RFBServerInit) {
        guard let wrapKey = appleWrapKey else {
            handleFailure("Native encryption requires Mac account authentication")
            return
        }
        appleWrapKey = nil
        sendData(AppleViewerInfo.encode())
        sendData(AppleEncryptionControl.requestReceiveEncryption)
        readRawExact(4) { [weak self] update in
            guard let self, let update else { return }
            guard update == Data([0, 0, 0, 1]) else {
                self.handleFailure("Invalid native encryption update header"); return
            }
            self.readRawExact(12) { rectangle in
                guard let rectangle else { return }
                guard AppleEncryptionControl.isInitialRekey(updateHeader: update, rectangleHeader: rectangle) else {
                    self.handleFailure("Invalid native encryption rekey envelope"); return
                }
                self.readRawExact(36) { payload in
                    guard let payload else { return }
                    do {
                        let codec = try AppleRFBRecordLayer(wrapKey: wrapKey)
                        try codec.installRekey(payload)
                        // Both messages are cleartext; subsequent writes use records.
                        self.sendData(self.experimentalAppleControlMode ? AppleEncryptionControl.normalControl : AppleEncryptionControl.observe)
                        self.sendData(AppleEncryptionControl.enableSendEncryption)
                        self.appleRecordCodec = codec
                        self.setupSession(serverInit: serverInit)
                    } catch { self.handleFailure("Native encryption rekey failed") }
                }
            }
        }
    }

    private func setupSession(serverInit: RFBServerInit) {
        AppLogger.shared.info("Configuring session: \(colorDepth.pixelFormat.bitsPerPixel)-bit pixel format...", category: "RFB")
        if experimentalAppleCursor && appleServerBanner && appleRecordCodec == nil { sendData(AppleViewerInfo.encode()) }
        // Negotiate wire precision; decoded frames always use BGRA32 for rendering.
        let pixelFormatData = RFBEncoder.encodeSetPixelFormat(colorDepth.pixelFormat)
        if appleRecordCodec == nil { sendData(pixelFormatData) }
        else {
            guard let configuration = AppleDisplayConfiguration.fixed(width: framebuffer.width, height: framebuffer.height,
                logicalWidth: experimentalAppleLogicalSize?.width, logicalHeight: experimentalAppleLogicalSize?.height,
                physicalSize: experimentalApplePhysicalSize) else {
                handleFailure("Invalid native fixed display geometry"); return
            }
            sendData(configuration)
        }

        // Advertise only implemented formats, retaining Zlib/Raw fallbacks.
        AppLogger.shared.info("Setting encodings: ZRLE, Zlib, CopyRect, DesktopSize, Raw...", category: "RFB")
        let encodings = currentEncodings()
        let encodingsData = RFBEncoder.encodeSetEncodings(encodings)
        sendData(encodingsData)
        if appleRecordCodec != nil && experimentalAppleCombinedDisplay {
            sendData(AppleDisplayConfiguration.selection())
        }
        if appleRecordCodec != nil { sendData(pixelFormatData) }

        guard transitionCurrentConnection(to: .connected) else { return }
        AppLogger.shared.info("Session state -> connected! Requesting initial full-frame update (0,0,\(framebuffer.width)x\(framebuffer.height))...", category: "RFB")

        firstFrameDeadline = NativeFirstFrameDeadline(now: ProcessInfo.processInfo.systemUptime)
        if let current = connection { scheduleFirstFrameDeadline(connection: current, delay: 20) }

        if appleClipboard {
            sendData(AppleClipboardControl.monitoring(true))
            requestAppleClipboard()
        }

        if appleRecordCodec != nil {
            // Native streaming starts with a full fetch, then arms server pushes.
            requestUpdate(incremental: false)
            if let arm = AppleFramebufferControl.arm(width: framebuffer.width, height: framebuffer.height) {
                sendData(arm)
            }
        } else {
            if experimentalAppleCursor && appleServerBanner,
               let arm = AppleFramebufferControl.arm(width: framebuffer.width, height: framebuffer.height) {
                sendData(arm)
            }
            requestUpdate(incremental: false)
        }

        // Start server message loop
        startMessageLoop()
    }

    private func scheduleFirstFrameDeadline(connection current: NWConnection, delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self, weak current] in
            guard let self, let current, self.connection === current,
                  self.state == .connected, !self.hasReceivedPixelUpdate else { return }
            if let deadline = self.firstFrameDeadline {
                let remaining = deadline.remaining(now: ProcessInfo.processInfo.systemUptime)
                if remaining > 0 {
                    self.scheduleFirstFrameDeadline(connection: current, delay: remaining)
                    return
                }
            }
            self.handleFailure(Self.timeoutMessage(for: .connected))
        }
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
            // Native status is a control-channel message independent of whether
            // this authentication branch has clipboard capability verified.
            case 0x14 where self.appleClipboard || self.appleRecordCodec != nil:
                self.handleAppleClipboardStatus()
            case 0x22 where self.appleServerBanner:
                self.handleAppleFileCopyMessage()
            case 0x1f where self.appleClipboard:
                self.handleAppleClipboardArchive()
            default:
                // RFB messages have no shared length field. Skipping only the
                // type would reinterpret an unknown body as future messages.
                self.handleFailure("Unsupported server message type: \(msgType)")
            }
        }
    }

    private func handleAppleFileCopyMessage() {
        // Type byte was consumed by the loop. Bound the remaining payload
        // before readExact allocates or waits for attacker-controlled lengths.
        readExact(5) { [weak self] header in
            guard let self, let header else { return }
            let length = header.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard (8...1_048_576).contains(length) else {
                self.handleFailure("Invalid native file-copy message length")
                return
            }
            self.readExact(Int(length)) { [weak self] payload in
                guard let self, let payload else { return }
                var packet = Data([0x22])
                packet.append(header)
                packet.append(payload)
                do {
                    guard let decoded = try AppleFileCopyMessage.decode(packet),
                          decoded.consumedBytes == packet.count else {
                        self.handleFailure("Invalid native file-copy message")
                        return
                    }
                    self.inputLock.lock()
                    let receiver = self.appleFileCopyReceiver
                    let sender = self.appleFileCopySender
                    self.inputLock.unlock()
                    if let sender, sender.sessionID == decoded.message.sessionID,
                       decoded.message.command == 200 || decoded.message.command == 300 {
                        _ = sender.enqueue(decoded.message)
                    }
                    if let receiver, (101...104).contains(decoded.message.command),
                       receiver.sessionID == decoded.message.sessionID,
                       !receiver.enqueue(decoded.message), receiver.requiresTransportFailure {
                        self.handleFailure("Native file-copy receive queue unavailable")
                        return
                    }
                    self.onAppleFileCopyReceived?(decoded.message)
                    self.startMessageLoop()
                } catch {
                    self.handleFailure("Invalid native file-copy message")
                }
            }
        }
    }

    private func handleFramebufferUpdate() {
        // Header: [pad: 1 byte] [numRects: 2 bytes] = 3 bytes
        readExact(3) { [weak self] headerData in
            guard let self = self, let headerData = headerData else { return }
            self.updateHasDisplayLayout = false
            self.updateHasPixels = false
            self.updateHasCursorShape = false
            let numRects = headerData.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            self.readRectangles(count: Int(numRects))
        }
    }

    private func readRectangles(count: Int) {
        guard count > 0 else {
            if updateHasPixels { hasReceivedPixelUpdate = true }
            // Loading progress is only useful until the first desktop is visible.
            // A display-layout acknowledgement alone is not the first visible desktop.
            if updateHasPixels || (hasReceivedPixelUpdate && !updateHasDisplayLayout && !updateHasCursorShape) {
                hasCompletedFramebufferUpdate = true
                onFrameUpdated?()
            }
            // Cursor/layout-only replies do not satisfy the initial desktop fetch.
            // An incremental request before pixels arrive can leave a static Mac
            // waiting indefinitely because there is no changed desktop region.
            if appleRecordCodec == nil { requestUpdate(incremental: hasReceivedPixelUpdate) }
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

            if self.appleRecordCodec != nil {
                let source = self.connection
                self.onNativeRectangleReceived?(Int(header.width), Int(header.height), header.encoding.rawValue)
                guard self.connection === source, self.appleRecordCodec != nil else { return }
            }

            switch header.encoding {
            case .tight:
                guard let source = self.connection else { return }
                let width = Int(header.width), height = Int(header.height)
                guard Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height else {
                    self.handleFailure("Invalid Tight rectangle bounds")
                    return
                }
                self.readTightRectangle(x: Int(header.x), y: Int(header.y), width: width, height: height,
                                        remaining: count - 1, prefix: Data(), source: source)
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
                    if self.appleRecordCodec != nil {
                        self.onNativePayloadLength?(length)
                        guard self.connection === sourceConnection else { return }
                    }
                    let measurePayload = self.onZRLETiming != nil || self.onPixelTransferSample != nil
                    let payloadStarted = measurePayload ? ProcessInfo.processInfo.systemUptime : 0
                    self.readExact(length, trackPixelPayload: true) { [weak self] compressed in
                        guard let self, let compressed, self.connection === sourceConnection else { return }
                        let payloadElapsed = measurePayload ? ProcessInfo.processInfo.systemUptime - payloadStarted : 0
                        if self.appleRecordCodec != nil {
                            self.onNativePixelPayloadReady?(compressed.count)
                            guard self.connection === sourceConnection else { return }
                        }
                        let measureNativeDecode = self.appleRecordCodec != nil && self.onNativePixelDecodeCompleted != nil
                        let measureDecode = measureNativeDecode || measurePayload
                        let decoders = self.frameDecoders
                        self.decodeQueue.async { [weak self] in
                            guard !decoders.isCancelled else { return }
                            let decodeStarted = measureDecode ? ProcessInfo.processInfo.systemUptime : 0
                            let decoded = decoders.zrle.decode(data: compressed, width: width, height: height)
                            let decodeElapsed = measureDecode ? ProcessInfo.processInfo.systemUptime - decodeStarted : 0
                            self?.queue.async { [weak self] in
                                guard let self, self.connection === sourceConnection else { return }
                                guard let pixels = decoded else {
                                    self.handleFailure("Invalid ZRLE pixel data")
                                    return
                                }
                                if measureNativeDecode {
                                    self.onNativePixelDecodeCompleted?(decodeElapsed)
                                    guard self.connection === sourceConnection else { return }
                                }
                                if measurePayload {
                                    self.onZRLETiming?(compressed.count, payloadElapsed, decodeElapsed)
                                    guard self.connection === sourceConnection else { return }
                                    self.onPixelTransferSample?(compressed.count, payloadElapsed)
                                    guard self.connection === sourceConnection else { return }
                                }
                                self.framebuffer.updateRect(x: Int(header.x), y: Int(header.y), width: width,
                                                            height: height, rawData: pixels)
                                self.updateHasPixels = true
                                self.readRectangles(count: count - 1)
                            }
                        }
                    }
                }

            case .zlib:
                guard let sourceConnection = self.connection else { return }
                let width = Int(header.width), height = Int(header.height)
                guard width > 0, height > 0,
                      Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height,
                      width <= ZRLEDecoder.maximumPixelBytes / 4 / height else {
                    self.handleFailure("Invalid Zlib rectangle size")
                    return
                }
                let expectedBytes = width * height * self.colorDepth.bytesPerPixel
                self.readExact(4) { [weak self] lengthData in
                    guard let self, let lengthData, self.connection === sourceConnection else { return }
                    let length = Int(lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                    guard length > 0, length <= expectedBytes * 2 + 1024 else {
                        self.handleFailure("Invalid Zlib compressed length")
                        return
                    }
                    self.readExact(length, trackPixelPayload: true) { [weak self] compressed in
                        guard let self, let compressed, self.connection === sourceConnection else { return }
                        let decoders = self.frameDecoders
                        self.decodeQueue.async { [weak self] in
                            guard !decoders.isCancelled else { return }
                            let decoded = decoders.zlib.decompress(data: compressed, expectedBytes: expectedBytes)
                                .flatMap { decoders.colorDepth.expandPixels($0) }
                            self?.queue.async { [weak self] in
                                guard let self, self.connection === sourceConnection else { return }
                                guard let pixels = decoded else {
                                    self.handleFailure("Invalid Zlib pixel data")
                                    return
                                }
                                self.framebuffer.updateRect(x: Int(header.x), y: Int(header.y), width: width,
                                                            height: height, rawData: pixels)
                                self.updateHasPixels = true
                                self.readRectangles(count: count - 1)
                            }
                        }
                    }
                }

            case .raw:
                guard let sourceConnection = self.connection else { return }
                let width = Int(header.width), height = Int(header.height)
                guard Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height,
                      height == 0 || width <= ZRLEDecoder.maximumPixelBytes / 4 / height else {
                    self.handleFailure("Invalid Raw rectangle size")
                    return
                }
                let pixelBytes = width * height * self.colorDepth.bytesPerPixel
                self.readExact(pixelBytes, trackPixelPayload: true) { [weak self] pixelData in
                    guard let self, let pixelData, self.connection === sourceConnection else { return }
                    let commit: @Sendable (Data?) -> Void = { [weak self] expanded in
                        guard let self, self.connection === sourceConnection else { return }
                        guard let expanded else { self.handleFailure("Invalid Raw pixel data"); return }
                        self.updateHasPixels = pixelBytes > 0 || self.updateHasPixels
                        self.framebuffer.updateRect(x: Int(header.x), y: Int(header.y), width: width,
                                                    height: height, rawData: expanded)
                        self.readRectangles(count: count - 1)
                    }
                    if self.colorDepth == .fullColor {
                        commit(pixelData)
                    } else {
                        let decoders = self.frameDecoders
                        self.decodeQueue.async { [weak self] in
                            guard !decoders.isCancelled else { return }
                            let expanded = decoders.colorDepth.expandPixels(pixelData)
                            self?.queue.async { commit(expanded) }
                        }
                    }
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
                guard let source = self.connection else { return }
                self.updateHasDisplayLayout = true
                // Screen resolution changed on remote Mac!
                AppLogger.shared.info("Remote desktop resized to \(header.width)x\(header.height)", category: "RFB")
                if self.framebuffer.width != Int(header.width) || self.framebuffer.height != Int(header.height) {
                    self.framebuffer.resize(newWidth: Int(header.width), newHeight: Int(header.height))
                }
                self.onDisplayLayoutReceived?(nil)
                guard self.connection === source else { return }
                if self.appleRecordCodec != nil,
                   let arm = AppleFramebufferControl.arm(width: self.framebuffer.width, height: self.framebuffer.height) {
                    self.sendData(arm)
                    self.requestUpdate(incremental: false)
                }
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

            case .appleDisplayLayout:
                self.updateHasDisplayLayout = true
                guard let source = self.connection else { return }
                self.readExact(2) { [weak self] prefix in
                    guard let self, let prefix, self.connection === source else { return }
                    let length = Int(prefix[0]) << 8 | Int(prefix[1])
                    guard length >= 2 else {
                        self.handleFailure("Invalid native display layout length"); return
                    }
                    self.readExact(length) { [weak self] body in
                        guard let self, let body, self.connection === source else { return }
                        self.onNativeLayoutPayload?(body)
                        guard self.connection === source else { return }
                        // The experimental field model has known version skew.
                        // Never resize using guessed offsets or apply later pixels
                        // to potentially stale geometry. A real payload is required.
                        self.handleFailure("Native display layout geometry is not yet validated")
                    }
                }

            case .appleCursor:
                self.updateHasCursorShape = true
                guard let source = self.connection else { return }
                let decoders = self.frameDecoders
                self.readExact(8) { [weak self] prefix in
                    guard let self, let prefix, self.connection === source else { return }
                    let size = Int(prefix.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian })
                    guard size <= AppleCursorCache.maximumCompressedBytes else {
                        self.handleFailure("Invalid Apple cursor length")
                        return
                    }
                    let validSelect = size == 0 && header.width == 0 && header.height == 0 && header.x == 0 && header.y == 0
                    let validStore = size > 0 && header.width > 0 && header.height > 0 &&
                        Int(header.width) <= RFBRemoteCursor.maximumDimension &&
                        Int(header.height) <= RFBRemoteCursor.maximumDimension &&
                        header.x < header.width && header.y < header.height
                    guard validSelect || validStore else {
                        self.handleFailure("Invalid Apple cursor geometry")
                        return
                    }
                    let decode: @Sendable (Data) -> Void = { [weak self] payload in
                        guard let self, self.connection === source else { return }
                        self.decodeQueue.async { [weak self] in
                            guard !decoders.isCancelled else { return }
                            let result = Result {
                                try decoders.appleCursor.decode(message: prefix + payload,
                                    width: Int(header.width), height: Int(header.height),
                                    hotspotX: Int(header.x), hotspotY: Int(header.y))
                            }
                            self?.queue.async { [weak self] in
                                guard let self, self.connection === source else { return }
                                switch result {
                                case .success(let shape):
                                    if let shape {
                                        self.onCursorReceived?(shape)
                                        guard self.connection === source else { return }
                                        self.onAppleCursorReceived?(shape)
                                    }
                                    guard self.connection === source else { return }
                                    self.readRectangles(count: count - 1)
                                case .failure:
                                    self.handleFailure("Invalid Apple cursor data")
                                }
                            }
                        }
                    }
                    if size == 0 { decode(Data()) }
                    else { self.readExact(size) { if let data = $0 { decode(data) } } }
                }

            case .cursor:
                self.updateHasCursorShape = true
                guard let source = self.connection,
                      let size = RFBRemoteCursor.payloadSize(width: Int(header.width), height: Int(header.height), depth: self.colorDepth),
                      header.width == 0 || header.height == 0 ||
                        (header.x < header.width && header.y < header.height) else {
                    self.handleFailure("Invalid remote cursor geometry")
                    return
                }
                let depth = self.colorDepth
                let decoders = self.frameDecoders
                let publish: @Sendable (RFBRemoteCursor?) -> Void = { [weak self] cursor in
                    guard let self, self.connection === source else { return }
                    guard let cursor else {
                        self.handleFailure("Invalid remote cursor data")
                        return
                    }
                    self.onCursorReceived?(cursor)
                    guard self.connection === source else { return }
                    self.readRectangles(count: count - 1)
                }
                if size == 0 {
                    publish(RFBRemoteCursor.decode(width: Int(header.width), height: Int(header.height),
                        hotspotX: Int(header.x), hotspotY: Int(header.y), depth: depth, payload: Data()))
                } else {
                    self.readExact(size) { [weak self] data in
                        guard let self, let data, self.connection === source else { return }
                        self.decodeQueue.async { [weak self] in
                            guard !decoders.isCancelled else { return }
                            let cursor = RFBRemoteCursor.decode(width: Int(header.width), height: Int(header.height),
                                hotspotX: Int(header.x), hotspotY: Int(header.y), depth: depth, payload: data)
                            self?.queue.async { publish(cursor) }
                        }
                    }
                }

            case .lastRect:
                self.readRectangles(count: 0)
                return

            default:
                AppLogger.shared.warning("Unhandled encoding \(header.encoding.rawValue) for rect \(header.width)x\(header.height)", category: "RFB")
                // Unknown bodies have no generic length prefix. Skipping only
                // their header would parse payload bytes as later rectangles.
                self.handleFailure("Unsupported framebuffer encoding \(header.encoding.rawValue)")
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

    private func requestAppleClipboard() {
        guard appleClipboard, state == .connected else { return }
        if appleClipboardRequestPending {
            appleClipboardRefetchRequested = true
            return
        }
        appleClipboardRequestPending = true
        sendData(AppleClipboardControl.request())
    }

    private func handleAppleClipboardStatus() {
        guard let source = connection else { return }
        beginAppleClipboardRead(connection: source)
        readExact(7) { [weak self] body in
            guard let self, let body, self.connection === source else { return }
            self.appleClipboardReadID = nil
            guard body[1] == 0, body[2] == 4 else {
                self.handleFailure("Invalid native clipboard status")
                return
            }
            let command = UInt16(body[5]) << 8 | UInt16(body[6])
            self.onAppleStatusReceived?(command)
            guard self.connection === source else { return }
            if command == 2 { self.requestAppleClipboard() }
            self.startMessageLoop()
        }
    }

    private func handleAppleClipboardArchive() {
        guard let source = connection else { return }
        beginAppleClipboardRead(connection: source)
        readExact(15) { [weak self] header in
            guard let self, let header, self.connection === source else { return }
            let packetHeader = Data([0x1f]) + header
            let plainSize = packetHeader[8..<12].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let compressedSize = packetHeader[12..<16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            guard plainSize <= AppleClipboardArchive.maximumBytes,
                  compressedSize > 0, compressedSize <= AppleClipboardArchive.maximumBytes else {
                self.handleFailure("Native clipboard exceeds the supported size")
                return
            }
            self.readExact(Int(compressedSize)) { [weak self] compressed in
                guard let self, let compressed, self.connection === source else { return }
                self.appleClipboardReadID = nil
                let packet = packetHeader + compressed
                self.decodeQueue.async { [weak self] in
                    let result = try? AppleClipboardArchive.decode(message: packet)
                    self?.queue.async { [weak self] in
                        guard let self, self.connection === source else { return }
                        guard let result else {
                            self.handleFailure("Invalid native clipboard archive")
                            return
                        }
                        self.appleClipboardRequestPending = false
                        let refetch = self.appleClipboardRefetchRequested
                        self.appleClipboardRefetchRequested = false
                        switch result {
                        case .text(let text): self.onClipboardReceived?(text)
                        case .empty: self.onClipboardReceived?("")
                        case .unsupported, .promise: break
                        }
                        guard self.connection === source else { return }
                        if refetch { self.requestAppleClipboard() }
                        self.startMessageLoop()
                    }
                }
            }
        }
    }

    private func beginAppleClipboardRead(connection source: NWConnection) {
        let readID = UUID()
        appleClipboardReadID = readID
        queue.asyncAfter(deadline: .now() + 15) { [weak self, weak source] in
            guard let self, let source, self.connection === source,
                  self.appleClipboardReadID == readID else { return }
            self.handleFailure("Native clipboard data timed out")
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

    // Transport-queue confined. A quality hint does not change pixel format.
    private var requestedJPEGQuality: Int?

    private func currentEncodings() -> [RFBConstants.EncodingType] {
        var encodings: [RFBConstants.EncodingType] = [
            .zrle,
            .zlib,
            .copyRect,
            .desktopSize,
            .extendedDesktopSize,
            .extendedClipboard
        ]
        // The standard RFB Tight receive path is implemented and covered by
        // actual fragmented TCP tests. Keep ZRLE first until adaptive quality
        // explicitly selects Tight, and preserve Apple's native configuration.
        if appleRecordCodec == nil {
            encodings.insert(.tight, at: requestedJPEGQuality == nil ? 1 : 0)
            if let quality = requestedJPEGQuality {
                encodings.append(.init(rawValue: Int32(-32 + quality)))
            }
        }
        if experimentalAppleCursor && appleServerBanner { encodings.append(.appleCursor) }
        else { encodings.append(.cursor) }
        if appleRecordCodec != nil && experimentalAppleLayoutDiagnostic { encodings.append(.appleDisplayLayout) }
        encodings.append(.raw)
        return encodings
    }

    /// nil restores lossless preference. JPEG levels are server hints, not a
    /// promise of effective image quality; native Apple sessions are unchanged.
    public func setCompressionQuality(jpegQuality: Int?) {
        guard jpegQuality.map({ (0...9).contains($0) }) ?? true else { return }
        queue.async { [weak self] in
            guard let self, self.requestedJPEGQuality != jpegQuality else { return }
            self.requestedJPEGQuality = jpegQuality
            guard self.state == .connected, self.appleRecordCodec == nil else { return }
            self.sendData(RFBEncoder.encodeSetEncodings(self.currentEncodings()))
        }
    }

    // MARK: - Public Client Controls (Pointer, Keyboard, Clipboard)

    /// Request a screen update from the remote server.
    public func requestUpdate(incremental: Bool) {
        if appleRecordCodec != nil {
            let source = connection
            onNativeUpdateRequested?(incremental)
            guard connection === source, appleRecordCodec != nil else { return }
        }
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
        if inputEnabled != enabled {
            inputGeneration = UUID()
            appleClipboardSendGeneration = UUID()
        }
        if !enabled && inputEnabled {
            for key in heldKeys { sendData(RFBEncoder.encodeKeyEvent(down: false, keySym: key)) }
            heldKeys.removeAll()
            if !heldPointerButtons.isEmpty {
                sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
            }
            heldPointerButtons = []
            pendingClipboard = nil
            appleClipboardSendPending = nil
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

    /// Native viewport/input identity changes invalidate delayed wheels without
    /// dropping held keyboard keys or changing the latest pointer position.
    public func cancelPendingWheelEvents() {
        inputLock.lock()
        inputGeneration = UUID()
        inputLock.unlock()
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

    /// Send mouse movement or button press. onWheelSent runs after a delayed wheel's
    /// press/release pair is enqueued; cancelled work does not invoke it.
    public func sendPointerEvent(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16, onWheelSent: (@Sendable () -> Void)? = nil) {
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
                // Completion runs outside inputLock, after both pulse packets are queued.
                if self.sendWheelPacket(RFBConstants.ButtonMask(rawValue: buttonMask.rawValue & 0x78), generation: generation) {
                    onWheelSent?()
                }
            }
        }
    }

    /// Send a key press or release.
    public func sendKeyEvent(down: Bool, keySym: UInt32) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, state == .connected else { return }
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
        if appleClipboard, let current = connection {
            let normalized = RFBEncoder.clipboardText(text, extended: false)
            guard normalized.utf8.count <= 1_048_000 else { return false }
            appleClipboardSendPending = (normalized, current, appleClipboardSendGeneration)
            if !appleClipboardSendActive {
                appleClipboardSendActive = true
                decodeQueue.async { [weak self] in self?.drainAppleClipboardSend() }
            }
            return true
        }
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

    /// The owner calls this only after session negotiation. Installing a
    /// receiver never negotiates or advertises a transfer by itself.
    @discardableResult
    func installAppleFileCopyReceiver(_ receiver: AppleFileCopyReceiveWorker) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, appleServerBanner, appleFileCopyReceiver == nil,
              appleFileCopySender?.sessionID != receiver.sessionID else { return false }
        appleFileCopyReceiver = receiver
        return true
    }

    func removeAppleFileCopyReceiver(_ receiver: AppleFileCopyReceiveWorker) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard appleFileCopyReceiver === receiver else { return }
        appleFileCopyReceiver = nil
        receiver.cancel()
    }

    /// Installation follows successful transfer negotiation; starting is explicit.
    @discardableResult
    func installAppleFileCopySender(_ sender: AppleFileCopySendWorker) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, appleServerBanner, inputEnabled,
              appleFileCopySender == nil,
              appleFileCopyReceiver?.sessionID != sender.sessionID else { return false }
        appleFileCopySender = sender
        return true
    }

    func removeAppleFileCopySender(_ sender: AppleFileCopySendWorker) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard appleFileCopySender === sender else { return }
        appleFileCopySender = nil
        sender.cancel()
    }

    /// Bind a negotiated owner's multi-step startup to the current input/socket
    /// lifetime. Revoked tokens must never adopt a replacement connection.
    var fileCopyTransportGeneration: UUID? {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, appleServerBanner, inputEnabled, connection != nil else { return nil }
        return inputGeneration
    }

    /// Internal transport primitive. The transfer coordinator must negotiate
    /// the session/command first; this does not advertise file-copy support.
    /// True means queued, never acknowledged or persisted remotely.
    /// For admitted packets, processed reports local transport completion or
    /// invalidation exactly once. A false return does not schedule a callback.
    @discardableResult
    func sendAppleFileCopy(_ message: AppleFileCopyMessage,
                          expectedGeneration: UUID? = nil,
                          processed: (@Sendable (Bool) -> Void)? = nil) -> Bool {
        guard let packet = try? message.encode() else { return false }
        inputLock.lock()
        guard state == .connected, appleServerBanner, inputEnabled,
              expectedGeneration == nil || expectedGeneration == inputGeneration,
              let current = connection else { inputLock.unlock(); return false }
        let generation = inputGeneration
        inputLock.unlock()
        queue.async { [weak self] in
            guard let self else { processed?(false); return }
            self.inputLock.lock()
            guard self.connection === current, self.state == .connected,
                  self.inputEnabled, self.inputGeneration == generation else {
                self.inputLock.unlock()
                processed?(false)
                return
            }
            self.sendData(packet, processed: processed)
            self.inputLock.unlock()
        }
        return true
    }

    private func drainAppleClipboardSend() {
        inputLock.lock()
        guard let pending = appleClipboardSendPending else {
            appleClipboardSendActive = false
            inputLock.unlock()
            return
        }
        appleClipboardSendPending = nil
        inputLock.unlock()
        let packet = try? AppleClipboardArchive.encode(text: pending.text)
        queue.async { [weak self] in
            guard let self else { return }
            self.inputLock.lock()
            if let packet, self.connection === pending.connection,
               self.state == .connected, self.inputEnabled,
               self.appleClipboardSendGeneration == pending.generation {
                self.sendData(packet)
            }
            self.inputLock.unlock()
            // Yield to already queued frame/clipboard decoding between sends.
            self.decodeQueue.async { [weak self] in self?.drainAppleClipboardSend() }
        }
    }

    private func sendData(_ data: Data, completion: (@Sendable () -> Void)? = nil,
                          processed: (@Sendable (Bool) -> Void)? = nil) {
        guard let connection else { processed?(false); return }
        let wire: Data
        inputLock.lock()
        do {
            if let codec = appleRecordCodec {
                var encoded = Data()
                var offset = 0
                while offset < data.count {
                    let end = min(data.count, offset + AppleRFBRecordLayer.maximumBodySize)
                    encoded.append(try codec.seal(data.subdata(in: offset..<end)))
                    offset = end
                }
                wire = encoded
            } else { wire = data }
            inputLock.unlock()
        } catch {
            inputLock.unlock()
            handleFailure("Native encrypted write failed")
            processed?(false)
            return
        }
        connection.send(content: wire, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self, let connection, self.connection === connection else {
                processed?(false)
                return
            }
            if let error = error {
                self.handleFailure(Self.transportFailureMessage(error, state: self.state))
                processed?(false)
                return
            }
            self.collectTransportReportIfDue(connection: connection)
            processed?(true)
            completion?()
        }))
    }

    private func readTightRectangle(x: Int, y: Int, width: Int, height: Int, remaining: Int,
                                    prefix: Data, source: NWConnection,
                                    payloadStarted: TimeInterval? = nil, payloadBytes: Int = 0) {
        guard connection === source else { return }
        let decoders = frameDecoders
        switch TightPacketLayout.next(prefix, width: width, height: height, colorDepth: decoders.colorDepth) {
        case .invalid:
            handleFailure("Invalid Tight rectangle layout")
        case .need(let bytes, let pixelPayload):
            let started = pixelPayload ? (payloadStarted ?? ProcessInfo.processInfo.systemUptime) : payloadStarted
            let sampleBytes = payloadBytes + (pixelPayload ? bytes : 0)
            readExact(bytes, trackPixelPayload: pixelPayload) { [weak self] chunk in
                guard let self, let chunk, self.connection === source else { return }
                self.readTightRectangle(x: x, y: y, width: width, height: height, remaining: remaining,
                                        prefix: prefix + chunk, source: source,
                                        payloadStarted: started, payloadBytes: sampleBytes)
            }
        case .complete:
            let receiveDuration = payloadStarted.map { ProcessInfo.processInfo.systemUptime - $0 }
            decodeQueue.async { [weak self] in
                guard !decoders.isCancelled else { return }
                let result = decoders.tight.decode(prefix, width: width, height: height, colorDepth: decoders.colorDepth)
                self?.queue.async { [weak self] in
                    guard let self, self.connection === source else { return }
                    guard case .decoded(let pixels, let consumed) = result, consumed == prefix.count else {
                        self.handleFailure("Invalid Tight pixel data")
                        return
                    }
                    if let receiveDuration {
                        self.onPixelTransferSample?(payloadBytes, receiveDuration)
                        guard self.connection === source else { return }
                    }
                    self.framebuffer.updateRect(x: x, y: y, width: width, height: height, rawData: pixels)
                    self.updateHasPixels = true
                    self.readRectangles(count: remaining)
                }
            }
        }
    }

    private func readExact(_ count: Int, trackPixelPayload: Bool = false, completion: @escaping @Sendable (Data?) -> Void) {
        guard let codec = appleRecordCodec else {
            // A header receive can prefetch the first pixel bytes. Count that
            // progress once when parsing enters the pixel body, before waiting
            // for its remainder; raw receive recursion must not renew old bytes.
            if trackPixelPayload, !hasReceivedPixelUpdate, !readBuffer.isEmpty {
                firstFrameDeadline?.recordPayloadProgress(now: ProcessInfo.processInfo.systemUptime)
            }
            readRawExact(count, trackPixelPayload: trackPixelPayload, completion: completion)
            return
        }
        if decryptedReadBuffer.count >= count {
            let result = Data(decryptedReadBuffer.prefix(count))
            decryptedReadBuffer.removeFirst(count)
            completion(result)
            return
        }
        readRawExact(2) { [weak self] header in
            guard let self, let header else { completion(nil); return }
            let length = Int(header[0]) << 8 | Int(header[1])
            guard length >= 32, length <= 65_520, length % 16 == 0 else {
                self.handleFailure("Invalid native encrypted record length"); completion(nil); return
            }
            self.readRawExact(length) { payload in
                guard let payload else { completion(nil); return }
                self.inputLock.lock()
                do {
                    let body = try codec.open(header + payload)
                    self.inputLock.unlock()
                    self.onNativeRecordReceived?(body.first.map(Int.init), body.count)
                    guard self.appleRecordCodec === codec, self.connection != nil else {
                        completion(nil); return
                    }
                    self.decryptedReadBuffer.append(body)
                    if trackPixelPayload, !self.hasReceivedPixelUpdate, count > 100_000, !body.isEmpty {
                        self.firstFrameDeadline?.recordPayloadProgress(now: ProcessInfo.processInfo.systemUptime)
                        let received = min(self.decryptedReadBuffer.count, count)
                        if received <= body.count || received == count || received % 1_048_576 < body.count {
                            self.onDownloadProgress?(Double(received) / 1_048_576, Double(count) / 1_048_576)
                        }
                        guard self.appleRecordCodec === codec else { completion(nil); return }
                    }
                    self.readExact(count, trackPixelPayload: trackPixelPayload, completion: completion)
                } catch {
                    self.inputLock.unlock()
                    self.handleFailure("Native encrypted record verification failed")
                    completion(nil)
                }
            }
        }
    }

    private func readRawExact(_ count: Int, trackPixelPayload: Bool = false, completion: @escaping @Sendable (Data?) -> Void) {
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

            guard self.connection === conn else { completion(nil); return }
            if trackPixelPayload, !self.hasReceivedPixelUpdate, receivedBytes > 0 {
                self.firstFrameDeadline?.recordPayloadProgress(now: ProcessInfo.processInfo.systemUptime)
            }

            if trackPixelPayload && !self.hasCompletedFramebufferUpdate && count > 100000 && self.readBuffer.count % 2097152 < receivedBytes {
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
                self.readRawExact(count, trackPixelPayload: trackPixelPayload, completion: completion)
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

    static func transportFailureMessage(_ error: NWError, state: State) -> String {
        if case .posix(let code) = error {
            switch code {
            case .ECONNREFUSED:
                return "The remote port refused the connection. Enable Screen Sharing and check the port and firewall."
            case .ENETUNREACH, .EHOSTUNREACH, .ENETDOWN:
                return "The remote network is unreachable. Check your LAN or Tailscale connection and the device address."
            case .ETIMEDOUT:
                return timeoutMessage(for: state)
            default: break
            }
        }
        return "Connection failed: \(error.localizedDescription)"
    }

    static func timeoutMessage(for state: State) -> String {
        switch state {
        case .connecting:
            return "Network connection timed out. Check the address, LAN or Tailscale connection, and Local Network permission."
        case .negotiatingVersion:
            return "The server did not respond with a remote desktop protocol. Check Screen Sharing and the port."
        case .authenticating:
            return "Authentication timed out. Complete the account or password prompt and check the Mac's sharing permissions."
        case .initializing:
            return "The server did not initialize the desktop. Check Screen Sharing on the remote Mac and retry."
        default:
            return "Connected, but no desktop image arrived. Check the remote Mac's Screen Sharing session and retry."
        }
    }

    private func handleFailure(_ message: String) {
        inputLock.lock()
        appleFileCopyReceiver?.cancel()
        appleFileCopyReceiver = nil
        appleFileCopySender?.cancel()
        appleFileCopySender = nil
        frameDecoders.cancel()
        appleClipboardSendPending = nil
        appleClipboardSendGeneration = UUID()
        appleRecordCodec?.close()
        appleRecordCodec = nil
        appleWrapKey = nil
        decryptedReadBuffer.removeAll()
        firstFrameDeadline = nil
        inputLock.unlock()
        AppLogger.shared.error("Session failed: \(message)", category: "RFB")
        stopTransportReports()
        let previous = connection
        connection = nil
        appleClipboardReadID = nil
        previous?.cancel()
        // A failure observer may reconnect synchronously. Teardown must finish
        // before publishing, so it cannot cancel the replacement connection.
        state = .failed(message)
    }
}

/// Each context is captured by its own pending rectangles. Dictionary mutation
/// is confined to RFBClient's serial decode worker; contexts are never reset
/// from the transport/UI queues while decoding is in progress.
private final class RFBFrameDecoders: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    let colorDepth: RFBColorDepth
    let zrle: ZRLEDecoder
    let zlib = ZlibDecompressor()
    let tight = TightRectangleDecoder()
    let appleCursor = AppleCursorCache()
    init(colorDepth: RFBColorDepth = .fullColor) {
        self.colorDepth = colorDepth
        zrle = ZRLEDecoder(colorDepth: colorDepth)
    }
}
