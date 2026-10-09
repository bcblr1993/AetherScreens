import Foundation
import SwiftUI
import CoreGraphics
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Manages a live remote screen sharing session with a Mac.
@MainActor
public final class SessionViewModel: ObservableObject, Identifiable {
    public let device: RemoteDevice
    public nonisolated var id: UUID { device.id }
    let fileTransfers = FileTransferTaskStore()
    lazy var fileUploadCoordinator = AppleFileCopyUploadCoordinator(store: fileTransfers, client: client)
    lazy var fileDownloadCoordinator = AppleFileCopyDownloadCoordinator(store: fileTransfers, client: client)
    @Published var isPreparingFileUpload = false
    @Published var fileUploadNotice: String?
    @Published var fileDownloadNotice: String?
    var fileUploadPreparationTask: Task<Void, Never>?
    var fileUploadPreparationID = UUID()
    public let client: RFBClient
    public let trackpadEngine: TrackpadEngine
    public let curtainManager: CurtainModeManager
    public let multiDisplayManager: MultiDisplayManager
    public let remoteInteraction = PassthroughSubject<Void, Never>()
    public let pencilToolbarToggle = PassthroughSubject<CGPoint?, Never>()
    public let metrics: PerformanceMetrics
    public let metalRenderer: MetalScreenRenderer?

    @Published public var passwordSaveNotice: String?
    @Published public var sessionState: RFBClient.State = .disconnected
    @Published public private(set) var isAwaitingAutomaticReconnect = false
    @Published public private(set) var sshPrompt: SessionSSHPrompt?
    private var sshPasswordContinuation: CheckedContinuation<String?, Never>?
    private var sshHostContinuation: CheckedContinuation<Bool, Never>?
    private var sshSetupTask: Task<Void, Never>?
    private var reconnectPolicy = SessionReconnectPolicy()
    private var automaticReconnectTask: Task<Void, Never>?
    private var automaticReconnectIdentity = UUID()
    private var sessionLifecycleActive = false
    private var sshTunnel: SSHForwardingTunnel?
    private var sshGeneration = UUID()
    private let sshCredentials: SSHCredentialStore
    private let sshTrust: SSHHostTrustStore
    private let initialSSHPassword: String?
    private let initialSSHPrivateKey: Data?
    @Published public var currentImage: CGImage?
    @Published public var hasReceivedFirstFrame: Bool = false
    @Published public var downloadProgress: (current: Double, total: Double)? = nil
    @Published public var inputMode: TrackpadEngine.Mode = .trackpad {
        didSet {
            trackpadEngine.releaseAllButtons()
            trackpadEngine.mode = inputMode
        }
    }
    @Published public var isObserveOnly = false {
        didSet {
            releaseToolbarHeldKeys()
            releaseAllModifiers()
            trackpadEngine.releaseAllButtons()
            if isObserveOnly { stopFileTransfers(); isKeyboardVisible = false }
            client.setInputEnabled(!isObserveOnly && isForegroundSession)
            inputGeneration = UUID()
        }
    }
    private var pointerButtonsForModifiers: RFBConstants.ButtonMask = []
    private var toolbarHeldKeys: Set<UInt32> = []
    private var pendingModifierWheels = 0
    private var modifierWheelGeneration = UUID()
    private var cmdGeneration = UUID(), optGeneration = UUID(), ctrlGeneration = UUID(), shiftGeneration = UUID()
    private struct OnceModifierSnapshot: Sendable {
        let cmd: UUID?, opt: UUID?, ctrl: UUID?, shift: UUID?
        var isEmpty: Bool { cmd == nil && opt == nil && ctrl == nil && shift == nil }
    }
    private var onceModifierSnapshot: OnceModifierSnapshot {
        OnceModifierSnapshot(cmd: cmdState == .activeOnce ? cmdGeneration : nil,
            opt: optState == .activeOnce ? optGeneration : nil,
            ctrl: ctrlState == .activeOnce ? ctrlGeneration : nil,
            shift: shiftState == .activeOnce ? shiftGeneration : nil)
    }
    @Published public var isKeyboardVisible: Bool = false {
        didSet { if !isKeyboardVisible { releaseToolbarHeldKeys() } }
    }
    @Published public var showShortcutsMenu: Bool = false
    @Published public var showDisplaysMenu: Bool = false
    @Published public var isTextInputBarVisible: Bool = false
    @Published public var textInputBuffer: String = ""
    @Published public var clipboardTransferNotice: String?

    // 3-State Modifiers (Screens Sticky Keys)
    public enum ModifierState: Equatable, Sendable {
        case inactive
        case activeOnce // active for the next key or completed mouse action
        case locked     // double-tapped, stays active indefinitely
    }

    @Published public var cmdState: ModifierState = .inactive { didSet { cmdGeneration = UUID() } }
    @Published public var optState: ModifierState = .inactive { didSet { optGeneration = UUID() } }
    @Published public var ctrlState: ModifierState = .inactive { didSet { ctrlGeneration = UUID() } }
    @Published public var shiftState: ModifierState = .inactive { didSet { shiftGeneration = UUID() } }

    // Backward-compatibility computed booleans
    public var isCmdActive: Bool { cmdState != .inactive }
    public var isOptActive: Bool { optState != .inactive }
    public var isCtrlActive: Bool { ctrlState != .inactive }
    public var isShiftActive: Bool { shiftState != .inactive }

    // Zoom and pan
    @Published public var isFullscreen = false
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var viewOffset: CGSize = .zero

