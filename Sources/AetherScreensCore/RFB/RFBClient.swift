import Foundation
import CoreGraphics
import Network
import AetherScreensSSH
import zlib

/// High-level client managing an RFB 3.8 remote desktop session over TCP (Network.framework).
public final class RFBClient: @unchecked Sendable {

    public enum KeyInputSource: Hashable, Sendable {
        case app
        case hardwareKeyboard
        case toolbarRepeat
    }

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
            if let inputDiagnostics {
                let stage: InputDiagnostics.Stage? = switch state {
                case .connecting: .connectionStarted
                case .connected: .connectionReady
                case .failed: .connectionFailed
                case .disconnected: .connectionClosed
                default: nil
                }
                if let stage {
                    inputLock.lock()
                    inputDiagnostics.record(stage, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags)
                    inputLock.unlock()
                }
            }
            onStateChanged?(state)
        }
    }

    // Callbacks
    public var onStateChanged: (@Sendable (State) -> Void)?
    public var onFrameUpdated: (@Sendable () -> Void)?
    public var onDisplayLayoutReceived: (@Sendable (RFBDisplayLayout?) -> Void)?
    public var onAppleDisplayLayoutReceived: (@Sendable (RFBAppleDisplayLayout) -> Void)?
    public var onAppleDisplaySelectionFinished: (@Sendable (UInt32?, Bool) -> Void)?
    public var onAppleServerScalingFinished: (@Sendable (Double, Bool) -> Void)?
    public var onAppleCurtainStateChanged: (@Sendable (RFBCurtainStatus) -> Void)?
    var curtainRecoveryProvider: (@Sendable (String?) -> Bool)?
    /// Locality of the established transport, including the owned SSH socket.
    var isLocalConnection: Bool? {
        inputLock.lock()
        let active = connection != nil
        let path = connection?.currentPath
        let tunneled = usesSSHTransport
        let endpoints = sshTransportEndpoints
        inputLock.unlock()
        guard active else { return nil }
        if tunneled { return LocalConnectionRoute.isLocal(endpoints) }
        return LocalConnectionRoute.isLocal(path)
    }
    public var onClipboardReceived: (@Sendable (String) -> Void)?
    /// Apple archive flavors, including binary image/URL data and aliases.
    public var onClipboardFlavorsReceived: (@Sendable ([RFBClipboardFlavor]) -> Void)?
    public var onRequestPassword: (@Sendable (@escaping @Sendable (String?) -> Void) -> Void)?
    public var onRequestMacAccount: (@Sendable (@escaping @Sendable (String?, String?) -> Void) -> Void)?
    public var onBytesReceived: (@Sendable (Int) -> Void)?
    /// TCP transport round-trip estimate; excludes server processing and display.
    public var onTransportRTT: (@Sendable (Double) -> Void)?
    public var onDownloadProgress: (@Sendable (Double, Double) -> Void)?

    private var storedConnection: NWConnection?
    private var connection: NWConnection? {
        get {
            inputLock.lock()
            defer { inputLock.unlock() }
            return storedConnection
        }
        set {
            inputLock.lock()
            storedConnection = newValue
            inputLock.unlock()
        }
    }
    private var usesSSHTransport = false
    private var sshTransportEndpoints: SSHTransportEndpoints?
    private var sshRoundTripTimeProvider: (@Sendable () async -> Double?)?
    // Accessed only on the connection queue, including teardown.
    private weak var reportConnection: NWConnection?
    private var pendingTransferReport: NWConnection.PendingDataTransferReport?
    private var lastTransferReportTime: TimeInterval = 0
    private var pendingSSHTransportReport: Task<Void, Never>?
    private let transportReportInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.aethernative.aetherscreens.rfbclient", qos: .userInteractive)
    private var readBuffer = Data()
    private var hasCompletedFramebufferUpdate = false
    private var updateHasDisplayLayout = false
    private var updateHasPixels = false
    private var appleLayoutNeedsRepaint = false
    private let zlibDecompressor = ZlibDecompressor()
    private let zrleDecoder = ZRLEDecoder()
    private let inputLock = NSRecursiveLock()
    let inputDiagnosticIdentifier = UUID()
    private let inputDiagnostics: InputDiagnostics?
    private var lastDiagnosticPointerSample: TimeInterval = -.infinity
    private var inputEnabled = true
    private var pointerInputEnabled = true
    private var inputGeneration = UUID()
    private var heldKeys = Set<UInt32>()
    private var keyOwners: [UInt32: Set<KeyInputSource>] = [:]
    private var pointerPosition: (UInt16, UInt16) = (0, 0)
    private var heldPointerButtons: RFBConstants.ButtonMask = []
    private var nextWheelDeadline = DispatchTime.now()
    private var wheelScheduleGeneration: UUID?
    private var extendedClipboard = false
    private var pendingClipboard: String?
    private var appleUTF16Keysyms = false
    private var appleClipboardMonitoring = false
    private var automaticClipboardEnabled: Bool
    private let automaticFramebufferUpdates: Bool
    private var automaticFramebufferActive = false
    private var incrementalRefreshGeneration: UUID?
    private var appleDisplayLayout: RFBAppleDisplayLayout?
    private var appleCurtain = RFBAppleCurtain()
    private var appleCurtainConnectionID = UUID()
    private let appleCurtainEventSource = RFBCurtainEventSource()
    private var appleCurtainEventRevision: UInt64 = 0
    private var appleCurtainCloseCompletion: FinalInputCompletion?
    private var appleDisplaySelectionGeneration: UUID?
    private var requestedAppleDisplayID: UInt32?
    private var appleServerScalingGeneration: UUID?
    private var requestedAppleServerScale: Double = 1
    private var appleDisplayAwaitingPixels = false
    private var appleDisplayHasFreshPixels = false
    private var finalDisconnectToken: UUID?
    private let connectionTimeoutInterval: TimeInterval
    private let appleDisplaySelectionTimeoutInterval: TimeInterval
    private var connectionTimeoutGeneration: UUID?
    private var authenticationPromptGeneration: UUID?

    public convenience init(
        host: String,
        port: UInt16 = RFBConstants.defaultPort,
        password: String? = nil,
        username: String? = nil,
        framebuffer: Framebuffer = Framebuffer(),
        automaticClipboard: Bool = true,
        automaticFramebufferUpdates: Bool = false
    ) {
        self.init(host: host, port: port, password: password, username: username,
                  framebuffer: framebuffer, automaticClipboard: automaticClipboard,
                  automaticFramebufferUpdates: automaticFramebufferUpdates,
                  connectionTimeoutInterval: 20, inputDiagnostics: .enabled)
    }

    init(host: String, port: UInt16 = RFBConstants.defaultPort,
         password: String? = nil, username: String? = nil,
         framebuffer: Framebuffer = Framebuffer(), automaticClipboard: Bool = true,
         automaticFramebufferUpdates: Bool = false, connectionTimeoutInterval: TimeInterval,
         inputDiagnostics: InputDiagnostics? = nil, appleDisplaySelectionTimeoutInterval: TimeInterval = 10,
         transportReportInterval: TimeInterval = 1) {
        precondition(connectionTimeoutInterval.isFinite && connectionTimeoutInterval > 0)
        precondition(appleDisplaySelectionTimeoutInterval.isFinite && appleDisplaySelectionTimeoutInterval > 0)
        precondition(transportReportInterval.isFinite && transportReportInterval > 0)
        self.host = host
        self.port = port
        self.password = password
        self.username = username
        self.framebuffer = framebuffer
        self.automaticClipboardEnabled = automaticClipboard
        self.automaticFramebufferUpdates = automaticFramebufferUpdates
        self.connectionTimeoutInterval = connectionTimeoutInterval
        self.appleDisplaySelectionTimeoutInterval = appleDisplaySelectionTimeoutInterval
        self.transportReportInterval = transportReportInterval
        self.inputDiagnostics = inputDiagnostics
        inputDiagnostics?.record(.clientCreated, session: inputDiagnosticIdentifier)
    }

    /// Initiate connection to the remote Mac.
    public func connect() {
        connect(transportHost: host, transportPort: port)
    }

    /// Connects through a caller-owned, authenticated SSH loopback tunnel while
    /// preserving the remote host/account identity used by RFB and diagnostics.
    /// The tunnel owner must stop it when ending or replacing the session.
    public func connect(using tunnel: SSHLoopbackTunnel) {
        guard let localPort = UInt16(exactly: tunnel.port), localPort > 0 else { return }
        connect(transportHost: "127.0.0.1", transportPort: localPort,
                usesSSHTransport: true, sshTransportEndpoints: tunnel.transportEndpoints,
                sshRoundTripTimeProvider: { [weak tunnel] in await tunnel?.transportRoundTripTime() })
    }

    func connect(transportHost: String, transportPort: UInt16,
                         usesSSHTransport: Bool = false,
                         sshTransportEndpoints: SSHTransportEndpoints? = nil,
                         sshRoundTripTimeProvider: (@Sendable () async -> Double?)? = nil) {
        switch state {
        case .disconnected, .failed:
            break
        default:
            return
        }

        hasCompletedFramebufferUpdate = false
        extendedClipboard = false
        pendingClipboard = nil
        inputLock.lock()
        readBuffer.removeAll()
        self.usesSSHTransport = usesSSHTransport
        self.sshTransportEndpoints = sshTransportEndpoints
        self.sshRoundTripTimeProvider = sshRoundTripTimeProvider
        finalDisconnectToken = nil
        heldKeys.removeAll()
        keyOwners.removeAll()
        heldPointerButtons = []
        inputGeneration = UUID()
        appleUTF16Keysyms = false
        appleClipboardMonitoring = false
        automaticFramebufferActive = false
        incrementalRefreshGeneration = nil
        appleDisplayLayout = nil
        appleCurtainConnectionID = UUID()
        appleCurtain.beginConnection(appleCurtainConnectionID)
        appleDisplaySelectionGeneration = nil
        appleServerScalingGeneration = nil
        appleDisplayAwaitingPixels = false
        appleDisplayHasFreshPixels = false
        appleLayoutNeedsRepaint = false
        inputLock.unlock()
        state = .connecting
        // An observer can cancel or replace the attempt synchronously.
        guard state == .connecting, connection == nil else { return }
        AppLogger.shared.info("Initiating connection to \(host):\(port)...", category: "Network")

        let nwHost = NWEndpoint.Host(transportHost)
        let nwPort = NWEndpoint.Port(rawValue: transportPort)!

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true // Disable Nagle's algorithm for interactive responsiveness
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        inputLock.lock()
        guard state == .connecting, connection == nil else { inputLock.unlock(); return }
        self.connection = conn
        inputLock.unlock()

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
                self.pendingSSHTransportReport?.cancel()
                self.pendingSSHTransportReport = nil
                self.pendingTransferReport = self.usesSSHTransport ? nil : conn.startDataTransferReport()
                self.lastTransferReportTime = ProcessInfo.processInfo.systemUptime
                self.startHandshake()
            case .waiting(let error):
                AppLogger.shared.info("Waiting for network: \(error.localizedDescription)", category: "Network")
            case .failed(let error):
                AppLogger.shared.error("TCP connection failed: \(error.localizedDescription)", category: "Network")
                self.handleFailure("Connection failed: \(error.localizedDescription)", from: conn)
            case .cancelled:
                AppLogger.shared.info("TCP socket cancelled", category: "Network")
                self.state = .disconnected
            default:
                break
            }
        }

        queue.async { [weak self, weak conn] in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            self.authenticationPromptGeneration = nil
            self.armConnectionTimeout(for: conn)
        }
        conn.start(queue: queue)
    }

    /// Called on the connection queue. Every resumed handshake owns a new budget,
    /// so a timer scheduled before a prompt cannot expire the submitted attempt.
    private func armConnectionTimeout(for conn: NWConnection) {
        guard connection === conn else { return }
        let generation = UUID()
        connectionTimeoutGeneration = generation
        queue.asyncAfter(deadline: .now() + connectionTimeoutInterval) { [weak self, weak conn] in
            guard let self, let conn, self.connection === conn,
                  self.connectionTimeoutGeneration == generation else { return }
            switch self.state {
            case .connecting, .negotiatingVersion, .authenticating, .initializing: break
            default: return
            }
            #if os(macOS)
            let settings = "System Settings"
            #else
            let settings = "Settings"
            #endif
            self.handleFailure("Connection timed out. Check the address, Screen Sharing and your LAN or Tailscale connection. Allow AetherScreens in \(settings) > Privacy & Security > Local Network.", from: conn)
        }
    }

    private func beginAuthenticationPrompt() -> UUID {
        connectionTimeoutGeneration = nil
        let generation = UUID()
        authenticationPromptGeneration = generation
        return generation
    }

    /// Disconnect current session.
    public func disconnect() {
        inputLock.lock()
        let previous = connection
        let alreadyDraining = finalDisconnectToken != nil
        let drainsInput = state == .connected && !alreadyDraining && previous != nil
        var packet = drainsInput ? heldInputReleasePacket() : Data()
        if drainsInput, appleCurtainCloseCompletion == nil, appleCurtain.restorationForClose() != nil {
            packet.append(RFBEncoder.encodeAppleCurtain(hidden: false))
        }
        detachCurrentConnection()
        inputLock.unlock()
        if drainsInput, let previous {
            // Detach synchronously for immediate reconnect, but drain only the old
            // socket. Its completion must never tear down a replacement session.
            let finished = FinalInputCompletion { _ in previous.cancel() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { finished.finish(false) }
            previous.send(content: packet.isEmpty ? nil : packet, contentContext: .finalMessage, isComplete: true,
                          completion: .contentProcessed { finished.finish($0 == nil) })
        } else if !alreadyDraining {
            previous?.cancel()
        }
        AppLogger.shared.info("Disconnecting session with \(host)", category: "Network")
        state = .disconnected
    }

    /// Called under inputLock before publishing any terminal state or callback.
    private func detachCurrentConnection() {
        stopTransportReports()
        finalDisconnectToken = nil
        automaticFramebufferActive = false
        incrementalRefreshGeneration = nil
        appleDisplayLayout = nil
        appleDisplaySelectionGeneration = nil
        appleServerScalingGeneration = nil
        appleDisplayAwaitingPixels = false
        appleDisplayHasFreshPixels = false
        appleLayoutNeedsRepaint = false
        heldKeys.removeAll()
        keyOwners.removeAll()
        heldPointerButtons = []
        pendingClipboard = nil
        inputGeneration = UUID()
        connection = nil
        readBuffer.removeAll()
        appleCurtain.disconnected(connection: appleCurtainConnectionID)
        publishAppleCurtainStatus()
        let curtainCompletion = appleCurtainCloseCompletion
        appleCurtainCloseCompletion = nil
        curtainCompletion?.finish(false)
    }

    private func heldInputReleasePacket() -> Data {
        var packet = Data()
        for key in heldKeys.sorted() { packet.append(RFBEncoder.encodeKeyEvent(down: false, keySym: key)) }
        if !heldPointerButtons.isEmpty {
            packet.append(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
        }
        return packet
    }

    /// Queue a final, balanced input transaction and TCP write-close. A successful
    /// completion means Network processed the bytes, not that macOS acted on them.
    public func disconnect(after action: RemoteDisconnectAction, display: CGRect? = nil,
                           completion: @escaping @Sendable (Bool) -> Void) {
        disconnect(after: action, display: display, allowDisabledInput: false, completion: completion)
    }

    /// A session owner may authorize its configured action when explicitly
    /// closing a retained control session. Ordinary disabled input stays gated.
    func disconnect(after action: RemoteDisconnectAction, display: CGRect?, allowDisabledInput: Bool,
                    completion: @escaping @Sendable (Bool) -> Void) {
        inputLock.lock()
        guard appleCurtainCloseCompletion == nil else { inputLock.unlock(); completion(false); return }
        if state == .connected, finalDisconnectToken == nil, let connection,
           let request = appleCurtain.restorationForClose() {
            let releases = heldInputReleasePacket()
            if !releases.isEmpty { sendData(releases) }
            heldKeys.removeAll()
            keyOwners.removeAll()
            heldPointerButtons = []
            pendingClipboard = nil
            inputGeneration = UUID()
            let finished = FinalInputCompletion { [self, connection] _ in
                self.inputLock.lock()
                let current = self.connection === connection
                if current { self.appleCurtainCloseCompletion = nil }
                self.inputLock.unlock()
                guard current else { completion(false); return }
                self.disconnectFinal(after: action, display: display, allowDisabledInput: allowDisabledInput,
                                     completion: completion)
            }
            // Keep reads alive briefly for a new on-console report. The bounded
            // close budget also applies on iOS background expiration. Processing
            // bytes alone never confirms that the physical screen was restored.
            appleCurtainCloseCompletion = finished
            publishAppleCurtainStatus()
            sendAppleCurtain(request, on: connection, timeout: 2)
            // Window/session owners may disappear immediately after close. Keep
            // this transaction alive independently of them and the read queue;
            // settling clears the stored completion before final input drain.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self, connection, finished] in
                inputLock.lock(); defer { inputLock.unlock() }
                guard self.connection === connection, appleCurtainCloseCompletion === finished else {
                    finished.finish(false)
                    return
                }
                appleCurtain.expire(request)
                publishAppleCurtainStatus()
                finishAppleCurtainCloseIfSettled()
            }
            inputLock.unlock()
            return
        }
        inputLock.unlock()
        disconnectFinal(after: action, display: display, allowDisabledInput: allowDisabledInput,
                        completion: completion)
    }

    private func disconnectFinal(after action: RemoteDisconnectAction, display: CGRect?, allowDisabledInput: Bool,
                                 completion: @escaping @Sendable (Bool) -> Void) {
        inputLock.lock()
        guard finalDisconnectToken == nil else { inputLock.unlock(); completion(false); return }
        guard state == .connected, action == .disconnectOnly || inputEnabled || allowDisabledInput, let connection else {
            inputLock.unlock(); disconnect(); completion(false); return
        }
        let actionData = action.inputPacket(width: framebuffer.width, height: framebuffer.height, display: display)
        guard action == .disconnectOnly || !actionData.isEmpty else { inputLock.unlock(); disconnect(); completion(false); return }
        var packet = heldInputReleasePacket()
        packet.append(actionData)
        heldKeys.removeAll()
        keyOwners.removeAll()
        heldPointerButtons = []
        pendingClipboard = nil
        inputGeneration = UUID()
        let token = UUID()
        finalDisconnectToken = token
        incrementalRefreshGeneration = nil
        appleDisplaySelectionGeneration = nil
        appleServerScalingGeneration = nil
        let finished = FinalInputCompletion { [self, connection] processed in
            inputLock.lock()
            let current = self.connection === connection && finalDisconnectToken == token
            if current { detachCurrentConnection() }
            inputLock.unlock()
            connection.cancel()
            if current { state = .disconnected }
            completion(processed && current)
        }
        // Always settle, including cancellation/error and a superseded connection.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { finished.finish(false) }
        connection.send(content: packet.isEmpty ? nil : packet, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { finished.finish($0 == nil) })
        inputLock.unlock()
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
            self.inputLock.lock()
            self.appleUTF16Keysyms = data == Data("RFB 003.889\n".utf8)
            self.inputLock.unlock()

            // Reply with RFB 003.008
            let versionReply = Data(RFBConstants.protocolVersion38.utf8)
            AppLogger.shared.info("Sending client version: RFB 003.008", category: "RFB")
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
                        guard let msgData else { return }
                        let reason = String(data: msgData, encoding: .utf8) ?? "Unknown server error"
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
            let prompt = beginAuthenticationPrompt()
            request { [weak self] account, password in
                guard let self else { return }
                self.queue.async {
                    guard let pendingConnection, self.connection === pendingConnection,
                          self.state == .authenticating, self.authenticationPromptGeneration == prompt else { return }
                    self.authenticationPromptGeneration = nil
                    guard let account = account?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !account.isEmpty, let password, !password.isEmpty else {
                        self.handleFailure("Mac account username and password required")
                        return
                    }
                    self.username = account
                    self.password = password
                    self.armConnectionTimeout(for: pendingConnection)
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
            let prompt = beginAuthenticationPrompt()
            request { [weak self] entered in
                guard let self else { return }
                self.queue.async {
                    guard let pendingConnection, self.connection === pendingConnection,
                          self.state == .authenticating, self.authenticationPromptGeneration == prompt else { return }
                    self.authenticationPromptGeneration = nil
                    guard let entered, !entered.isEmpty else {
                        self.handleFailure("Mac account password required")
                        return
                    }
                    self.password = entered
                    self.armConnectionTimeout(for: pendingConnection)
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
            let prompt = beginAuthenticationPrompt()
            AppLogger.shared.info("No saved password. Requesting user input via modal sheet...", category: "Auth")
            onRequest { [weak self] enteredPwd in
                guard let self = self else { return }
                self.queue.async {
                    guard let pendingConnection, self.connection === pendingConnection,
                          self.state == .authenticating, self.authenticationPromptGeneration == prompt else { return }
                    self.authenticationPromptGeneration = nil
                    guard let pwd = enteredPwd, !pwd.isEmpty else {
                        AppLogger.shared.warning("User cancelled password prompt", category: "Auth")
                        self.handleFailure("VNC Password required to connect")
                        return
                    }
                    self.password = pwd
                    self.armConnectionTimeout(for: pendingConnection)
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
                    guard let lenData else { return }
                    let len = Int(lenData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                    self.readExact(len) { errData in
                        guard let errData else { return }
                        let errStr = String(data: errData, encoding: .utf8) ?? "Authentication failed (incorrect password)"
                        AppLogger.shared.error("Auth rejection detail: \(errStr)", category: "Auth")
                        self.handleFailure(errStr)
                    }
                }
            }
        }
    }

    private func sendClientInit() {
        guard transitionCurrentConnection(to: .initializing) else { return }
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
        // A connected observer may immediately reconnect on another thread.
        // Keep initialization and its first reader in the same input/lifecycle
        // transaction so an old initializer cannot read the new socket's banner.
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .initializing, connection != nil, finalDisconnectToken == nil else { return }
        if appleUTF16Keysyms { sendData(ApplePasteboard.viewerInfo()) }
        AppLogger.shared.info("Configuring session: 32-bit BGRA pixel format...", category: "RFB")
        // Request 32-bit standard BGRA format for high-speed iOS / Metal rendering
        let pixelFormatData = RFBEncoder.encodeSetPixelFormat(.standardBGRA32)
        sendData(pixelFormatData)

        // Advertise only implemented formats, retaining Zlib/Raw fallbacks.
        AppLogger.shared.info("Setting encodings: ZRLE, Zlib, CopyRect, DesktopSize, Raw...", category: "RFB")
        let encodings = RFBEncoder.sessionEncodings(supportsAppleDisplayMetadata: appleUTF16Keysyms)
        let encodingsData = RFBEncoder.encodeSetEncodings(encodings)
        sendData(encodingsData)

        guard transitionCurrentConnection(to: .connected) else { return }
        if let curtainRecoveryProvider {
            appleCurtain.configureRecoveryForNewConnection(curtainRecoveryProvider(username))
        }
        appleCurtain.authenticated(connection: appleCurtainConnectionID, apple: appleUTF16Keysyms)
        publishAppleCurtainStatus()
        AppLogger.shared.info("Session state -> connected! Requesting initial full-frame update (0,0,\(framebuffer.width)x\(framebuffer.height))...", category: "RFB")

        // Send initial full screen update request
        requestUpdate(incremental: false)
        configureAutomaticFramebufferUpdates()

        // Start server message loop
        startMessageLoop()
        inputLock.lock()
        if automaticClipboardEnabled { requestApplePasteboard() }
        inputLock.unlock()
    }

    // MARK: - Server Message Loop

    private func startMessageLoop() {
        inputLock.lock()
        guard state == .connected, finalDisconnectToken == nil, let sourceConnection = connection else {
            inputLock.unlock()
            return
        }
        inputLock.unlock()
        readExact(1, from: sourceConnection) { [weak self] typeData in
            guard let self = self, let typeData = typeData,
                  self.connection === sourceConnection, self.state == .connected else { return }
            let msgType = typeData[0]

            switch msgType {
            case RFBConstants.ServerMessageType.framebufferUpdate.rawValue:
                self.handleFramebufferUpdate()
            case RFBConstants.ServerMessageType.serverCutText.rawValue:
                self.handleServerCutText()
            case RFBConstants.ServerMessageType.bell.rawValue:
                AppLogger.shared.info("Server sent bell (beep)", category: "RFB")
                self.startMessageLoop()
            case 0x1F where self.appleUTF16Keysyms:
                self.handleApplePasteboard()
            case 0x14 where self.appleUTF16Keysyms:
                self.handleAppleStatus()
            default:
                // An unknown payload has no safe boundary for the next message.
                self.handleFailure("Unsupported server message type: \(msgType)")
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
            guard let sourceConnection = connection else { return }
            if updateHasPixels {
                inputLock.lock()
                appleDisplayHasFreshPixels = true
                let finished = appleDisplaySelectionGeneration != nil && appleDisplayLayout?.selectedDisplayID == requestedAppleDisplayID
                let completedDisplayID = requestedAppleDisplayID
                let scalingFinished = appleServerScalingGeneration != nil &&
                    appleDisplayLayout?.screens.allSatisfy({ abs($0.serverScale - requestedAppleServerScale) < 0.00001 }) == true
                let completedScale = requestedAppleServerScale
                if finished { appleDisplaySelectionGeneration = nil }
                if scalingFinished { appleServerScalingGeneration = nil }
                appleDisplayAwaitingPixels = appleDisplaySelectionGeneration != nil || appleServerScalingGeneration != nil
                if finished { inputDiagnostics?.record(.appleDisplaySelectionConfirmed, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags) }
                inputLock.unlock()
                if finished { onAppleDisplaySelectionFinished?(completedDisplayID, true) }
                guard connection === sourceConnection else { return }
                if scalingFinished { onAppleServerScalingFinished?(completedScale, true) }
                guard connection === sourceConnection else { return }
            }
            // Loading progress is only useful until the first desktop is visible.
            // A display-layout acknowledgement alone is not the first visible desktop.
            if !updateHasDisplayLayout || updateHasPixels {
                hasCompletedFramebufferUpdate = true
                onFrameUpdated?()
            }
            // A notification can synchronously reconnect. Its old frame cannot
            // start a second reader or schedule an update on the replacement.
            guard connection === sourceConnection else { return }
            if appleLayoutNeedsRepaint {
                // Complete the layout's message first. A later incremental
                // request can replace a pending full repaint on Apple's server.
                appleLayoutNeedsRepaint = false
                if usesAutomaticFramebufferUpdates { configureAutomaticFramebufferUpdates() }
                requestUpdate(incremental: false)
            } else if usesAutomaticFramebufferUpdates {
                scheduleIncrementalRefresh(for: sourceConnection)
            } else {
                requestUpdate(incremental: true)
            }
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
            case .appleDisplayInfo where self.appleUTF16Keysyms:
                self.readExact(10) { prefix in
                    guard let prefix else { return }
                    let displayCount = Int(prefix[8]) << 8 | Int(prefix[9])
                    guard displayCount <= 25 else { self.handleFailure("Invalid Apple display info count"); return }
                    self.readExact(displayCount * 28) { body in
                        guard body != nil else { return }
                        self.readRectangles(count: count - 1)
                    }
                }
            case .appleDisplayLayout where self.appleUTF16Keysyms:
                self.readAppleDisplayLayout(remainingRectangles: count - 1)
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
                guard let sourceConnection = self.connection else { return }
                let width = Int(header.width), height = Int(header.height)
                guard width > 0, height > 0,
                      Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height,
                      width <= ZRLEDecoder.maximumPixelBytes / 4 / height else {
                    self.handleFailure("Invalid Zlib rectangle size")
                    return
                }
                let expectedBytes = width * height * 4
                self.readExact(4) { [weak self] lengthData in
                    guard let self, let lengthData, self.connection === sourceConnection else { return }
                    let length = Int(lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
                    guard length > 0, length <= expectedBytes * 2 + 1024 else {
                        self.handleFailure("Invalid Zlib compressed length")
                        return
                    }
                    self.readExact(length) { [weak self] compressed in
                        guard let self, let compressed, self.connection === sourceConnection else { return }
                        let decoded = self.zlibDecompressor.decompress(data: compressed, expectedBytes: expectedBytes)
                        guard self.connection === sourceConnection else { return }
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

            case .raw:
                let width = Int(header.width), height = Int(header.height)
                guard Int(header.x) + width <= self.framebuffer.width,
                      Int(header.y) + height <= self.framebuffer.height else {
                    self.handleFailure("Invalid Raw rectangle size")
                    return
                }
                let pixelBytes = width * height * 4
                self.readExact(pixelBytes) { pixelData in
                    guard let pixelData = pixelData else { return }
                    self.updateHasPixels = pixelBytes > 0 || self.updateHasPixels
                    self.framebuffer.updateRect(
                        x: Int(header.x),
                        y: Int(header.y),
                        width: width,
                        height: height,
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
                guard let sourceConnection = self.connection else { return }
                // Screen resolution changed on remote Mac!
                AppLogger.shared.info("Remote desktop resized to \(header.width)x\(header.height)", category: "RFB")
                self.framebuffer.resize(newWidth: Int(header.width), newHeight: Int(header.height))
                self.onDisplayLayoutReceived?(nil)
                guard self.connection === sourceConnection else { return }
                self.refreshAutomaticFramebufferRegion()
                self.readRectangles(count: count - 1)

            case .extendedDesktopSize:
                guard let sourceConnection = self.connection else { return }
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
                        // The layout observer may close or replace the session.
                        guard self.connection === sourceConnection else { return }
                        self.refreshAutomaticFramebufferRegion()
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
                    self.readExact(totalCursorBytes) { cursorData in
                        guard cursorData != nil else { return }
                        self.readRectangles(count: count - 1)
                    }
                } else {
                    self.readRectangles(count: count - 1)
                }

            case .lastRect:
                self.readRectangles(count: 0)
                return

            default:
                // Its unknown payload cannot be skipped as another rectangle.
                self.handleFailure("Unsupported framebuffer encoding: \(header.encoding.rawValue)")
            }
        }
    }

    private func readAppleDisplayLayout(remainingRectangles: Int) {
        guard let sourceConnection = connection else { return }
        readExact(2) { [weak self] prefix in
            guard let self, let prefix, self.connection === sourceConnection else { return }
            let length = Int(prefix[0]) << 8 | Int(prefix[1])
            guard (20...4096).contains(length) else { self.handleFailure("Invalid Apple display layout length"); return }
            self.readExact(length) { body in
                guard let body, self.connection === sourceConnection else { return }
                guard let layout = RFBAppleDisplayLayout.parse(body) else {
                    self.handleFailure("Invalid Apple display layout"); return
                }
                self.inputLock.lock()
                guard self.connection === sourceConnection else { self.inputLock.unlock(); return }
                let geometryChanged = (self.appleDisplayLayout.map { !$0.hasSameFramebufferLayout(as: layout) } ?? true) ||
                    self.framebuffer.width != Int(layout.width) || self.framebuffer.height != Int(layout.height)
                if geometryChanged {
                    if !self.heldPointerButtons.isEmpty {
                        self.sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: self.pointerPosition.0, y: self.pointerPosition.1))
                    }
                    self.heldPointerButtons = []
                    self.inputGeneration = UUID()
                    self.appleDisplayAwaitingPixels = true
                    self.appleDisplayHasFreshPixels = false
                    // Earlier rectangles in this update belonged to the old
                    // geometry. Only pixels after the layout can be presented.
                    self.updateHasPixels = false
                    // Even equal-size screens must not retain the other screen's pixels.
                    self.framebuffer.resize(newWidth: Int(layout.width), newHeight: Int(layout.height))
                }
                self.appleDisplayLayout = layout
                self.appleCurtain.metadata(connection: self.appleCurtainConnectionID, sessionFlags: layout.sessionFlags)
                self.publishAppleCurtainStatus()
                self.finishAppleCurtainCloseIfSettled()
                self.inputDiagnostics?.record(.appleDisplayLayoutReceived, session: self.inputDiagnosticIdentifier, flags: self.diagnosticInputFlags)
                self.updateHasDisplayLayout = true
                self.appleLayoutNeedsRepaint = true
                self.incrementalRefreshGeneration = nil
                self.inputLock.unlock()
                self.onAppleDisplayLayoutReceived?(layout)
                guard self.connection === sourceConnection else { return }
                self.readRectangles(count: remainingRectangles)
            }
        }
    }

    public var currentAppleDisplayLayout: RFBAppleDisplayLayout? {
        inputLock.lock(); defer { inputLock.unlock() }
        return state == .connected ? appleDisplayLayout : nil
    }

    public var curtainStatus: RFBCurtainStatus {
        inputLock.lock(); defer { inputLock.unlock() }
        return appleCurtain.status
    }

    var curtainEvent: RFBCurtainEvent {
        inputLock.lock(); defer { inputLock.unlock() }
        return .init(source: appleCurtainEventSource, revision: appleCurtainEventRevision,
                     account: username, transportAttached: connection != nil, status: appleCurtain.status,
                     pendingRequestID: appleCurtain.pending?.id, pendingHidden: appleCurtain.pending?.hidden,
                     confirmedRestorationID: appleCurtain.confirmedRestorationID)
    }

    /// All callers hold inputLock. Record the event before publishing its callback
    /// so a process-local ledger can synchronously bind requests before send.
    private func publishAppleCurtainStatus() {
        appleCurtainEventRevision &+= 1
        onAppleCurtainStateChanged?(appleCurtain.status)
    }

    /// Normal authenticated Apple visibility protocol; no lock shortcut, helper,
    /// account change or private note. Capability comes only from this socket's
    /// accepted DisplayInfo2 metadata, including login-window exclusion.
    @discardableResult
    public func setAppleCurtain(hidden: Bool) -> Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        guard state == .connected, finalDisconnectToken == nil,
              appleCurtainCloseCompletion == nil, !hidden || inputEnabled,
              let connection else { return false }
        if curtainRecoveryProvider?(username) == true { appleCurtain.inheritRecoveryWarning() }
        guard let request = appleCurtain.request(hidden: hidden) else { return false }
        publishAppleCurtainStatus()
        sendAppleCurtain(request, on: connection, timeout: 20)
        return true
    }

    /// Called under inputLock; retain the original socket and request identity
    /// in both completions. A reconnect must never receive old Curtain bytes.
    private func sendAppleCurtain(_ request: RFBAppleCurtain.Request, on source: NWConnection,
                                  timeout: TimeInterval) {
        guard connection === source, appleCurtain.pending == request else { return }
        source.send(content: RFBEncoder.encodeAppleCurtain(hidden: request.hidden),
                    completion: .contentProcessed { [weak self, weak source] error in
            guard let self, let source else { return }
            self.inputLock.lock(); defer { self.inputLock.unlock() }
            guard self.connection === source, self.appleCurtainConnectionID == request.connectionID else { return }
            if error != nil {
                // A close restore may have superseded this hide. Only a failure
                // accepted for the current request may end its transaction.
                guard self.appleCurtain.writeFailed(request) else { return }
                self.publishAppleCurtainStatus()
                self.finishAppleCurtainCloseIfSettled()
                self.handleFailure("Curtain request delivery failed.", from: source)
            }
        })
        queue.asyncAfter(deadline: .now() + timeout) { [weak self, weak source] in
            guard let self, let source else { return }
            self.inputLock.lock(); defer { self.inputLock.unlock() }
            guard self.connection === source, self.appleCurtain.pending == request else { return }
            self.appleCurtain.expire(request)
            self.publishAppleCurtainStatus()
            self.finishAppleCurtainCloseIfSettled()
        }
    }

    private func finishAppleCurtainCloseIfSettled() {
        guard appleCurtain.pending == nil, let completion = appleCurtainCloseCompletion else { return }
        appleCurtainCloseCompletion = nil
        completion.finish(!appleCurtain.status.needsRestoration && appleCurtain.status.phase == .visible)
    }

    /// Report client limitations separately from the remote Mac's capabilities.
    /// A confirmed scale change must never be presented as progressive quality.
    public var imageQualityCapabilities: RemoteImageQualityCapabilities {
        inputLock.lock(); defer { inputLock.unlock() }
        let active = state == .connected && connection != nil && finalDisconnectToken == nil
        return RemoteImageQualityCapabilities(
            progressiveAdaptiveQuality: active ? .clientDecoderUnavailable : .notConnected,
            supportsServerScaling: active && appleUTF16Keysyms && appleDisplayLayout != nil)
    }

    /// Selection is confirmed by the server's next layout, then fresh pixels.
    /// Observe may change the viewed display. Pointer input waits for that frame.
    @discardableResult
    public func selectAppleDisplay(id: UInt32?) -> Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        guard state == .connected, finalDisconnectToken == nil, appleUTF16Keysyms, appleServerScalingGeneration == nil,
              let sourceConnection = connection, let layout = appleDisplayLayout,
              id == nil || layout.screens.contains(where: { $0.id == id }) else { return false }
        if id == layout.selectedDisplayID && appleDisplaySelectionGeneration == nil && !appleDisplayAwaitingPixels {
            // The UI can still be applying this acknowledged layout. Complete
            // its request even when the already visible view needs no wire switch.
            inputDiagnostics?.record(.appleDisplaySelectionConfirmed, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags)
            onAppleDisplaySelectionFinished?(id, true)
            return true
        }
        if !heldPointerButtons.isEmpty {
            sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
        }
        heldPointerButtons = []
        inputGeneration = UUID()
        let generation = UUID()
        requestedAppleDisplayID = id
        appleDisplaySelectionGeneration = generation
        appleDisplayAwaitingPixels = true
        inputDiagnostics?.record(.appleDisplaySelectionRequested, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags)
        sendData(RFBEncoder.encodeAppleSetDisplay(id))
        queue.asyncAfter(deadline: .now() + appleDisplaySelectionTimeoutInterval) { [weak self, weak sourceConnection] in
            guard let self, let sourceConnection else { return }
            self.inputLock.lock()
            guard self.connection === sourceConnection, self.state == .connected,
                  self.finalDisconnectToken == nil, self.appleDisplaySelectionGeneration == generation else {
                self.inputLock.unlock(); return
            }
            self.appleDisplaySelectionGeneration = nil
            // No answer retains the previous valid geometry. An answer without
            // pixels stays gated until a real frame arrives.
            self.appleDisplayAwaitingPixels = !self.appleDisplayHasFreshPixels
            self.inputDiagnostics?.record(.appleDisplaySelectionFailed, session: self.inputDiagnosticIdentifier, flags: self.diagnosticInputFlags)
            self.requestUpdate(incremental: false)
            self.inputLock.unlock()
            self.onAppleDisplaySelectionFinished?(id, false)
        }
        return true
    }

    /// Only the answering Apple layout and a subsequent frame confirm scaling.
    /// Display selection and scaling are serialized so input cannot use a mix
    /// of coordinates from two different geometry requests.
    @discardableResult
    public func setAppleServerScaling(_ factor: Double) -> Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        guard let packet = RFBEncoder.encodeAppleServerScaling(factor), state == .connected,
              finalDisconnectToken == nil, appleUTF16Keysyms,
              appleDisplaySelectionGeneration == nil, appleServerScalingGeneration == nil,
              !appleDisplayAwaitingPixels, let sourceConnection = connection,
              let layout = appleDisplayLayout else { return false }
        if layout.screens.allSatisfy({ abs($0.serverScale - factor) < 0.00001 }) {
            onAppleServerScalingFinished?(factor, true)
            return true
        }
        guard let currentScale = layout.screens.first?.serverScale,
              layout.screens.allSatisfy({ abs($0.serverScale - currentScale) < 0.00001 }),
              Double(layout.width) / currentScale * factor >= 1,
              Double(layout.height) / currentScale * factor >= 1 else { return false }
        if !heldPointerButtons.isEmpty {
            sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
        }
        heldPointerButtons = []
        inputGeneration = UUID()
        let generation = UUID()
        requestedAppleServerScale = factor
        appleServerScalingGeneration = generation
        appleDisplayAwaitingPixels = true
        sendData(packet)
        queue.asyncAfter(deadline: .now() + appleDisplaySelectionTimeoutInterval) { [weak self, weak sourceConnection] in
            guard let self, let sourceConnection else { return }
            self.inputLock.lock()
            guard self.connection === sourceConnection, self.state == .connected,
                  self.finalDisconnectToken == nil, self.appleServerScalingGeneration == generation else {
                self.inputLock.unlock(); return
            }
            self.appleServerScalingGeneration = nil
            self.appleDisplayAwaitingPixels = !self.appleDisplayHasFreshPixels
            self.requestUpdate(incremental: false)
            self.inputLock.unlock()
            self.onAppleServerScalingFinished?(factor, false)
        }
        return true
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

    private func handleApplePasteboard() {
        readExact(15) { [weak self] header in
            guard let self, let header else { return }
            let plainSize = Int(header[7..<11].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            let compressedSize = Int(header[11..<15].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            AppLogger.shared.debug("Apple pasteboard metadata: promise=\(header[1]), archive=\(plainSize), compressed=\(compressedSize)", category: "RFB")
            guard plainSize <= ApplePasteboard.maximumArchiveBytes,
                  compressedSize > 0, compressedSize <= ApplePasteboard.maximumArchiveBytes else {
                self.handleFailure("Remote Apple clipboard exceeds the supported size")
                return
            }
            self.readExact(compressedSize) { payload in
                guard let payload else { return }
                if header[1] == 0, let items = ApplePasteboard.decodeItems(payload, uncompressedBytes: plainSize) {
                    if let receive = self.onClipboardFlavorsReceived {
                        receive(items)
                    } else if let text = ApplePasteboard.text(in: items) {
                        self.onClipboardReceived?(text)
                    }
                }
                self.startMessageLoop()
            }
        }
    }

    private func handleAppleStatus() {
        readExact(3) { [weak self] header in
            guard let self, let header else { return }
            let length = Int(header[1]) << 8 | Int(header[2])
            guard length <= 4096 else { self.handleFailure("Invalid Apple status length"); return }
            self.readExact(length) { body in
                guard let body else { return }
                if body.count == 4 {
                    let flags = Int(body[0]) << 8 | Int(body[1])
                    let command = Int(body[2]) << 8 | Int(body[3])
                    if command != 12 {
                        self.inputDiagnostics?.record(.appleStatus, session: self.inputDiagnosticIdentifier,
                                                      appleFlags: UInt16(flags), appleCommand: UInt16(command))
                        AppLogger.shared.debug("Apple status: flags=\(flags), command=\(command)", category: "RFB")
                    }
                }
                if body == Data([0, 1, 0, 2]) {
                    self.inputLock.lock()
                    if self.appleClipboardMonitoring { self.sendData(Data([0x0B, 0, 0, 0, 0, 0, 0, 0])) }
                    self.inputLock.unlock()
                }
                self.startMessageLoop()
            }
        }
    }

    @discardableResult
    func requestApplePasteboard() -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, appleUTF16Keysyms else { return false }
        if automaticClipboardEnabled && !appleClipboardMonitoring {
            appleClipboardMonitoring = true
            sendData(Data([0x15, 0, 0, 1, 0, 0, 0, 0]))
        }
        sendData(Data([0x0B, 0, 0, 0, 0, 0, 0, 0]))
        return true
    }

    /// Persist monitoring policy across reconnects. Manual fetch does not change it.
    public func setAutomaticClipboardMonitoring(_ enabled: Bool) {
        inputLock.lock()
        defer { inputLock.unlock() }
        automaticClipboardEnabled = enabled
        guard state == .connected, finalDisconnectToken == nil, appleUTF16Keysyms,
              appleClipboardMonitoring != enabled else { return }
        appleClipboardMonitoring = enabled
        sendData(Data([0x15, 0, 0, enabled ? 1 : 2, 0, 0, 0, 0]))
    }

    /// Fetch current content; legacy servers without request support reject it.
    @discardableResult
    public func requestRemoteClipboard() -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, finalDisconnectToken == nil else { return false }
        if appleUTF16Keysyms { return requestApplePasteboard() }
        guard extendedClipboard else { return false }
        sendExtendedClipboard(flags: 0x02000001)
        return true
    }

    public var supportsAppleClipboard: Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        return appleUTF16Keysyms
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
        } else if action == 0x08000000, flags & 1 != 0, automaticClipboardEnabled {
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

    public var usesAutomaticFramebufferUpdates: Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        return automaticFramebufferActive && state == .connected && finalDisconnectToken == nil
    }

    private func configureAutomaticFramebufferUpdates() {
        inputLock.lock(); defer { inputLock.unlock() }
        guard automaticFramebufferUpdates, appleUTF16Keysyms, state == .connected,
              finalDisconnectToken == nil, framebuffer.width > 0, framebuffer.height > 0,
              framebuffer.width <= Int(UInt16.max), framebuffer.height <= Int(UInt16.max) else { return }
        automaticFramebufferActive = true
        sendData(RFBEncoder.encodeAppleAutoFramebufferUpdate(width: UInt16(framebuffer.width),
                                                             height: UInt16(framebuffer.height)))
    }

    private func refreshAutomaticFramebufferRegion() {
        inputLock.lock(); defer { inputLock.unlock() }
        guard usesAutomaticFramebufferUpdates else { return }
        incrementalRefreshGeneration = nil
        configureAutomaticFramebufferUpdates()
        requestUpdate(incremental: false)
    }

    /// Push does not replace polling on a still Apple desktop. Coalesce requests
    /// after complete frames, including empty replies, to at most 30 per second.
    /// One queued callback belongs to exactly one connection and is invalidated
    /// by a resize, final action, failure or disconnect.
    private func scheduleIncrementalRefresh(for sourceConnection: NWConnection) {
        inputLock.lock(); defer { inputLock.unlock() }
        guard connection === sourceConnection, usesAutomaticFramebufferUpdates,
              incrementalRefreshGeneration == nil else { return }
        let generation = UUID()
        incrementalRefreshGeneration = generation
        queue.asyncAfter(deadline: .now() + 1.0 / 30.0) { [weak self, weak sourceConnection] in
            guard let self, let sourceConnection else { return }
            self.inputLock.lock(); defer { self.inputLock.unlock() }
            guard self.connection === sourceConnection, self.usesAutomaticFramebufferUpdates,
                  self.incrementalRefreshGeneration == generation else { return }
            self.incrementalRefreshGeneration = nil
            self.requestUpdate(incremental: true)
        }
    }

    /// Request a screen update from the remote server.
    public func requestUpdate(incremental: Bool) {
        inputLock.lock(); defer { inputLock.unlock() }
        guard state == .connected, finalDisconnectToken == nil,
              framebuffer.width > 0, framebuffer.height > 0,
              framebuffer.width <= Int(UInt16.max), framebuffer.height <= Int(UInt16.max) else { return }
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
            keyOwners.removeAll()
            if !heldPointerButtons.isEmpty {
                sendData(RFBEncoder.encodePointerEvent(buttonMask: [], x: pointerPosition.0, y: pointerPosition.1))
            }
            heldPointerButtons = []
            pendingClipboard = nil
        }
        inputEnabled = enabled
        inputDiagnostics?.record(.inputGateChanged, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags)
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
        inputDiagnostics?.record(.pointerGateChanged, session: inputDiagnosticIdentifier, flags: diagnosticInputFlags)
    }

    @discardableResult
    private func sendPointerPacket(_ mask: RFBConstants.ButtonMask, x: UInt16, y: UInt16, generation: UUID? = nil) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, pointerInputEnabled, !appleDisplayAwaitingPixels, finalDisconnectToken == nil else {
            if mask.rawValue & 7 != 0 {
                inputDiagnostics?.record(.pointerSuppressed, session: inputDiagnosticIdentifier,
                                         flags: diagnosticInputFlags, buttons: mask.rawValue)
            }
            return false
        }
        guard state == .connected, connection != nil else {
            if let inputDiagnostics {
                DiagnosticInput.pointer(mask.rawValue & 7).record(inputDiagnostics, session: inputDiagnosticIdentifier,
                                                                 flags: diagnosticInputFlags, outcome: .dropped)
            }
            return false
        }
        if let generation, generation != inputGeneration { return false }
        let sampled: Bool
        if inputDiagnostics != nil {
            let now = ProcessInfo.processInfo.systemUptime
            sampled = mask.rawValue & 7 != heldPointerButtons.rawValue || now - lastDiagnosticPointerSample >= 5
            if sampled { lastDiagnosticPointerSample = now }
        } else { sampled = false }
        let mapped: (UInt16, UInt16)
        if let layout = appleDisplayLayout {
            if let position = layout.serverCoordinates(x: x, y: y) { mapped = position }
            else if mask.isEmpty && !heldPointerButtons.isEmpty { mapped = pointerPosition }
            else { return false }
        } else { mapped = (x, y) }
        pointerPosition = mapped
        heldPointerButtons = RFBConstants.ButtonMask(rawValue: mask.rawValue & 7)
        sendData(RFBEncoder.encodePointerEvent(buttonMask: mask, x: mapped.0, y: mapped.1),
                 diagnosticInput: sampled ? .pointer(mask.rawValue & 7) : nil)
        return true
    }

    /// Delayed wheel work reads the latest pointer state under the same lock as
    /// ordinary movement. Its press/release pair cannot revive an old drag or
    /// overwrite a newer position, and releasing the wheel keeps held buttons.
    @discardableResult
    private func sendWheelPacket(_ wheel: RFBConstants.ButtonMask, generation: UUID) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard state == .connected, connection != nil, inputEnabled, pointerInputEnabled,
              !appleDisplayAwaitingPixels, finalDisconnectToken == nil, generation == inputGeneration else { return false }
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
        let mapped = appleDisplayLayout?.serverCoordinates(x: x, y: y) ?? (appleDisplayLayout == nil ? (x, y) : nil)
        let enabled = state == .connected && connection != nil && inputEnabled && pointerInputEnabled &&
            !appleDisplayAwaitingPixels && finalDisconnectToken == nil && mapped != nil
        if enabled {
            pointerPosition = mapped!
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
    public func sendKeyEvent(down: Bool, keySym: UInt32, source: KeyInputSource = .app) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, finalDisconnectToken == nil else {
            if keySym == MacKeyMap.return {
                inputDiagnostics?.record(.returnSuppressed, session: inputDiagnosticIdentifier,
                                         flags: diagnosticInputFlags, down: down)
            }
            return
        }
        guard state == .connected, connection != nil else {
            if let inputDiagnostics, keySym == MacKeyMap.return {
                DiagnosticInput.returnKey(down).record(inputDiagnostics, session: inputDiagnosticIdentifier,
                                                       flags: diagnosticInputFlags, outcome: .dropped)
            }
            return
        }
        if down {
            heldKeys.insert(keySym)
            keyOwners[keySym, default: []].insert(source)
        } else {
            keyOwners[keySym]?.remove(source)
            // A toolbar release must not end a still-held physical modifier,
            // and releasing a physical key must preserve a sticky toolbar key.
            if !(keyOwners[keySym]?.isEmpty ?? true) { return }
            keyOwners.removeValue(forKey: keySym)
            heldKeys.remove(keySym)
        }
        let data = RFBEncoder.encodeKeyEvent(down: down, keySym: keySym)
        sendData(data, diagnosticInput: keySym == MacKeyMap.return ? .returnKey(down) : nil)
    }

    /// A user-initiated password transaction never uses either clipboard path.
    @discardableResult
    func typeUserPassword(_ text: String, pressReturn: Bool) -> Bool {
        inputLock.lock(); defer { inputLock.unlock() }
        guard state == .connected, inputEnabled, finalDisconnectToken == nil else { return false }
        sendText(text)
        if pressReturn {
            sendKeyEvent(down: true, keySym: MacKeyMap.return)
            sendKeyEvent(down: false, keySym: MacKeyMap.return)
        }
        return true
    }

    /// Send committed text as complete key strokes rather than overlapping held keys.
    public func sendText(_ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for scalar in normalized.unicodeScalars {
            inputLock.lock()
            defer { inputLock.unlock() }
            // Apple's 3.889 server accepts UTF-16 units, but drops a non-BMP
            // X11 scalar. Keep each surrogate pair together through input gating.
            if appleUTF16Keysyms && scalar.value > 0xFFFF {
                for unit in String(scalar).utf16 {
                    let key = 0x01000000 | UInt32(unit)
                    sendKeyEvent(down: true, keySym: key)
                    sendKeyEvent(down: false, keySym: key)
                }
                continue
            }
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

    /// Queue the modern Apple text archive after an Apple server handshake.
    @discardableResult
    func sendApplePasteboardText(_ text: String) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, finalDisconnectToken == nil, state == .connected, appleUTF16Keysyms,
              let packet = ApplePasteboard.encodeText(text) else { return false }
        sendData(packet)
        return true
    }

    /// Queue typed Apple clipboard flavors without sending a paste shortcut.
    /// Observe mode and unsupported servers reject the upload before any write.
    @discardableResult
    public func sendClipboardFlavors(_ items: [RFBClipboardFlavor]) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, finalDisconnectToken == nil, state == .connected, appleUTF16Keysyms,
              let packet = ApplePasteboard.encodeItems(items) else { return false }
        sendData(packet)
        return true
    }

    /// Queue supported clipboard text. Acceptance does not acknowledge a remote paste.
    @discardableResult
    public func sendCutText(_ text: String) -> Bool {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputEnabled, finalDisconnectToken == nil, state == .connected else { return false }
        if appleUTF16Keysyms { return sendApplePasteboardText(text) }
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

    /// Queue clipboard content and its paste shortcut in one input transaction.
    /// Modern Apple archives are applied in wire order before subsequent keys.
    @discardableResult
    public func sendClipboardAndPaste(_ text: String) -> Bool {
        queueClipboardAndPaste(text) == .queued
    }

    enum ClipboardPasteResult: Equatable { case unsupported, queued, rejected }

    func queueClipboardAndPaste(_ text: String) -> ClipboardPasteResult {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard appleUTF16Keysyms else { return .unsupported }
        guard sendCutText(text) else { return .rejected }
        sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
        sendKeyEvent(down: true, keySym: 118)
        sendKeyEvent(down: false, keySym: 118)
        sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        return .queued
    }

    func queueClipboardAndPaste(_ items: [RFBClipboardFlavor]) -> ClipboardPasteResult {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard appleUTF16Keysyms else { return .unsupported }
        guard !items.isEmpty, sendClipboardFlavors(items) else { return .rejected }
        sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
        sendKeyEvent(down: true, keySym: 118)
        sendKeyEvent(down: false, keySym: 118)
        sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        return .queued
    }

    // MARK: - Socket Helpers

    private enum DiagnosticOutcome { case dropped, queued, processed, failed }

    private enum DiagnosticInput: Sendable {
        case pointer(UInt8)
        case returnKey(Bool)

        func record(_ recorder: InputDiagnostics, session: UUID, flags: InputDiagnostics.Flags, outcome: DiagnosticOutcome) {
            switch self {
            case .pointer(let buttons):
                let stage: InputDiagnostics.Stage = switch outcome {
                case .dropped: .pointerDropped
                case .queued: .pointerQueued
                case .processed: .pointerProcessed
                case .failed: .pointerFailed
                }
                recorder.record(stage, session: session, flags: flags, buttons: buttons)
            case .returnKey(let down):
                let stage: InputDiagnostics.Stage = switch outcome {
                case .dropped: .returnDropped
                case .queued: .returnQueued
                case .processed: .returnProcessed
                case .failed: .returnFailed
                }
                recorder.record(stage, session: session, flags: flags, down: down)
            }
        }
    }

    /// Call only while holding inputLock. These flags describe local gating,
    /// not the Apple server's permission to control its desktop.
    private var diagnosticInputFlags: InputDiagnostics.Flags {
        var flags: InputDiagnostics.Flags = []
        if inputEnabled { flags.insert(.inputEnabled) }
        if pointerInputEnabled { flags.insert(.pointerEnabled) }
        if connection != nil { flags.insert(.connectionPresent) }
        if appleDisplayAwaitingPixels { flags.insert(.displaySwitchPending) }
        if finalDisconnectToken == nil { flags.insert(.notClosing) }
        return flags
    }

    private func sendData(_ data: Data, completion: (@Sendable () -> Void)? = nil, diagnosticInput: DiagnosticInput? = nil) {
        inputLock.lock()
        defer { inputLock.unlock() }
        let diagnosticFlags = inputDiagnostics != nil && diagnosticInput != nil ? diagnosticInputFlags : []
        if let inputDiagnostics, let diagnosticInput {
            diagnosticInput.record(inputDiagnostics, session: inputDiagnosticIdentifier, flags: diagnosticFlags,
                                   outcome: finalDisconnectToken == nil && appleCurtainCloseCompletion == nil && connection != nil ? .queued : .dropped)
        }
        guard finalDisconnectToken == nil, appleCurtainCloseCompletion == nil, let connection else { return }
        connection.send(content: data, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self, let connection, self.connection === connection else { return }
            if let inputDiagnostics = self.inputDiagnostics, let diagnosticInput {
                // Network.framework completion confirms processing of this send,
                // not receipt or execution by the remote Mac.
                diagnosticInput.record(inputDiagnostics, session: self.inputDiagnosticIdentifier,
                                       flags: diagnosticFlags, outcome: error == nil ? .processed : .failed)
            }
            if let error = error {
                self.handleFailure("Connection failed: \(error.localizedDescription)", from: connection)
                return
            }
            self.collectTransportReportIfDue(connection: connection)
            completion?()
        }))
    }

    private func readExact(_ count: Int, completion: @escaping @Sendable (Data?) -> Void) {
        inputLock.lock()
        let sourceConnection = connection
        inputLock.unlock()
        guard let sourceConnection else { return }
        readExact(count, from: sourceConnection, completion: completion)
    }

    /// Buffer operations share the lifecycle lock; every retry retains its original socket.
    /// External callbacks and Network calls run after releasing this transaction's lock.
    private func readExact(_ count: Int, from conn: NWConnection,
                           completion: @escaping @Sendable (Data?) -> Void) {
        inputLock.lock()
        guard connection === conn else { inputLock.unlock(); return }
        if readBuffer.count >= count {
            let chunk = Data(readBuffer.prefix(count))
            readBuffer.removeSubrange(0..<count)
            inputLock.unlock()
            completion(chunk)
            return
        }
        let needed = count - readBuffer.count
        inputLock.unlock()
        let maxReceive = min(max(needed, 65536), 1048576)
        conn.receive(minimumIncompleteLength: 1, maximumLength: maxReceive) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            self.inputLock.lock()
            // Retirement abandons this private parsing continuation. It must not
            // report a fabricated failure or resume a rectangle on its replacement.
            guard self.connection === conn else { self.inputLock.unlock(); return }
            let receivedBytes = content?.count ?? 0
            if let content, !content.isEmpty { self.readBuffer.append(content) }
            let progress: (Double, Double)?
            if !self.hasCompletedFramebufferUpdate && count > 100000 &&
                self.readBuffer.count % 2097152 < receivedBytes {
                progress = (Double(self.readBuffer.count) / (1024.0 * 1024.0),
                            Double(count) / (1024.0 * 1024.0))
            } else { progress = nil }
            self.inputLock.unlock()

            if receivedBytes > 0 { self.onBytesReceived?(receivedBytes) }
            if let progress, self.connection === conn {
                self.onDownloadProgress?(progress.0, progress.1)
            }

            self.inputLock.lock()
            guard self.connection === conn else { self.inputLock.unlock(); return }
            if let error {
                self.inputLock.unlock()
                self.handleFailure("Socket read error: \(error.localizedDescription)", from: conn)
                return
            }
            if self.readBuffer.count >= count {
                let chunk = Data(self.readBuffer.prefix(count))
                self.readBuffer.removeSubrange(0..<count)
                self.inputLock.unlock()
                completion(chunk)
            } else if isComplete {
                let availableBytes = self.readBuffer.count
                self.inputLock.unlock()
                print("[DEBUG readExact] Connection marked isComplete=true, but only have \(availableBytes) of \(count) bytes")
                self.handleFailure("Remote host closed connection (received \(availableBytes)/\(count) bytes)", from: conn)
            } else {
                self.inputLock.unlock()
                self.readExact(count, from: conn, completion: completion)
            }
        }
    }

    private func collectTransportReportIfDue(connection: NWConnection) {
        guard state == .connected, self.connection === connection,
              reportConnection === connection else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTransferReportTime >= transportReportInterval else { return }
        if usesSSHTransport {
            guard pendingSSHTransportReport == nil, let provider = sshRoundTripTimeProvider else { return }
            lastTransferReportTime = now
            pendingSSHTransportReport = Task { [weak self, weak connection] in
                let sample = await provider()
                guard !Task.isCancelled else { return }
                self?.queue.async { [weak self, weak connection] in
                    guard let self, let connection, self.connection === connection,
                          self.reportConnection === connection, self.state == .connected else { return }
                    self.pendingSSHTransportReport = nil
                    guard let sample, sample.isFinite, sample > 0 else { return }
                    self.onTransportRTT?(sample)
                }
            }
            return
        }
        guard let report = pendingTransferReport else { return }
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
            self.pendingSSHTransportReport?.cancel()
            self.pendingSSHTransportReport = nil
            self.pendingTransferReport = nil
            self.reportConnection = nil
        }
    }

    private func handleFailure(_ message: String, from sourceConnection: NWConnection? = nil) {
        inputLock.lock()
        if let sourceConnection, connection !== sourceConnection { inputLock.unlock(); return }
        stopTransportReports()
        automaticFramebufferActive = false
        incrementalRefreshGeneration = nil
        appleDisplaySelectionGeneration = nil
        appleServerScalingGeneration = nil
        appleDisplayLayout = nil
        appleDisplayAwaitingPixels = false
        appleDisplayHasFreshPixels = false
        let previous = connection
        connection = nil
        heldKeys.removeAll()
        keyOwners.removeAll()
        heldPointerButtons = []
        pendingClipboard = nil
        inputGeneration = UUID()
        readBuffer.removeAll()
        appleCurtain.disconnected(connection: appleCurtainConnectionID, failed: true)
        publishAppleCurtainStatus()
        let curtainCompletion = appleCurtainCloseCompletion
        appleCurtainCloseCompletion = nil
        curtainCompletion?.finish(false)
        inputLock.unlock()
        AppLogger.shared.error("Session failed: \(message)", category: "RFB")
        previous?.cancel()
        // A failure observer may reconnect synchronously. Teardown must finish
        // before publishing, so it cannot cancel the replacement connection.
        state = .failed(message)
    }
}

/// Send completion and timeout can race; neither may settle a close twice.
private final class FinalInputCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Bool) -> Void)?
    init(_ completion: @escaping @Sendable (Bool) -> Void) { self.completion = completion }
    func finish(_ processed: Bool) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(processed)
    }
}