    // Active Display Crop Rect (if specific display is selected)
    @Published public var activeCropRect: CGRect? = nil

    // Password Prompt Sheet State
    @Published public var isPromptingPassword: Bool = false
    @Published public var passwordPromptError: String? = nil
    private var passwordContinuation: ((String?) -> Void)? = nil
    @Published public var requiresMacAccountPrompt = false
    private var macAccountContinuation: ((String?, String?) -> Void)?

    @Published public var actualSizeZoomScale: CGFloat = 2
    @Published public var isPanningViewport: Bool = false {
        didSet {
            if isPanningViewport {
                trackpadEngine.releaseAllButtons()
                resetPendingModifierWheels()
            }
            pointerButtonsForModifiers = []
            client.setPointerInputEnabled(!isPanningViewport)
        }
    }
    @Published public private(set) var inputGeneration = UUID() {
        didSet {
            pointerButtonsForModifiers = []
            client.cancelPendingWheelEvents()
            resetPendingModifierWheels()
            releaseToolbarHeldKeys()
        }
    }
    private let thumbnailSnapshots = ThumbnailSnapshotScheduler()
    private var thumbnailCadence = ThumbnailSnapshotCadence()
    private let frameUpdateGate = FrameUpdateGate()
    private let fallbackFramePipeline = FallbackFramePipeline()
    /// Additional display surfaces subscribe without invalidating the whole UI per frame.
    public let frameUpdates = PassthroughSubject<Void, Never>()
    public let pointerUpdates = PassthroughSubject<CGPoint, Never>()
    public let cursorUpdates = CurrentValueSubject<RFBRemoteCursor?, Never>(nil)
    @Published private var lastFramebufferSize = CGSize.zero

    public let isTemporary: Bool
    @Published public var keyboardConfiguration: KeyboardToolbarConfiguration {
        didSet {
            // A hidden sticky key must never leave the remote modifier held.
            if keyboardConfiguration.items != oldValue.items { releaseAllModifiers() }
            if !isTemporary { keyboardStore.save(keyboardConfiguration, for: device.id) }
        }
    }
    private let keyboardStore: KeyboardToolbarStore
    private let displayQualityStore: DisplayQualityStore
    @Published public private(set) var displayColorDepth: RFBColorDepth = .fullColor
    @Published public private(set) var automaticDisplayQuality = false
    private var adaptiveDisplayQuality = AdaptiveDisplayQuality()
    private let clipboardReader: @MainActor @Sendable () -> String?
    private let clipboardWriter: @MainActor @Sendable (String) -> Void
    public var canRememberPassword: Bool { !isTemporary }
    private let deviceStore: DeviceStore
    private nonisolated let callbackGeneration = SessionCallbackGeneration()
    private nonisolated let lockShortcutGeneration = SessionCallbackGeneration()
    private nonisolated let foregroundGeneration = SessionCallbackGeneration()
    private nonisolated let qualityGeneration = SessionCallbackGeneration()
    @Published public private(set) var isForegroundSession = true

    public init(device: RemoteDevice, password: String?, isTemporary: Bool = false,
                deviceStore: DeviceStore = .shared, keyboardStore: KeyboardToolbarStore = .shared,
                clipboardWriter: (@MainActor @Sendable (String) -> Void)? = nil,
                clipboardReader: (@MainActor @Sendable () -> String?)? = nil,
                displayQualityStore: DisplayQualityStore = .shared,
                sshCredentials: SSHCredentialStore = .shared,
                sshTrust: SSHHostTrustStore = .shared,
                initialSSHPassword: String? = nil, initialSSHPrivateKey: Data? = nil) {
        self.device = device
        self.sshCredentials = sshCredentials
        self.sshTrust = sshTrust
        self.initialSSHPassword = initialSSHPassword
        self.initialSSHPrivateKey = initialSSHPrivateKey
        self.isTemporary = isTemporary
        self.deviceStore = deviceStore
        self.keyboardStore = keyboardStore
        self.displayQualityStore = displayQualityStore
        let initialColorDepth: RFBColorDepth = isTemporary ? .fullColor : displayQualityStore.load(for: device.id)
        self.displayColorDepth = initialColorDepth
        self.automaticDisplayQuality = !isTemporary && displayQualityStore.loadAutomatic(for: device.id)
        self.clipboardReader = clipboardReader ?? {
            #if canImport(UIKit)
            return UIPasteboard.general.string
            #elseif canImport(AppKit)
            return NSPasteboard.general.string(forType: .string)
            #else
            return nil
            #endif
        }
        self.clipboardWriter = clipboardWriter ?? { text in
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
        self.keyboardConfiguration = isTemporary ? KeyboardToolbarConfiguration() : keyboardStore.load(for: device.id)
        let rfb = RFBClient(
            host: device.host,
            port: device.port,
            password: password,
            username: device.username,
            colorDepth: initialColorDepth,
            requiresLoopbackForwarding: device.ssh != nil
        )
        self.client = rfb
        self.trackpadEngine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
        self.curtainManager = CurtainModeManager()
        self.multiDisplayManager = MultiDisplayManager()
        self.metrics = PerformanceMetrics()

        let renderer = MetalScreenRenderer(metrics: self.metrics)
        renderer?.framebuffer = rfb.framebuffer
        self.metalRenderer = renderer

        setupBindings()
    }

    private func setupBindings() {
        // Handle pointer events from trackpad engine
        trackpadEngine.onPointerEvent = { [weak self] mask, x, y in
            // Session-owned gestures are delivered by native UI handlers on the
            // main actor. Preserve event order without adding an asynchronous hop.
            MainActor.assumeIsolated {
                self?.sendNativePointer(buttonMask: mask, x: x, y: y)
            }
        }

        // Handle Curtain Mode toggle
        curtainManager.onCurtainStateChanged = { [weak self] isActive in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            let foreground = self.foregroundGeneration.capture()
            let shortcut = self.lockShortcutGeneration.advance()
            Task { @MainActor [weak self] in
                guard let self, isActive, self.curtainManager.isCurtainActive,
                      self.callbackGeneration.matches(generation),
                      self.foregroundGeneration.matches(foreground),
                      self.lockShortcutGeneration.matches(shortcut) else { return }
                // Send only the latest intentional Lock Screen shortcut.
                self.executeShortcut(.lockScreen)
            }
        }

        // Selection and server layout callbacks share the session generation guard.
        multiDisplayManager.onDisplaySelected = { [weak self] _ in
            guard let self else { return }
            // Release at the transport's last global position and invalidate queued
            // wheels before the UI task clears local drag state in the new crop.
            self.client.setPointerInputEnabled(false)
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
                self.applyDisplaySelection(resetInput: true)
            }
        }
        client.onDisplayLayoutReceived = { [weak self] layout in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
                if let layout { self.multiDisplayManager.updateFromLayout(layout) }
                else { self.multiDisplayManager.reset(width: self.client.framebuffer.width, height: self.client.framebuffer.height) }
                self.applyDisplaySelection()
            }
        }

        // Handle RFB client state changes
        client.onStateChanged = { [weak self] state in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
                self.sessionState = state
                if state == .connected { self.metalRenderer?.setUploadBufferCachingEnabled(true) }
                let stopped: Bool
                switch state {
                case .disconnected, .failed: stopped = true
                default: stopped = false
                }
                if stopped {
                    self.stopFileTransfers()
                    self.cursorUpdates.send(nil)
                    self.metalRenderer?.setUploadBufferCachingEnabled(false)
                    self.resetPendingModifierWheels()
                    self.metrics.reset()
                    self.releaseToolbarHeldKeys()
                    self.releaseAllModifiers()
                    self.trackpadEngine.releaseAllButtons()
                    self.inputGeneration = UUID()
                    self.scheduleAutomaticReconnect()
                }
                if state == .connected, !self.isTemporary {
                    self.deviceStore.recordConnection(for: self.device)
                }
            }
        }

        // Handle Interactive VNC Password Prompt from Server
        client.onRequestPassword = { [weak self] continuation in
            guard let self else { continuation(nil); return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else {
                    continuation(nil)
                    return
                }
                self.passwordContinuation = continuation
                self.cancelAutomaticReconnect()
                self.requiresMacAccountPrompt = false
                self.passwordPromptError = nil
                self.isPromptingPassword = true
            }
        }

        client.onRequestMacAccount = { [weak self] continuation in
            guard let self else { continuation(nil, nil); return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { continuation(nil, nil); return }
                self.macAccountContinuation = continuation
                self.cancelAutomaticReconnect()
                self.requiresMacAccountPrompt = true
                self.passwordPromptError = nil
                self.isPromptingPassword = true
            }
        }

        let sessionMetrics = metrics
        client.onBytesReceived = { count in sessionMetrics.recordBytesReceived(count) }
        client.onPixelTransferSample = { [weak self] bytes, duration in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            let foreground = self.foregroundGeneration.capture()
            let quality = self.qualityGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation),
                      self.foregroundGeneration.matches(foreground), self.isForegroundSession,
                      self.qualityGeneration.matches(quality),
                      self.automaticDisplayQuality, self.client.state == .connected,
                      !self.client.isNativeDisplaySession else { return }
                if let level = self.adaptiveDisplayQuality.sample(bytes: bytes, payloadDuration: duration,
                    now: ProcessInfo.processInfo.systemUptime, foreground: true) {
                    self.client.setCompressionQuality(jpegQuality: level.rawValue)
                }
            }
        }
        client.onTransportRTT = { [weak self] milliseconds in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation),
                      self.client.state == .connected else { return }
                self.metrics.recordLatency(ms: milliseconds)
            }
        }

        // Handle incoming frame download progress
        client.onDownloadProgress = { [weak self] current, total in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
                guard !self.hasReceivedFirstFrame else { return }
                self.downloadProgress = (current, total)
            }
        }

        // Handle incoming screen frame updates
        let renderer = metalRenderer
        client.onFrameUpdated = { [weak self] in
            guard let self else { return }
            renderer?.notifyFrameUpdated()
            guard let generation = self.callbackGeneration.scheduleFrame(gate: self.frameUpdateGate) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let updates = self.frameUpdateGate.consume(generation: generation)
                guard updates > 0, self.callbackGeneration.matches(generation) else { return }
                self.frameUpdates.send()
                if !self.hasReceivedFirstFrame {
                    self.hasReceivedFirstFrame = true
                    self.reconnectPolicy.receivedDesktop()
                    self.cancelAutomaticReconnect()
                }
                if self.downloadProgress != nil { self.downloadProgress = nil }
                if self.metalRenderer == nil {
                    self.fallbackFramePipeline.submit(framebuffer: self.client.framebuffer, generation: generation) { [weak self] image, expected in
                        MainActor.assumeIsolated {
                            guard let self, self.callbackGeneration.matches(expected) else { return }
                            self.currentImage = image
                        }
                    }
                }

                let w = self.client.framebuffer.width
                let h = self.client.framebuffer.height
                let size = CGSize(width: w, height: h)
                if self.lastFramebufferSize != size {
                    self.lastFramebufferSize = size
                    if self.activeCropRect == nil {
                        self.trackpadEngine.remoteWidth = CGFloat(w)
                        self.trackpadEngine.remoteHeight = CGFloat(h)
                        self.trackpadEngine.resetCursor()
                    }
                    self.multiDisplayManager.updateFromFramebuffer(width: w, height: h)
                }

                // Periodically save thumbnail for device list view
                if !self.isTemporary && self.thumbnailCadence.shouldCapture(
                    at: ProcessInfo.processInfo.systemUptime) {
                    let framebuffer = self.client.framebuffer
                    let deviceId = self.device.id
                    self.thumbnailSnapshots.schedule {
                        if let image = framebuffer.makeCGImage() {
                            ThumbnailStore.shared.saveThumbnail(image, for: deviceId)
                        }
                    }
                }
            }
        }

        client.onCursorReceived = { [weak self] cursor in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation),
                      self.client.state == .connected else { return }
                self.cursorUpdates.send(cursor)
            }
        }

        // Handle incoming clipboard text
        client.onClipboardReceived = { [weak self] text in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            let foreground = self.foregroundGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation),
                      self.foregroundGeneration.matches(foreground), self.isForegroundSession,
                      self.client.state == .connected else { return }
                self.clipboardWriter(text)
            }
        }
    }

    private func applyDisplaySelection(resetInput: Bool = false) {
        let display = multiDisplayManager.currentDisplay
        let crop = display.flatMap { $0.id > 0 ? $0.bounds : nil }
        let width = crop?.width ?? CGFloat(client.framebuffer.width)
        let height = crop?.height ?? CGFloat(client.framebuffer.height)
        let geometryChanged = crop != activeCropRect || width != trackpadEngine.remoteWidth || height != trackpadEngine.remoteHeight
        guard geometryChanged || resetInput else { return }
        // Release before local coordinates can be translated into a new display.
        client.setPointerInputEnabled(false)
        defer { client.setPointerInputEnabled(!isPanningViewport) }
        trackpadEngine.releaseAllButtons()
        inputGeneration = UUID()
        guard geometryChanged else { return }
        activeCropRect = crop
        trackpadEngine.remoteWidth = width
        trackpadEngine.remoteHeight = height
        zoomScale = 1
        viewOffset = .zero
        isPanningViewport = false
        if client.state == .connected { trackpadEngine.resetCursor() }
    }

    /// Keep the connection and viewport, but only the selected session may control input or clipboard.
    public func setForegroundSession(_ foreground: Bool) {
        guard foreground != isForegroundSession else { return }
        releaseToolbarHeldKeys()
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        foregroundGeneration.advance()
        inputGeneration = UUID()
        isForegroundSession = foreground
        qualityGeneration.advance()
        adaptiveDisplayQuality.reset()
        if foreground {
            client.setCompressionQuality(jpegQuality: automaticDisplayQuality ? adaptiveDisplayQuality.level.rawValue : nil)
        }
        if !foreground {
            cancelAutomaticReconnect()
            stopFileTransfers()
            isKeyboardVisible = false
            isTextInputBarVisible = false
        }
        client.setInputEnabled(foreground && !isObserveOnly)
        if foreground { scheduleAutomaticReconnect() }
    }

    /// Submit entered password to active RFB handshake
    public func submitPassword(_ pwd: String, rememberInKeychain: Bool, accountUsername: String? = nil) {
        passwordSaveNotice = nil
        if let accountContinuation = macAccountContinuation {
            guard let account = accountUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else { return }
            macAccountContinuation = nil
            if canRememberPassword {
                var updated = device
                updated.username = account
                updated.authMethod = .macAccount
                if !deviceStore.updateDevice(updated, password: rememberInKeychain ? pwd : nil) {
                    passwordSaveNotice = "This connection can continue, but its password was not saved to Keychain. Re-enter it after restarting the app."
                }
            }
            isPromptingPassword = false
            accountContinuation(account, pwd)
            return
        }
        client.password = pwd
        if rememberInKeychain && canRememberPassword {
            if !deviceStore.updatePassword(pwd, for: device) {
                passwordSaveNotice = "This connection can continue, but its password was not saved to Keychain. Re-enter it after restarting the app."
            }
        }
        isPromptingPassword = false
        let cont = passwordContinuation
        passwordContinuation = nil
        if let cont {
            cont(pwd)
        } else if case .failed = client.state {
            reconnectSession()
        }
    }

    /// Cancel interactive password prompt
    public func cancelPasswordPrompt() {
        reconnectPolicy.stop()
        cancelAutomaticReconnect()
        clearPasswordPrompt()
        stopFileTransfers()
        client.disconnect()
    }

    private func clearPasswordPrompt() {
        isPromptingPassword = false
        let cont = passwordContinuation
        passwordContinuation = nil
        cont?(nil)
        let accountContinuation = macAccountContinuation
        macAccountContinuation = nil
        accountContinuation?(nil, nil)
    }

    /// Move the local viewport without emitting remote pointer events.
    public func panViewport(dx: CGFloat, dy: CGFloat, limitX: CGFloat, limitY: CGFloat) {
        let x = max(-limitX, min(limitX, viewOffset.width))
        let y = max(-limitY, min(limitY, viewOffset.height))
        let updated = CGSize(width: max(-limitX, min(limitX, x + dx)),
                             height: max(-limitY, min(limitY, y + dy)))
        // Repeated motion against a desktop boundary should not invalidate the UI.
        if updated != viewOffset { viewOffset = updated }
    }

    /// Connect to remote Mac
    public func startSession() {
        startSession(preservingReconnectBudget: false)
    }

    private func startSession(preservingReconnectBudget: Bool) {
        cancelAutomaticReconnect()
        qualityGeneration.advance()
        adaptiveDisplayQuality.reset()
        client.setCompressionQuality(jpegQuality: automaticDisplayQuality ? adaptiveDisplayQuality.level.rawValue : nil)
        sessionLifecycleActive = true
        if !preservingReconnectBudget { reconnectPolicy = SessionReconnectPolicy() }
        stopFileTransfers()
        if device.ssh != nil {
            cancelSSHSetup()
            client.disconnect()
            _ = client.configureLoopbackForwarding(port: nil)
        }
        isDisconnectRequested = false
        thumbnailCadence = ThumbnailSnapshotCadence()
        client.setInputEnabled(isForegroundSession && !isObserveOnly)
        resetPendingModifierWheels()
        pointerButtonsForModifiers = []
        fallbackFramePipeline.begin(generation: callbackGeneration.advance(frameGate: frameUpdateGate))
        cursorUpdates.send(nil)
        metrics.reset()
        hasReceivedFirstFrame = false
        downloadProgress = nil
        lastFramebufferSize = .zero
        multiDisplayManager.reset(width: client.framebuffer.width, height: client.framebuffer.height)
        if let settings = device.ssh { startSSH(settings) }
        else { client.connect() }
    }

    /// Reauthenticate without leaving the viewport; also clear held local input.
    public func reconnectSession() {
        releaseToolbarHeldKeys()
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        cancelPasswordPrompt()
        inputGeneration = UUID()
        if curtainManager.isCurtainActive { curtainManager.toggleCurtain() }
        stopFileTransfers()
        client.disconnect()
        startSession()
    }

    public func selectDisplayColorDepth(_ depth: RFBColorDepth) {
        guard isForegroundSession, depth != displayColorDepth else { return }
        if curtainManager.isCurtainActive { curtainManager.toggleCurtain() }
        releaseToolbarHeldKeys()
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        cancelPasswordPrompt()
        inputGeneration = UUID()
        stopFileTransfers()
        client.disconnect()
        guard client.configureColorDepth(depth) else { return }
        displayColorDepth = depth
        if !isTemporary { displayQualityStore.save(depth, for: device.id) }
        startSession()
    }

    public func selectAutomaticDisplayQuality(_ enabled: Bool) {
        guard isForegroundSession, enabled != automaticDisplayQuality,
              !client.isNativeDisplaySession else { return }
        automaticDisplayQuality = enabled
        qualityGeneration.advance()
        adaptiveDisplayQuality.reset()
        if !isTemporary { displayQualityStore.saveAutomatic(enabled, for: device.id) }
        client.setCompressionQuality(jpegQuality: enabled ? adaptiveDisplayQuality.level.rawValue : nil)
    }

    /// Explicit user close; lifecycle cleanup alone must never trigger remote actions.
    private var isDisconnectRequested = false
    public func requestDisconnect() {
        guard !isDisconnectRequested else { return }
        isDisconnectRequested = true
        let action = !isTemporary && isForegroundSession && !isObserveOnly
            ? DisconnectActionStore.shared.load(for: device.id, type: device.deviceType) : .none
        // Detach before local teardown so disappearance cannot prematurely
        // close the transport carrying the final complete key sequence.
        let drainingTunnel = sshTunnel
        sshTunnel = nil
        endSession()
        stopFileTransfers()
        client.disconnect(performing: action, deviceType: device.deviceType)
        if let drainingTunnel {
            Task { await drainingTunnel.finishForwardedConnections() }
        }
    }

    /// Clean up local session state without triggering configured remote actions.
    public func endSession() {
        sessionLifecycleActive = false
        reconnectPolicy.stop()
        cancelAutomaticReconnect()
        metalRenderer?.setUploadBufferCachingEnabled(false)
        cancelSSHSetup()
        resetPendingModifierWheels()
        fallbackFramePipeline.begin(generation: callbackGeneration.advance(frameGate: frameUpdateGate))
        cursorUpdates.send(nil)
        metrics.reset()
        releaseToolbarHeldKeys()
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        let framebuffer = client.framebuffer
        let deviceId = device.id
        // A failed/unopened attempt may still have an allocated blank framebuffer.
        // Preserve the last successful preview until this attempt received a frame.
        if !isTemporary && hasReceivedFirstFrame {
            thumbnailSnapshots.schedule {
                if let image = framebuffer.makeCGImage() {
                    ThumbnailStore.shared.saveThumbnail(image, for: deviceId)
                }
            }
        }
        hasReceivedFirstFrame = false
        downloadProgress = nil
        if isDisconnectRequested { clearPasswordPrompt() }
        else { cancelPasswordPrompt() }
    }

    private func cancelAutomaticReconnect() {
        automaticReconnectIdentity = UUID()
        automaticReconnectTask?.cancel()
        automaticReconnectTask = nil
        isAwaitingAutomaticReconnect = false
    }

    private func scheduleAutomaticReconnect() {
        guard sessionLifecycleActive, isForegroundSession, !isDisconnectRequested,
              !isPromptingPassword, sshPrompt == nil,
              automaticReconnectTask == nil else { return }
        switch sessionState {
        case .disconnected, .failed: break
        default: return
        }
        guard let delay = reconnectPolicy.nextDelay() else { return }
        let identity = automaticReconnectIdentity
        automaticReconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.automaticReconnectIdentity == identity,
                  self.sessionLifecycleActive, self.isForegroundSession,
                  !self.isDisconnectRequested else { return }
            self.automaticReconnectTask = nil
            self.clearPasswordPrompt()
            self.client.disconnect()
            self.startSession(preservingReconnectBudget: true)
        }
        isAwaitingAutomaticReconnect = true
    }

    private func cancelSSHSetup() {
        sshGeneration = UUID()
        sshSetupTask?.cancel()
        sshSetupTask = nil
        let password = sshPasswordContinuation, host = sshHostContinuation
        sshPasswordContinuation = nil
        sshHostContinuation = nil
        sshPrompt = nil
        password?.resume(returning: nil)
        host?.resume(returning: false)
        if let tunnel = sshTunnel { Task { await tunnel.stop() } }
        sshTunnel = nil
    }

    private func startSSH(_ settings: SSHConnectionSettings) {
        let generation = sshGeneration
        let tunnel = SSHForwardingTunnel()
        sshTunnel = tunnel
        sessionState = .connecting
        sshSetupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let password: String
                var privateKeyData: Data?
                if case .privateKey(let reference) = settings.authentication {
                    guard let data = try self.initialSSHPrivateKey ?? self.sshCredentials.load(kind: .privateKey, reference: reference) else {
                        throw SSHForwardingTunnel.Failure.unsupportedAuthentication
                    }
                    privateKeyData = data
                    password = ""
                } else if let initial = self.initialSSHPassword {
                    password = initial
                } else if let data = try self.deviceStore.getSSHPassword(for: self.device, credentials: self.sshCredentials) {
                    guard let decoded = String(data: data, encoding: .utf8) else {
                        throw SSHForwardingTunnel.Failure.invalidData
                    }
                    password = decoded
                } else {
                    guard let entered = await withCheckedContinuation({ continuation in
                        self.sshPasswordContinuation = continuation
                        self.sshPrompt = SessionSSHPrompt(settings: settings, kind: .password)
                    }) else { throw SSHForwardingTunnel.Failure.cancelled }
                    password = entered
                }
                try Task.checkCancellation()
                guard self.sshGeneration == generation else { return }
                let localPort = try await tunnel.start(settings: settings, password: password, privateKeyData: privateKeyData,
                    remotePort: self.device.port, trust: self.sshTrust) { [weak self] key, assessment in
                    guard let self else { return false }
                    return await self.confirmSSHHost(settings: settings, key: key,
                        assessment: assessment, generation: generation)
                }
                try Task.checkCancellation()
                guard self.sshGeneration == generation else { await tunnel.stop(); return }
                guard self.client.configureLoopbackForwarding(port: localPort) else {
                    throw SSHForwardingTunnel.Failure.invalidForward
                }
                self.sshSetupTask = nil
                self.client.connect()
            } catch {
                await tunnel.stop()
                guard self.sshGeneration == generation else { return }
                self.sshSetupTask = nil
                self.sshTunnel = nil
                if error is CancellationError || (error as? SSHForwardingTunnel.Failure) == .cancelled {
                    self.sessionState = .disconnected
                    self.reconnectPolicy.stop()
                    self.cancelAutomaticReconnect()
                } else {
                    self.sessionState = .failed(AppLocalization.string(
                        (error as? SSHForwardingTunnel.Failure) == .unsupportedAuthentication
                        ? "The SSH private key is missing. Import it again."
                        : "SSH connection failed. Check the server, credentials and host identity."))
                    if SessionReconnectPolicy.retriesSSHError(error) {
                        self.scheduleAutomaticReconnect()
                    } else {
                        self.reconnectPolicy.stop()
                        self.cancelAutomaticReconnect()
                    }
                }
            }
        }
    }

    private func confirmSSHHost(settings: SSHConnectionSettings, key: SSHHostKey,
                                assessment: SSHHostTrustStore.Assessment, generation: UUID) async -> Bool {
        guard sshGeneration == generation, !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            sshHostContinuation = continuation
            sshPrompt = SessionSSHPrompt(settings: settings, kind: .host(key, assessment))
        }
    }

    public func submitSSHPassword(_ password: String, remember: Bool, promptID: UUID) {
        guard sshPrompt?.id == promptID, let continuation = sshPasswordContinuation else { return }
        if remember && canRememberPassword {
            do {
                try sshCredentials.save(Data(password.utf8), kind: .password, reference: device.id)
                deviceStore.bindSavedSSHPassword(for: device)
            }
            catch {
                sshPrompt?.error = AppLocalization.string("Could not save the SSH password to Keychain.")
                return
            }
        }
        sshPasswordContinuation = nil
        sshPrompt = nil
        continuation.resume(returning: password)
    }

    public func approveSSHHost(promptID: UUID) {
        guard sshPrompt?.id == promptID, let continuation = sshHostContinuation else { return }
        sshHostContinuation = nil
        sshPrompt = nil
        continuation.resume(returning: true)
    }

    public func cancelSSHPrompt(promptID: UUID) {
        guard sshPrompt?.id == promptID else { return }
        reconnectPolicy.stop()
        cancelAutomaticReconnect()
        cancelSSHSetup()
        stopFileTransfers()
        client.disconnect()
        sessionState = .disconnected
    }

    // MARK: - Modifiers & Sticky Keys (Screens 3-State Logic)

    public func cycleCmd() {
        guard !isObserveOnly else { return }
        switch cmdState {
        case .inactive:
            cmdState = .activeOnce
            client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
        case .activeOnce:
            cmdState = .locked
            // Already down
        case .locked:
            cmdState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        }
    }

    public func cycleOption() {
        guard !isObserveOnly else { return }
        switch optState {
        case .inactive:
            optState = .activeOnce
            client.sendKeyEvent(down: true, keySym: MacKeyMap.optionLeft)
        case .activeOnce:
            optState = .locked
        case .locked:
            optState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.optionLeft)
        }
    }

    public func cycleControl() {
        guard !isObserveOnly else { return }
        switch ctrlState {
        case .inactive:
            ctrlState = .activeOnce
            client.sendKeyEvent(down: true, keySym: MacKeyMap.controlLeft)
        case .activeOnce:
            ctrlState = .locked
        case .locked:
            ctrlState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.controlLeft)
        }
    }

    public func cycleShift() {
        guard !isObserveOnly else { return }
        switch shiftState {
        case .inactive:
            shiftState = .activeOnce
            client.sendKeyEvent(down: true, keySym: MacKeyMap.shiftLeft)
        case .activeOnce:
            shiftState = .locked
        case .locked:
            shiftState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.shiftLeft)
        }
    }

    public func toggleCmd() { cycleCmd() }
    public func toggleOption() { cycleOption() }
    public func toggleControl() { cycleControl() }
    public func toggleShift() { cycleShift() }

    /// Release single-use modifiers after a keystroke or completed mouse action
    private func releaseActiveOnceModifiers(matching snapshot: OnceModifierSnapshot? = nil) {
        // A mouse-up or key-up must not overtake an already scheduled modified wheel.
        guard pendingModifierWheels == 0 else { return }
        if cmdState == .activeOnce && (snapshot == nil || snapshot?.cmd == cmdGeneration) {
            cmdState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        }
        if optState == .activeOnce && (snapshot == nil || snapshot?.opt == optGeneration) {
            optState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.optionLeft)
        }
        if ctrlState == .activeOnce && (snapshot == nil || snapshot?.ctrl == ctrlGeneration) {
            ctrlState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.controlLeft)
        }
        if shiftState == .activeOnce && (snapshot == nil || snapshot?.shift == shiftGeneration) {
            shiftState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.shiftLeft)
        }
    }

    /// Reset all sticky modifiers to released state
    public func releaseAllModifiers() {
        if cmdState != .inactive {
            cmdState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        }
        if optState != .inactive {
            optState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.optionLeft)
        }
        if ctrlState != .inactive {
            ctrlState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.controlLeft)
        }
        if shiftState != .inactive {
            shiftState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.shiftLeft)
        }
    }

    public var canSendRemoteCommands: Bool {
        isForegroundSession && !isObserveOnly && client.state == .connected
    }

    /// Send a single key tap (down + up)
    public func sendKeyTap(_ keySym: UInt32) {
        guard canSendRemoteCommands else { return }
        client.sendKeyEvent(down: true, keySym: keySym)
        let generation = inputGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.inputGeneration == generation else { return }
            self.client.sendKeyEvent(down: false, keySym: keySym)
            self.releaseActiveOnceModifiers()
        }
    }

    /// Repeated downs belong to one held key; consume Once modifiers only on release.
    public func repeatToolbarKey(_ keySym: UInt32) {
        guard isForegroundSession, !isObserveOnly, isKeyboardVisible,
              sessionState == .connected || client.state == .connected else { return }
        toolbarHeldKeys.insert(keySym)
        client.sendKeyEvent(down: true, keySym: keySym)
    }

    public func releaseToolbarKey(_ keySym: UInt32) {
        guard toolbarHeldKeys.remove(keySym) != nil else { return }
        client.sendKeyEvent(down: false, keySym: keySym)
        if toolbarHeldKeys.isEmpty { releaseActiveOnceModifiers() }
    }

    private func releaseToolbarHeldKeys() {
        guard !toolbarHeldKeys.isEmpty else { return }
        for key in toolbarHeldKeys.sorted() { client.sendKeyEvent(down: false, keySym: key) }
        toolbarHeldKeys.removeAll()
        releaseActiveOnceModifiers()
    }

    /// Send a text character
    public func sendCharacter(_ char: Character) {
        if let sym = MacKeyMap.keySym(for: char) {
            sendKeyTap(sym)
        }
    }

    /// Send arbitrary text string cleanly to remote Mac
    public func sendTextString(_ text: String) {
        guard canSendRemoteCommands else { return }
        client.sendText(text)
        releaseActiveOnceModifiers()
    }

    /// Editing commands use the remote clipboard and preserve an already locked Cmd.
    public func sendCommandShortcut(_ character: Character) {
        guard !isObserveOnly, isForegroundSession, client.state == .connected,
              let key = MacKeyMap.keySym(for: character) else { return }
        let introducedCommand = !isCmdActive
        if introducedCommand { client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft) }
        client.sendKeyEvent(down: true, keySym: key)
        client.sendKeyEvent(down: false, keySym: key)
        if introducedCommand { client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft) }
        releaseActiveOnceModifiers()
    }

    /// Execute a predefined Mac shortcut
    public func executeShortcut(_ shortcut: MacKeyMap.MacShortcut) {
        guard canSendRemoteCommands else { return }
        let sequence = shortcut.keySequence
        for item in sequence {
            client.sendKeyEvent(down: item.down, keySym: item.key)
        }
        releaseActiveOnceModifiers()
    }

    private var shouldReduceMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }

    /// Local fullscreen controls remain available in Observe mode.
    public func toggleFullscreen() {
        trackpadEngine.releaseAllButtons()
        // Publish the layout before rebuilding native input. SwiftUI can rebuild
        // synchronously when its identity changes, so it must see the new value.
        withAnimation(shouldReduceMotion ? nil : .easeInOut(duration: 0.18)) {
            isFullscreen.toggle()
            inputGeneration = UUID()
        }
    }

    public func handleThreeFingerSwipe(_ direction: MacKeyMap.ThreeFingerSwipe) {
        guard !isObserveOnly, client.state == .connected else { return }
        trackpadEngine.releaseAllButtons()
        // Sticky modifiers must not turn a standard Control-arrow into another shortcut.
        releaseAllModifiers()
        executeShortcut(direction.shortcut)
    }

    /// Double-tap toggles fit and one remote pixel per local display pixel.
    public func handleDoubleTapZoom() {
        withAnimation(shouldReduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            if zoomScale > 1.1 {
                zoomScale = 1.0
                viewOffset = .zero
            } else {
                zoomScale = actualSizeZoomScale
            }
        }
        triggerHaptic()
    }

    /// Insert local clipboard text into the focused remote field. Apple Screen Sharing
    /// does not accept legacy ClientCutText in the tested account session.
    public func syncClipboardToMac() {
        guard !isObserveOnly else { return }
        if let string = clipboardReader() { sendTextString(string) }
    }

    /// Explicit clipboard transfer, distinct from inserting text as key events.
    public func sendLocalClipboardToRemote() {
        guard !isObserveOnly, isForegroundSession, client.state == .connected else {
            clipboardTransferNotice = "Clipboard transfer requires an active control session."
            return
        }
        guard let text = clipboardReader() else {
            clipboardTransferNotice = "The local clipboard contains no plain text."
            return
        }
        clipboardTransferNotice = client.sendCutText(text)
            ? "Clipboard transfer requested. Paste on the remote computer to check."
            : "Clipboard transfer is unavailable for this text. Use Paste Text instead."
    }

    /// Trigger tactile haptic feedback on iOS devices
    public func triggerHaptic() {
        #if canImport(UIKit)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }

    private func resetPendingModifierWheels() {
        pendingModifierWheels = 0
        modifierWheelGeneration = UUID()
    }

    /// Direct pointer event for macOS native mouse tracking or iPad trackpad
    public func sendNativePointer(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) {
        guard !isObserveOnly, !isPanningViewport, isForegroundSession, client.state == .connected else {
            pointerButtonsForModifiers = []
            return
        }
        let buttons = buttonMask.intersection([.left, .middle, .right])
        let completedClickOrDrag = !pointerButtonsForModifiers.isEmpty && buttons.isEmpty
        pointerButtonsForModifiers = buttons
        let (tx, ty) = multiDisplayManager.translateCoordinates(
            x: CGFloat(x),
            y: CGFloat(y),
            remoteTotalWidth: CGFloat(client.framebuffer.width),
            remoteTotalHeight: CGFloat(client.framebuffer.height)
        )
        pointerUpdates.send(CGPoint(x: Int(tx), y: Int(ty)))
        let snapshot = onceModifierSnapshot
        if buttonMask.rawValue & 0x78 != 0, !snapshot.isEmpty {
            let generation = inputGeneration
            let wheelGeneration = modifierWheelGeneration
            pendingModifierWheels += 1
            client.sendPointerEvent(buttonMask: buttonMask, x: tx, y: ty) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.inputGeneration == generation,
                          self.modifierWheelGeneration == wheelGeneration else { return }
                    self.pendingModifierWheels = max(0, self.pendingModifierWheels - 1)
                    guard self.pointerButtonsForModifiers.isEmpty else { return }
                    self.releaseActiveOnceModifiers(matching: snapshot)
                }
            }
        } else {
            client.sendPointerEvent(buttonMask: buttonMask, x: tx, y: ty)
        }
        // Hover must retain a pending modifier; dragging retains it until all
        // buttons are up. Queue the key release after the final pointer release.
        if completedClickOrDrag { releaseActiveOnceModifiers() }
    }

    /// Direct key event for macOS native keyboard passthrough
    public func sendNativeKey(down: Bool, keySym: UInt32) {
        client.sendKeyEvent(down: down, keySym: keySym)
    }
}

private final class SessionCallbackGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    func capture() -> UUID { lock.lock(); defer { lock.unlock() }; return value }
    func matches(_ generation: UUID) -> Bool { capture() == generation }
    func scheduleFrame(gate: FrameUpdateGate) -> UUID? {
        lock.lock(); defer { lock.unlock() }
        return gate.enqueue(generation: value) ? value : nil
    }
    @discardableResult
    func advance(frameGate: FrameUpdateGate? = nil) -> UUID {
        lock.lock(); defer { lock.unlock() }
        value = UUID()
        frameGate?.begin(generation: value)
        return value
    }
}
