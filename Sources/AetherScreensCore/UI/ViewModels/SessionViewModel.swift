import Foundation
import SwiftUI
import CoreGraphics
import Combine
import AetherScreensSSH

#if canImport(UIKit)
import UIKit
#endif

/// Manages a live remote screen sharing session with a Mac.
@MainActor
public final class SessionViewModel: ObservableObject, Identifiable {
    public let device: RemoteDevice
    public nonisolated var id: UUID { device.id }
    public let client: RFBClient
    public let trackpadEngine: TrackpadEngine
    public let externalDisplayMirror = RemoteDisplayMirror()
    public let curtainManager: CurtainModeManager
    @Published public private(set) var curtainStatus = RFBCurtainStatus.disconnected
    private let curtainRecoveryStore: CurtainRecoveryStore
    private var curtainRecoveryAccount: String?
    private var curtainRecoveryObservation: AnyCancellable?
    @Published private var rememberedCurtainRecovery = false
    private var hasCurtainRecoveryWarning: Bool {
        curtainStatus.recoveryUnconfirmed || rememberedCurtainRecovery
    }

    public var canChangeCurtain: Bool {
        sessionState == .connected && !isEndingSession && curtainStatus.canRequest && !curtainStatus.isPending &&
            (!isObserveOnly || curtainStatus.needsRestoration || hasCurtainRecoveryWarning)
    }

    public var curtainActionTitle: String {
        curtainStatus.needsRestoration || hasCurtainRecoveryWarning
            ? "Restore Remote Console" : "Hide Remote Console"
    }

    public var curtainStatusMessage: String? {
        if curtainStatus.phase == .hiding { return "Hiding remote console…" }
        if curtainStatus.phase == .restoring { return "Restoring remote console…" }
        if hasCurtainRecoveryWarning { return "Remote console restoration is unconfirmed. Check the Mac before leaving it unattended." }
        switch curtainStatus.phase {
        case .hiding: return "Hiding remote console…"
        case .hidden: return "Remote console hidden. Check the Mac’s display before relying on privacy."
        case .restoring: return "Restoring remote console…"
        case .timedOut: return "The remote console change timed out. Its state is unconfirmed."
        case .failed: return "The remote console change failed. Its state is unconfirmed."
        case .unknown: return "Remote console visibility is unconfirmed."
        default: return nil
        }
    }

    public func changeCurtain() {
        guard canChangeCurtain else { return }
        triggerHaptic()
        client.setAppleCurtain(hidden: !curtainStatus.needsRestoration && !hasCurtainRecoveryWarning)
    }
    public let multiDisplayManager: MultiDisplayManager
    public let metrics: PerformanceMetrics
    public let metalRenderer: MetalScreenRenderer?
    private let liveActivitySessionID = UUID()
    private let thumbnailStore: ThumbnailStore

    @Published public var sessionState: RFBClient.State = .disconnected
    @Published public var currentImage: CGImage?
    @Published public var hasReceivedFirstFrame: Bool = false
    @Published public var downloadProgress: (current: Double, total: Double)? = nil
    @Published public private(set) var cursorSpeed: Double = 1
    @Published public var inputMode: TrackpadEngine.Mode = .trackpad {
        didSet {
            trackpadEngine.releaseAllButtons()
            trackpadEngine.mode = inputMode
        }
    }
    @Published public var isObserveOnly = false {
        didSet {
            releaseAllModifiers()
            trackpadEngine.releaseAllButtons()
            if isObserveOnly { isKeyboardVisible = false; clipboardPasteError = nil }
            refreshInputGate()
            inputGeneration = UUID()
            refreshClipboardMonitoring()
        }
    }
    @Published public var isKeyboardVisible: Bool = false {
        didSet { if !isKeyboardVisible { cancelToolbarKeyHold() } }
    }
    @Published public private(set) var isTypingUserPassword = false
    @Published public var userPasswordError: String?
    private let userPasswordReader: @MainActor @Sendable (RemoteDevice) -> String?
    private let userPasswordAuthentication: @MainActor @Sendable () async -> Bool
    private var userPasswordTask: Task<Void, Never>?
    private var userPasswordToken: UUID?
    private var hardwareKeyboardMapping = HardwareKeyboardMapping()
    private var toolbarKeyHold: (key: UInt32, token: UUID, began: Bool)?
    private var toolbarKeyRepeatTask: Task<Void, Never>?
    @Published public var showShortcutsMenu: Bool = false
    @Published public var showDisplaysMenu: Bool = false
    @Published public var isTextInputBarVisible: Bool = false
    @Published public var textInputBuffer: String = ""
    @Published public var clipboardPasteError: String?
    @Published public var displaySelectionError: String?
    @Published public private(set) var sharedClipboardEnabled = true
    @Published public private(set) var imageCompression: RemoteImageCompressionPolicy
    @Published public private(set) var pendingImageScale: Double?
    @Published public var imageCompressionError: String?
    private var lastAppleDisplayLayout: RFBAppleDisplayLayout?
    private var failedImageScale: Double?
    private let clipboardReader: @MainActor @Sendable () -> [RFBClipboardFlavor]
    private let clipboardAsyncReader: (@MainActor @Sendable () async -> [RFBClipboardFlavor]?)?
    private var clipboardReadTask: Task<Void, Never>?
    private var clipboardReadID = UUID()
    private let clipboardCountReader: @MainActor @Sendable () -> Int
    private var observedClipboardCount: Int?
    private var clipboardMonitor: Task<Void, Never>?
    private var manualClipboardRequest = false
    @Published private var applicationInputActive = true
    @Published private var clipboardApplicationActive = true
    private var clipboardLifecycleObservers = Set<AnyCancellable>()
    private nonisolated let clipboardGeneration = SessionCallbackGeneration()

    // 3-State Modifiers (Screens Sticky Keys)
    public enum ModifierState: Equatable, Sendable {
        case inactive
        case activeOnce // active for next key press only
        case locked     // double-tapped, stays active indefinitely
    }

    @Published public var cmdState: ModifierState = .inactive
    @Published public var optState: ModifierState = .inactive
    @Published public var ctrlState: ModifierState = .inactive
    @Published public var shiftState: ModifierState = .inactive

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
            if isPanningViewport { trackpadEngine.releaseAllButtons() }
            client.setPointerInputEnabled(!isPanningViewport)
        }
    }
    @Published public private(set) var inputGeneration = UUID()
    private var frameCountSinceLastSnapshot: Int = 0
    @Published private var lastFramebufferSize = CGSize.zero

    public let isTemporary: Bool
    @Published public var keyboardConfiguration: KeyboardToolbarConfiguration {
        didSet {
            // A hidden sticky key must never leave the remote modifier held.
            if keyboardConfiguration.items != oldValue.items { releaseAllModifiers() }
            if keyboardConfiguration.hardwareKeyboard != oldValue.hardwareKeyboard { cancelToolbarKeyHold() }
            if !isTemporary && !applyingKeyboardPreference { keyboardStore.save(keyboardConfiguration, for: device.id) }
        }
    }
    private let keyboardStore: KeyboardToolbarStore
    private var applyingKeyboardPreference = false
    private var keyboardPreferenceObserver: AnyCancellable?
    private var lastKeyboardPreferenceData: Data?
    private let clipboardWriter: @MainActor @Sendable (String) -> Void
    private let clipboardFlavorsWriter: (@MainActor @Sendable ([RFBClipboardFlavor]) -> Void)?
    public var canRememberPassword: Bool { !isTemporary }
    private let deviceStore: DeviceStore
    private nonisolated let callbackGeneration = SessionCallbackGeneration()
    private nonisolated let foregroundGeneration = SessionCallbackGeneration()
    @Published public private(set) var isForegroundSession = true
    private var isEndingSession = false
    private var selectedApplicationInputActive: Bool {
        applicationInputActive && isForegroundSession && !isEndingSession
    }
    // Sticky state also works before a connection exists; transport availability
    // is checked separately by actions that require a live session.
    private var controlInputAllowed: Bool {
        selectedApplicationInputActive && !isObserveOnly
    }
    public struct SSHTrustRequest: Identifiable {
        public let id: UUID
        public let configuration: SSHConfiguration
        public let identity: SSHHostKeyIdentity
    }
    @Published public private(set) var sshTrustRequest: SSHTrustRequest?
    private let sshCoordinator: SSHSessionCoordinator
    private let transientSSHCredentials: SSHSessionCredentials?
    private var sshTask: Task<Void, Never>?
    private var sshAttempt = UUID()
    private var sshTrustContinuation: CheckedContinuation<SSHSessionCoordinator.TrustDecision, Never>?

    public init(device: RemoteDevice, password: String?, isTemporary: Bool = false,
                deviceStore: DeviceStore = .shared, keyboardStore: KeyboardToolbarStore = .shared,
                clipboardWriter: (@MainActor @Sendable (String) -> Void)? = nil,
                clipboardFlavorsWriter: (@MainActor @Sendable ([RFBClipboardFlavor]) -> Void)? = nil,
                clipboardReader: (@MainActor @Sendable () -> [RFBClipboardFlavor])? = nil,
                clipboardAsyncReader: (@MainActor @Sendable () async -> [RFBClipboardFlavor]?)? = nil,
                clipboardCountReader: (@MainActor @Sendable () -> Int)? = nil,
                userPasswordReader: (@MainActor @Sendable (RemoteDevice) -> String?)? = nil,
                userPasswordAuthentication: (@MainActor @Sendable () async -> Bool)? = nil,
                sshCredentials: SSHSessionCredentials? = nil,
                sshKeychain: SSHKeychainStore = .shared,
                thumbnailStore: ThumbnailStore = .shared,
                curtainRecoveryStore: CurtainRecoveryStore = .shared) {
        self.thumbnailStore = thumbnailStore
        self.curtainRecoveryStore = curtainRecoveryStore
        self.curtainRecoveryAccount = device.username
        self._rememberedCurtainRecovery = Published(initialValue: curtainRecoveryStore.hasUnresolved(for: .init(device: device, account: device.username)))
        self.sshCoordinator = SSHSessionCoordinator(store: sshKeychain)
        self.transientSSHCredentials = sshCredentials
        self.userPasswordReader = userPasswordReader ?? { deviceStore.getPassword(for: $0) }
        self.userPasswordAuthentication = userPasswordAuthentication ?? { await UserPasswordAuthentication.authenticate() }
        self.sharedClipboardEnabled = device.effectiveSharedClipboard
        self.imageCompression = device.effectiveImageCompression
        self.clipboardReader = clipboardReader ?? { SystemClipboard.read() }
        #if canImport(UIKit)
        self.clipboardAsyncReader = clipboardAsyncReader ?? (clipboardReader == nil ? { await SystemClipboard.readAsync() } : nil)
        #else
        self.clipboardAsyncReader = clipboardAsyncReader
        #endif
        self.clipboardCountReader = clipboardCountReader ?? { SystemClipboard.changeCount }
        self.device = device
        self.isTemporary = isTemporary
        self.deviceStore = deviceStore
        self.keyboardStore = keyboardStore
        self.lastKeyboardPreferenceData = keyboardStore.savedData(for: device.id)
        self.clipboardWriter = clipboardWriter ?? { text in
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
        }
        if let clipboardFlavorsWriter {
            self.clipboardFlavorsWriter = clipboardFlavorsWriter
        } else if clipboardWriter == nil {
            self.clipboardFlavorsWriter = { items in _ = SystemClipboard.write(items) }
        } else {
            self.clipboardFlavorsWriter = nil
        }
        self.keyboardConfiguration = isTemporary ? KeyboardToolbarConfiguration() : keyboardStore.load(for: device.id)
        let rfb = RFBClient(
            host: device.host,
            port: device.port,
            password: password,
            username: device.username,
            automaticClipboard: device.effectiveSharedClipboard,
            automaticFramebufferUpdates: true
        )
        self.client = rfb
        self.trackpadEngine = TrackpadEngine(remoteWidth: 1920, remoteHeight: 1080)
        self.cursorSpeed = device.effectiveCursorSpeed
        self.trackpadEngine.cursorSpeedMultiplier = CGFloat(device.effectiveCursorSpeed)
        self.curtainManager = CurtainModeManager()
        self.multiDisplayManager = MultiDisplayManager(preferredDisplayID: device.preferredDisplayID)
        self.metrics = PerformanceMetrics()

        let renderer = MetalScreenRenderer(metrics: self.metrics)
        renderer?.framebuffer = rfb.framebuffer
        self.metalRenderer = renderer

        observedClipboardCount = self.clipboardCountReader()
        setupBindings()
    }

    private func setupBindings() {
        if !isTemporary {
            keyboardPreferenceObserver = NotificationCenter.default.publisher(for: DevicePreferenceStorage.didChange)
                .filter { [keyboardStore] in ($0.object as? UserDefaults) === keyboardStore.synchronizationDefaults }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, !self.isEndingSession else { return }
                    let data = self.keyboardStore.savedData(for: self.device.id)
                    guard data != self.lastKeyboardPreferenceData else { return }
                    self.lastKeyboardPreferenceData = data
                    let configuration = self.keyboardStore.load(for: self.device.id)
                    guard configuration != self.keyboardConfiguration else { return }
                    self.applyingKeyboardPreference = true
                    self.keyboardConfiguration = configuration
                    self.applyingKeyboardPreference = false
                }
        }
        #if canImport(UIKit)
        let applicationActive = UIApplication.shared.applicationState == .active
        applicationInputActive = applicationActive
        clipboardApplicationActive = applicationActive
        refreshInputGate()
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.enterApplicationBackground() }
            }.store(in: &clipboardLifecycleObservers)
        // Biometric UI may temporarily resign activity without backgrounding.
        // Keep its authentication request alive while clipboard access pauses.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.setClipboardApplicationActive(false) }
            }.store(in: &clipboardLifecycleObservers)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    SessionLiveActivityController.shared.applicationWillEnterForeground()
                    self?.setApplicationInputActive(true)
                    self?.setClipboardApplicationActive(true)
                }
            }.store(in: &clipboardLifecycleObservers)
        #endif
        // Handle pointer events from trackpad engine
        // This callback may run off the main actor. Synchronized transport gates
        // enforce application, selected-session, Observe, and Pan input state.
        trackpadEngine.onPointerEvent = { [weak self] mask, x, y in
            guard let self = self else { return }
            let (tx, ty) = self.multiDisplayManager.translateCoordinates(
                x: CGFloat(x),
                y: CGFloat(y),
                remoteTotalWidth: CGFloat(self.client.framebuffer.width),
                remoteTotalHeight: CGFloat(self.client.framebuffer.height)
            )
            self.client.sendPointerEvent(buttonMask: mask, x: tx, y: ty)
        }

        // Preserve the existing Lock Remote Mac shortcut and local notice.
        curtainManager.onCurtainStateChanged = { [weak self] isActive in
            Task { @MainActor in
                guard let self = self else { return }
                if isActive {
                    // Send Lock Screen shortcut (Ctrl + Cmd + Q)
                    self.executeShortcut(.lockScreen)
                }
            }
        }

        let recoveryStore = curtainRecoveryStore
        let recoveryDevice = device
        let curtainTransport = client
        client.curtainRecoveryProvider = { account in
            recoveryStore.hasUnresolved(for: .init(device: recoveryDevice, account: account))
        }
        client.onAppleCurtainStateChanged = { [weak self, weak curtainTransport] status in
            guard let curtainTransport else { return }
            let event = curtainTransport.curtainEvent
            guard event.status == status else { return }
            // The close transaction owns the transport, not the dismissed VM.
            // Bind/record under the transport lock before queuing any UI work.
            recoveryStore.record(event, device: recoveryDevice)
            let revision = event.revision
            let account = event.account
            let sourceID = event.sourceID
            Task { @MainActor [weak self, weak curtainTransport] in
                // The status carries transport identity; accept terminal recovery
                // warnings even while the ordinary session callbacks are retired.
                guard let self, let curtainTransport else { return }
                let current = curtainTransport.curtainEvent
                guard current.revision == revision, current.status == status, current.account == account else { return }
                self.curtainRecoveryAccount = account
                self.rememberedCurtainRecovery = recoveryStore.hasRecoveryWarning(for: .init(device: recoveryDevice, account: account), currentSource: sourceID)
                self.curtainStatus = status
            }
        }
        curtainRecoveryObservation = recoveryStore.$revision.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rememberedCurtainRecovery = recoveryStore.hasRecoveryWarning(for: .init(device: recoveryDevice, account: self.curtainRecoveryAccount), currentSource: self.client.curtainEvent.sourceID)
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
        multiDisplayManager.onNativeDisplaySelection = { [weak self] id in
            self?.client.selectAppleDisplay(id: id) ?? false
        }
        client.onAppleDisplayLayoutReceived = { [weak self] layout in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation), !self.isEndingSession,
                      self.client.currentAppleDisplayLayout == layout else { return }
                if self.lastAppleDisplayLayout?.hasSameFramebufferLayout(as: layout) == true,
                   self.multiDisplayManager.selectedDisplayId == (layout.selectedDisplayID.map { Int($0) + 1 } ?? 0) {
                    // A Curtain visibility report with an already synchronized
                    // selection preserves the frame, viewport and held input.
                    self.lastAppleDisplayLayout = layout
                    return
                }
                let preserveViewport = self.lastAppleDisplayLayout.map { previous in
                    previous.selectedDisplayID == layout.selectedDisplayID &&
                    previous.screens.count == layout.screens.count &&
                    zip(previous.screens, layout.screens).allSatisfy {
                        $0.id == $1.id && $0.logicalBounds == $1.logicalBounds &&
                        $0.nativeDensity == $1.nativeDensity
                    }
                } ?? false
                self.lastAppleDisplayLayout = layout
                self.multiDisplayManager.updateFromAppleLayout(layout)
                self.applyDisplaySelection(resetInput: true, preservingViewport: preserveViewport)
            }
        }
        client.onAppleServerScalingFinished = { [weak self] factor, confirmed in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation), !self.isEndingSession,
                      self.pendingImageScale == factor else { return }
                self.pendingImageScale = nil
                self.failedImageScale = confirmed ? nil : factor
                self.imageCompressionError = confirmed ? nil : "The image compression change was not confirmed. Try again."
            }
        }
        client.onAppleDisplaySelectionFinished = { [weak self] id, confirmed in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation), !self.isEndingSession else { return }
                guard self.multiDisplayManager.finishNativeSelection(id: id) else { return }
                self.displaySelectionError = confirmed ? nil : "The display switch was not confirmed. Try again."
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
            // Invalidate at wire-notification time, before a newer clipboard
            // callback captures its token. Queued handshake UI work must not
            // invalidate content received after the connection became ready.
            if state != .connected { self.clipboardGeneration.advance() }
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation), self.client.state == state else { return }
                guard !self.isEndingSession || state == .disconnected else { return }
                self.sessionState = state
                switch state {
                case .connected:
                    if self.applicationInputActive {
                        SessionLiveActivityController.shared.sessionConnected(sessionID: self.liveActivitySessionID)
                    }
                case .failed:
                    SessionLiveActivityController.shared.sessionEnded(sessionID: self.liveActivitySessionID, reason: .failed)
                case .disconnected:
                    SessionLiveActivityController.shared.sessionEnded(sessionID: self.liveActivitySessionID)
                default: break
                }
                self.externalDisplayMirror.updatePresentationAllowed(state == .connected && self.hasReceivedFirstFrame && self.isForegroundSession)
                if state != .connected {
                    self.manualClipboardRequest = false
                }
                self.refreshClipboardMonitoring()
                if state == .disconnected { self.metrics.reset() }
                switch state {
                case .disconnected, .failed:
                    if self.device.sshConfiguration != nil && !self.isEndingSession { self.stopSSHConnection() }
                default: break
                }
                if case .failed = state {
                    self.metrics.reset()
                    self.releaseAllModifiers()
                    self.trackpadEngine.releaseAllButtons()
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
                self.requiresMacAccountPrompt = true
                self.passwordPromptError = nil
                self.isPromptingPassword = true
            }
        }

        let sessionMetrics = metrics
        client.onBytesReceived = { count in sessionMetrics.recordBytesReceived(count) }
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
                guard !self.isEndingSession, !self.hasReceivedFirstFrame else { return }
                self.downloadProgress = (current, total)
            }
        }

        // Handle incoming screen frame updates
        let renderer = metalRenderer
        client.onFrameUpdated = { [weak self] in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            renderer?.notifyFrameUpdated()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
                guard !self.isEndingSession else { return }
                if !self.hasReceivedFirstFrame { self.hasReceivedFirstFrame = true }
                self.externalDisplayMirror.updatePresentationAllowed(self.client.state == .connected && self.isForegroundSession)
                self.externalDisplayMirror.notifyFrameUpdated()
                if self.downloadProgress != nil { self.downloadProgress = nil }
                if self.metalRenderer == nil {
                    self.currentImage = self.client.framebuffer.makeCGImage()
                }

                let w = self.client.framebuffer.width
                let h = self.client.framebuffer.height
                let size = CGSize(width: w, height: h)
                if self.lastFramebufferSize != size {
                    self.lastFramebufferSize = size
                    if self.activeCropRect == nil &&
                        (self.trackpadEngine.remoteWidth != CGFloat(w) || self.trackpadEngine.remoteHeight != CGFloat(h)) {
                        self.trackpadEngine.remoteWidth = CGFloat(w)
                        self.trackpadEngine.remoteHeight = CGFloat(h)
                        self.trackpadEngine.resetCursor()
                    }
                    self.multiDisplayManager.updateFromFramebuffer(width: w, height: h)
                }
                self.applyImageCompression()

                // Periodically save thumbnail for device list view
                self.frameCountSinceLastSnapshot += 1
                if !self.isTemporary && (self.frameCountSinceLastSnapshot == 5 || self.frameCountSinceLastSnapshot % 60 == 0) {
                    let framebuffer = self.client.framebuffer
                    let deviceId = self.device.id
                    let thumbnailStore = self.thumbnailStore
                    DispatchQueue.global(qos: .utility).async {
                        if let image = framebuffer.makeCGImage() {
                            thumbnailStore.saveThumbnail(image, for: deviceId)
                        }
                    }
                }
            }
        }

        if clipboardFlavorsWriter != nil {
            client.onClipboardFlavorsReceived = { [weak self] items in
                guard let self else { return }
                let generation = self.callbackGeneration.capture()
                let foreground = self.foregroundGeneration.capture()
                let clipboard = self.clipboardGeneration.capture()
                Task { @MainActor [weak self] in
                    #if DEBUG
                    if let self, ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] == "1" {
                        AppLogger.shared.info("QA clipboard receive: callback=\(self.callbackGeneration.matches(generation)), foreground=\(self.foregroundGeneration.matches(foreground)), selected=\(self.isForegroundSession), clipboard=\(self.clipboardGeneration.matches(clipboard)), eligible=\(self.canGetClipboard), flavors=\(items.count)", category: "RFB")
                    }
                    #endif
                    guard let self, self.callbackGeneration.matches(generation),
                          self.foregroundGeneration.matches(foreground), self.isForegroundSession,
                          !self.isEndingSession, self.client.state == .connected,
                          self.canGetClipboard, self.clipboardGeneration.matches(clipboard),
                          self.sharedClipboardEnabled || self.manualClipboardRequest else { return }
                    self.manualClipboardRequest = false
                    self.clipboardFlavorsWriter?(items)
                    self.observedClipboardCount = self.clipboardCountReader()
                }
            }
        }

        // Handle incoming clipboard text
        client.onClipboardReceived = { [weak self] text in
            guard let self else { return }
            let generation = self.callbackGeneration.capture()
            let foreground = self.foregroundGeneration.capture()
            let clipboard = self.clipboardGeneration.capture()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation),
                      self.foregroundGeneration.matches(foreground), self.isForegroundSession,
                      !self.isEndingSession, self.client.state == .connected,
                      self.canGetClipboard, self.clipboardGeneration.matches(clipboard),
                      self.sharedClipboardEnabled || self.manualClipboardRequest else { return }
                self.manualClipboardRequest = false
                self.clipboardWriter(text)
                self.observedClipboardCount = self.clipboardCountReader()
            }
        }
    }

    /// Explicit selection is persisted; server layout changes never overwrite it.
    public func selectDisplay(id: Int) {
        guard multiDisplayManager.availableDisplays.contains(where: { $0.id == id }) else { return }
        guard multiDisplayManager.selectDisplay(id: id) else {
            displaySelectionError = "The display switch was not confirmed. Try again."
            return
        }
        displaySelectionError = nil
        if !isTemporary {
            deviceStore.updatePreferredDisplay(id == 0 ? nil : UInt32(exactly: id - 1), for: device)
        }
    }

    private func applyDisplaySelection(resetInput: Bool = false, preservingViewport: Bool = false) {
        let crop = multiDisplayManager.selectedViewportCropRect
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
        let oldWidth = trackpadEngine.remoteWidth, oldHeight = trackpadEngine.remoteHeight
        let cursor = CGPoint(x: trackpadEngine.cursorX / max(1, oldWidth) * width,
                             y: trackpadEngine.cursorY / max(1, oldHeight) * height)
        activeCropRect = crop
        trackpadEngine.remoteWidth = width
        trackpadEngine.remoteHeight = height
        if preservingViewport {
            trackpadEngine.moveCursor(to: cursor)
            return
        }
        zoomScale = 1
        viewOffset = .zero
        isPanningViewport = false
        if client.state == .connected { trackpadEngine.resetCursor() }
    }

    public var canChangeImageCompression: Bool {
        sessionState == .connected && client.currentAppleDisplayLayout != nil &&
        multiDisplayManager.pendingDisplayId == nil && pendingImageScale == nil
    }

    public func setImageCompression(_ policy: RemoteImageCompressionPolicy) {
        imageCompression = policy
        failedImageScale = nil
        imageCompressionError = nil
        if !isTemporary { deviceStore.updateImageCompression(policy, for: device) }
        applyImageCompression()
    }

    private func applyImageCompression() {
        guard !isEndingSession, hasReceivedFirstFrame, canChangeImageCompression,
              let layout = client.currentAppleDisplayLayout else { return }
        let factor = imageCompression.factor(isLocalConnection:
            imageCompression == .remoteOnly ? client.isLocalConnection : nil)
        guard failedImageScale != factor,
              !layout.screens.allSatisfy({ abs($0.serverScale - factor) < 0.00001 }) else { return }
        pendingImageScale = factor
        if !client.setAppleServerScaling(factor) { pendingImageScale = nil }
    }

    /// Keep the connection and viewport, but only the selected session may control input or clipboard.
    public func setForegroundSession(_ foreground: Bool) {
        guard foreground != isForegroundSession else { return }
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        foregroundGeneration.advance()
        inputGeneration = UUID()
        isForegroundSession = foreground
        externalDisplayMirror.updatePresentationAllowed(foreground && client.state == .connected && hasReceivedFirstFrame)
        if !foreground {
            cancelPendingSSHConnection()
            clipboardPasteError = nil
            isKeyboardVisible = false
            isTextInputBarVisible = false
        }
        refreshInputGate()
        // Background clipboard callbacks are discarded. Fetch the current Apple
        // pasteboard when selected so a copy made while hidden is not lost.
        manualClipboardRequest = false
        refreshClipboardMonitoring()
        if foreground && sharedClipboardEnabled { client.requestRemoteClipboard() }
    }

    private func refreshInputGate() {
        client.setInputEnabled(controlInputAllowed)
    }

    /// Application activity is independent of which retained session is selected.
    /// Real backgrounding releases every input owner without changing the viewport.
    func setApplicationInputActive(_ active: Bool) {
        guard applicationInputActive != active || !active else { return }
        applicationInputActive = active
        inputGeneration = UUID()
        if !active {
            // Close the transport first: release aggregate held keys and buttons
            // at their last wire position, and invalidate pending wheel work.
            client.setInputEnabled(false)
            releaseAllModifiers()
            trackpadEngine.releaseAllButtons()
            // Repeated background notifications must also cancel a newly pending
            // request, even when the application input gate was already closed.
            cancelPendingSSHConnection()
        } else {
            refreshInputGate()
        }
    }

    /// Only real application backgrounding ends transport ownership. Temporary
    /// inactivity (including biometric authentication) leaves the session intact.
    func enterApplicationBackground() {
        SessionLiveActivityController.shared.applicationDidEnterBackground()
        setApplicationInputActive(false)
        setClipboardApplicationActive(false)
        finishSession(reason: .backgrounded, performConfiguredAction: false, preserveViewport: true)
    }

    /// Submit entered password to active RFB handshake
    public func submitPassword(_ pwd: String, rememberInKeychain: Bool, accountUsername: String? = nil) {
        if let accountContinuation = macAccountContinuation {
            guard let account = accountUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty else { return }
            macAccountContinuation = nil
            if canRememberPassword {
                var updated = device
                updated.username = account
                updated.authMethod = .macAccount
                deviceStore.updateDevice(updated, password: rememberInKeychain ? pwd : nil)
            }
            isPromptingPassword = false
            accountContinuation(account, pwd)
            return
        }
        client.password = pwd
        if rememberInKeychain && canRememberPassword {
            deviceStore.updatePassword(pwd, for: device)
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
    public func cancelPasswordPrompt(disconnect: Bool = true) {
        isPromptingPassword = false
        let cont = passwordContinuation
        passwordContinuation = nil
        cont?(nil)
        let accountContinuation = macAccountContinuation
        macAccountContinuation = nil
        accountContinuation?(nil, nil)
        if disconnect { client.disconnect() }
    }

    /// Move the local viewport without emitting remote pointer events.
    public func panViewport(dx: CGFloat, dy: CGFloat, limitX: CGFloat, limitY: CGFloat) {
        let x = max(-limitX, min(limitX, viewOffset.width))
        let y = max(-limitY, min(limitY, viewOffset.height))
        viewOffset = CGSize(width: max(-limitX, min(limitX, x + dx)),
                            height: max(-limitY, min(limitY, y + dy)))
    }

    /// Connect to remote Mac
    public func startSession() {
        guard !isEndingSession, applicationInputActive else { return }
        SessionLiveActivityController.shared.sessionEnded(sessionID: liveActivitySessionID)
        externalDisplayMirror.updatePresentationAllowed(false)
        if device.sshConfiguration != nil { client.disconnect() }
        let cleanup = stopSSHConnection()
        manualClipboardRequest = false
        clipboardGeneration.advance()
        clipboardMonitor?.cancel()
        clipboardReadTask?.cancel()
        clipboardReadTask = nil
        clipboardMonitor = nil
        observedClipboardCount = clipboardCountReader()
        clipboardPasteError = nil
        callbackGeneration.advance()
        displaySelectionError = nil
        imageCompressionError = nil
        pendingImageScale = nil
        failedImageScale = nil
        lastAppleDisplayLayout = nil
        metrics.reset()
        hasReceivedFirstFrame = false
        downloadProgress = nil
        lastFramebufferSize = .zero
        multiDisplayManager.reset(width: client.framebuffer.width, height: client.framebuffer.height)
        guard let configuration = device.sshConfiguration else { client.connect(); return }
        let attempt = sshAttempt
        sessionState = .connecting
        sshTask = Task { [weak self] in
            await cleanup.value
            guard let self, self.sshAttempt == attempt, !Task.isCancelled else { return }
            do {
                guard self.sshTargetIsCurrent else { throw CancellationError() }
                let tunnel = try await self.sshCoordinator.connect(deviceID: self.device.id,
                    configuration: configuration, destinationPort: self.device.port,
                    credentials: self.transientSSHCredentials, temporary: self.isTemporary) { [weak self] identity in
                        guard let self, self.sshAttempt == attempt, self.sshTargetIsCurrent, self.isForegroundSession else { return .cancel }
                        return await withCheckedContinuation { continuation in
                            self.sshTrustContinuation = continuation
                            self.sshTrustRequest = SSHTrustRequest(id: attempt, configuration: configuration, identity: identity)
                        }
                    }
                guard self.sshAttempt == attempt, !Task.isCancelled, self.sshTargetIsCurrent else {
                    self.sshCoordinator.stop(); return
                }
                self.sshTask = nil
                self.client.connect(using: tunnel)
            } catch {
                guard self.sshAttempt == attempt else { return }
                self.sshTask = nil
                self.sshCoordinator.stop()
                if error is CancellationError {
                    self.sessionState = .disconnected
                } else if case SSHSessionCoordinator.Failure.trustCancelled = error {
                    self.sessionState = .disconnected
                } else {
                    self.sessionState = .failed(AppLocalization.string("SSH connection failed. Check the credentials and trusted host key."))
                }
            }
        }
    }

    private var sshTargetIsCurrent: Bool {
        guard !isEndingSession else { return false }
        if isTemporary { return true }
        guard let current = deviceStore.device(withID: device.id) else { return false }
        return current.host == device.host && current.port == device.port && current.username == device.username &&
            current.sshConfiguration == device.sshConfiguration
    }

    public func submitSSHTrust(id: UUID, decision: SSHSessionCoordinator.TrustDecision) {
        guard sshTrustRequest?.id == id, sshAttempt == id else { return }
        let continuation = sshTrustContinuation
        sshTrustContinuation = nil; sshTrustRequest = nil
        continuation?.resume(returning: sshTargetIsCurrent ? decision : .cancel)
    }

    @discardableResult
    private func stopSSHConnection() -> Task<Void, Never> {
        sshAttempt = UUID()
        sshTask?.cancel(); sshTask = nil
        let continuation = sshTrustContinuation
        sshTrustContinuation = nil; sshTrustRequest = nil
        continuation?.resume(returning: .cancel)
        return sshCoordinator.stop()
    }

    private func cancelPendingSSHConnection() {
        guard sshTask != nil else { return }
        stopSSHConnection()
        sessionState = .disconnected
    }

    /// Reauthenticate without leaving the viewport; also clear held local input.
    public func reconnectSession() {
        guard !isEndingSession else { return }
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        cancelPasswordPrompt()
        inputGeneration = UUID()
        if curtainManager.isCurtainActive { curtainManager.toggleCurtain() }
        startSession()
    }

    /// Disconnect from remote Mac
    public func endSession() {
        finishSession(reason: .ended, performConfiguredAction: true, preserveViewport: false)
    }

    private func finishSession(reason: SessionLiveActivityController.EndReason,
                               performConfiguredAction: Bool, preserveViewport: Bool) {
        SessionLiveActivityController.shared.sessionEnded(sessionID: liveActivitySessionID, reason: reason)
        guard !isEndingSession else { return }
        isEndingSession = true
        externalDisplayMirror.updatePresentationAllowed(false)
        clipboardMonitor?.cancel()
        clipboardReadTask?.cancel()
        clipboardReadTask = nil
        clipboardMonitor = nil
        manualClipboardRequest = false
        clipboardGeneration.advance()
        // Edits also apply to retained sessions. Never apply another address or
        // account's action to this socket, or a deleted record's stale action.
        let configured = isTemporary ? device : deviceStore.device(withID: device.id)
        let matchesTarget = configured?.host == device.host && configured?.port == device.port &&
            configured?.username == client.username && configured?.deviceType == .mac &&
            configured?.sshConfiguration == device.sshConfiguration
        let action = performConfiguredAction && device.deviceType == .mac && matchesTarget && !isObserveOnly && client.state == .connected
            ? configured?.disconnectAction ?? .disconnectOnly : .disconnectOnly
        clipboardPasteError = nil
        callbackGeneration.advance()
        inputGeneration = UUID()
        metrics.reset()
        cancelPasswordPrompt(disconnect: false)
        sessionState = .disconnected
        // Freeze and drain the transport's aggregate ownership before clearing
        // local state; native mouse holds do not belong to TrackpadEngine.
        if client.state == .connected {
            client.disconnect(after: action, display: activeCropRect, allowDisabledInput: true) { [weak self] processed in
                if !processed && action != .disconnectOnly {
                    AppLogger.shared.error("Disconnect action delivery could not be confirmed.", category: "Network")
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.stopSSHConnection()
                    self.callbackGeneration.advance()
                    self.isEndingSession = false
                }
            }
        } else {
            // Pending SSH trust/authentication has no RFB writes to drain.
            // Dismiss its review synchronously so late approval cannot proceed.
            client.disconnect()
            stopSSHConnection()
            isEndingSession = false
        }
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        let framebuffer = client.framebuffer
        let deviceId = device.id
        let thumbnailStore = self.thumbnailStore
        if !isTemporary && !preserveViewport {
            DispatchQueue.global(qos: .utility).async {
                if let image = framebuffer.makeCGImage() {
                    thumbnailStore.saveThumbnail(image, for: deviceId)
                }
            }
        }
        if !preserveViewport { hasReceivedFirstFrame = false }
        downloadProgress = nil
    }

    // MARK: - Modifiers & Sticky Keys (Screens 3-State Logic)

    public func cycleCmd() {
        guard controlInputAllowed else { return }
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
        guard controlInputAllowed else { return }
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
        guard controlInputAllowed else { return }
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
        guard controlInputAllowed else { return }
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

    /// Release any single-use modifiers that were active for just one keystroke
    private func releaseActiveOnceModifiers() {
        if cmdState == .activeOnce {
            cmdState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        }
        if optState == .activeOnce {
            optState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.optionLeft)
        }
        if ctrlState == .activeOnce {
            ctrlState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.controlLeft)
        }
        if shiftState == .activeOnce {
            shiftState = .inactive
            client.sendKeyEvent(down: false, keySym: MacKeyMap.shiftLeft)
        }
    }

    /// Reset all sticky modifiers to released state
    public func releaseAllModifiers() {
        cancelUserPasswordRequest()
        cancelToolbarKeyHold()
        for key in hardwareKeyboardMapping.releaseAll() {
            client.sendKeyEvent(down: false, keySym: key, source: .hardwareKeyboard)
        }
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

    public func setCursorSpeed(_ value: Double) {
        cursorSpeed = RemoteDevice.validatedCursorSpeed(value)
        trackpadEngine.cursorSpeedMultiplier = CGFloat(cursorSpeed)
        if !isTemporary { deviceStore.updateCursorSpeed(cursorSpeed, for: device) }
    }

    public func beginToolbarKeyHold(_ key: UInt32) {
        cancelToolbarKeyHold()
        guard canSendDictation, isKeyboardVisible else { return }
        let token = UUID()
        toolbarKeyHold = (key, token, false)
        let settings = keyboardConfiguration.hardwareKeyboard ?? HardwareKeyboardConfiguration()
        guard settings.repeatEnabled else { return }
        toolbarKeyRepeatTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(settings.validatedDelay)) } catch { return }
            guard let self, self.toolbarKeyHold?.token == token,
                  self.canSendDictation, self.isKeyboardVisible else { return }
            self.toolbarKeyHold?.began = true
            self.client.sendKeyEvent(down: true, keySym: key, source: .toolbarRepeat)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(settings.validatedInterval)) } catch { return }
                guard self.toolbarKeyHold?.token == token, self.canSendDictation, self.isKeyboardVisible else {
                    self.cancelToolbarKeyHold()
                    return
                }
                self.client.sendKeyEvent(down: true, keySym: key, source: .toolbarRepeat)
            }
        }
    }

    public func endToolbarKeyHold(_ key: UInt32, activate: Bool) {
        guard let hold = toolbarKeyHold, hold.key == key else { return }
        cancelToolbarKeyHold()
        if activate && !hold.began && canSendDictation { sendKeyTap(key) }
    }

    public func cancelToolbarKeyHold() {
        toolbarKeyRepeatTask?.cancel()
        toolbarKeyRepeatTask = nil
        guard let hold = toolbarKeyHold else { return }
        toolbarKeyHold = nil
        if hold.began {
            client.sendKeyEvent(down: false, keySym: hold.key, source: .toolbarRepeat)
            releaseActiveOnceModifiers()
        }
    }

    /// Send a single key tap (down + up)
    public func sendKeyTap(_ keySym: UInt32) {
        guard controlInputAllowed else { return }
        client.sendKeyEvent(down: true, keySym: keySym)
        let generation = inputGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.inputGeneration == generation, self.controlInputAllowed else { return }
            self.client.sendKeyEvent(down: false, keySym: keySym)
            self.releaseActiveOnceModifiers()
        }
    }

    /// Send a text character
    public func sendCharacter(_ char: Character) {
        if let sym = MacKeyMap.keySym(for: char) {
            sendKeyTap(sym)
        }
    }

    /// Send arbitrary text string cleanly to remote Mac
    public func sendTextString(_ text: String) {
        guard controlInputAllowed else { return }
        client.sendText(text)
        releaseActiveOnceModifiers()
    }

    /// Committed software-keyboard text and Return are separate remote actions.
    /// The Send button transmits text only; keyboard submission also activates the remote field.
    @discardableResult
    public func submitTextInput(pressReturn: Bool) -> Bool {
        if let diagnostics = InputDiagnostics.enabled {
            var flags: InputDiagnostics.Flags = []
            if isForegroundSession { flags.insert(.foreground) }
            if isObserveOnly { flags.insert(.observeOnly) }
            if !isEndingSession { flags.insert(.notClosing) }
            if sessionState == .connected { flags.insert(.connected) }
            diagnostics.record(canSendDictation ? .textSubmission : .textSubmissionSuppressed,
                               session: client.inputDiagnosticIdentifier, flags: flags)
        }
        guard canSendDictation, pressReturn || !textInputBuffer.isEmpty else { return false }
        if !textInputBuffer.isEmpty { sendTextString(textInputBuffer) }
        textInputBuffer = ""
        if pressReturn { sendKeyTap(MacKeyMap.return) }
        return true
    }

    public var canSendDictation: Bool {
        controlInputAllowed && client.state == .connected
    }

    public func handlePencilGesture(_ gesture: PencilGesture, location: CGPoint? = nil, viewSize: CGSize? = nil) {
        guard selectedApplicationInputActive, client.state == .connected else { return }
        switch keyboardConfiguration.pencilAction(for: gesture) {
        case .none: return
        case .toggleToolbar: isKeyboardVisible.toggle()
        case .secondaryClick, .middleClick:
            guard controlInputAllowed, !isPanningViewport else { return }
            if let location {
                guard let viewSize, location.x.isFinite, location.y.isFinite,
                      viewSize.width.isFinite, viewSize.height.isFinite,
                      viewSize.width > 0, viewSize.height > 0,
                      CGRect(origin: .zero, size: viewSize).contains(location) else { return }
            }
            trackpadEngine.releaseAbsolutePointer(.pencil)
            if let location, let viewSize {
                trackpadEngine.handleAbsolutePointer(point: location, viewSize: viewSize, buttons: [], source: .pencil)
            }
            trackpadEngine.click(button: keyboardConfiguration.pencilAction(for: gesture) == .secondaryClick ? .right : .middle)
        }
    }

    private var userPasswordTarget: RemoteDevice? {
        guard canSendDictation, clipboardApplicationActive, device.deviceType == .mac,
              let account = client.username, !account.isEmpty else { return nil }
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return nil }
        #endif
        if isTemporary {
            var target = device
            target.username = account
            target.authMethod = .macAccount
            return target
        }
        guard let saved = deviceStore.device(withID: device.id), saved.deviceType == .mac,
              saved.authMethod == .macAccount, saved.host == device.host, saved.port == device.port,
              let username = saved.username, !username.isEmpty, username == client.username else { return nil }
        return saved
    }

    public var canTypeUserPassword: Bool { !isTypingUserPassword && userPasswordTarget != nil }

    func cancelUserPasswordRequest() {
        userPasswordToken = nil
        userPasswordTask?.cancel()
        userPasswordTask = nil
        isTypingUserPassword = false
    }

    public func typeUserPassword(pressReturn: Bool = true) {
        guard canTypeUserPassword, let target = userPasswordTarget else { return }
        userPasswordError = nil
        let token = UUID()
        userPasswordToken = token
        isTypingUserPassword = true
        userPasswordTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.userPasswordToken == token {
                    self.userPasswordToken = nil
                    self.userPasswordTask = nil
                    self.isTypingUserPassword = false
                }
            }
            guard await self.userPasswordAuthentication(), !Task.isCancelled,
                  self.userPasswordToken == token else { return }
            // Biometric UI can temporarily resign application activity. Only a
            // still-selected, active session may receive the completed command.
            for _ in 0..<20 {
                if self.userPasswordTarget != nil { break }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard self.userPasswordToken == token, self.matchesUserPasswordTarget(target),
                  let password = self.client.password ?? self.userPasswordReader(target), !password.isEmpty,
                  password.utf8.count <= 4096,
                  password.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
                  self.matchesUserPasswordTarget(target), !Task.isCancelled else {
                if self.userPasswordToken == token { self.userPasswordError = "The saved user password is unavailable for this session." }
                return
            }
            self.userPasswordToken = nil
            self.userPasswordTask = nil
            self.isTypingUserPassword = false
            self.releaseAllModifiers()
            if !self.client.typeUserPassword(password, pressReturn: pressReturn) {
                self.userPasswordError = "The saved user password could not be typed. Reconnect and try again."
            }
        }
    }

    private func matchesUserPasswordTarget(_ target: RemoteDevice) -> Bool {
        guard let current = userPasswordTarget else { return false }
        return current.id == target.id && current.host == target.host && current.port == target.port
            && current.username == target.username && current.authMethod == target.authMethod
    }

    public func handleHardwareKey(down: Bool, keySym: UInt32) {
        guard canSendDictation else { return }
        guard let mapped = hardwareKeyboardMapping.event(down: down, key: keySym,
            configuration: keyboardConfiguration.hardwareKeyboard ?? HardwareKeyboardConfiguration()) else { return }
        client.sendKeyEvent(down: down, keySym: mapped, source: .hardwareKeyboard)
    }

    public func sendDictation(_ text: String) {
        guard canSendDictation, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sendTextString(text)
    }

    /// Execute a predefined Mac shortcut
    public func executeShortcut(_ shortcut: MacKeyMap.MacShortcut) {
        guard controlInputAllowed else { return }
        let sequence = shortcut.keySequence
        for item in sequence {
            client.sendKeyEvent(down: item.down, keySym: item.key)
        }
        releaseActiveOnceModifiers()
    }

    public var canTriggerHotCorner: Bool {
        canSendDictation && device.deviceType == .mac && !isPanningViewport
    }

    /// Enter the selected display's corner without dragging or inheriting a
    /// sticky modifier. Moving through its center allows repeated activation.
    public func triggerHotCorner(_ corner: TrackpadEngine.HotCorner) {
        guard canTriggerHotCorner else { return }
        // Release transport-held hardware keys too, not only toolbar modifiers.
        client.setInputEnabled(false)
        trackpadEngine.releaseAllButtons()
        releaseAllModifiers()
        inputGeneration = UUID()
        refreshInputGate()
        trackpadEngine.moveCursor(to: CGPoint(x: trackpadEngine.remoteWidth / 2, y: trackpadEngine.remoteHeight / 2))
        trackpadEngine.moveCursor(to: corner.point(width: trackpadEngine.remoteWidth, height: trackpadEngine.remoteHeight))
    }

    public func triggerScreenBoundary(_ target: ScreenBoundaryTarget) {
        guard canTriggerHotCorner else { return }
        switch target {
        case .corner(let corner): triggerHotCorner(corner)
        case .edge(let edge):
            client.setInputEnabled(false)
            trackpadEngine.releaseAllButtons()
            releaseAllModifiers()
            // The native boundary recognizer releases local held input before
            // invoking this action. Keep that canvas and its window recognizers
            // alive for consecutive edge swipes.
            refreshInputGate()
            trackpadEngine.moveCursor(to: CGPoint(x: trackpadEngine.remoteWidth / 2, y: trackpadEngine.remoteHeight / 2))
            trackpadEngine.moveCursor(to: edge.point(width: trackpadEngine.remoteWidth, height: trackpadEngine.remoteHeight))
        }
    }

    /// Local fullscreen controls remain available in Observe mode.
    public func toggleFullscreen() {
        trackpadEngine.releaseAllButtons()
        // Publish the layout before rebuilding native input. SwiftUI can rebuild
        // synchronously when its identity changes, so it must see the new value.
        withAnimation(.easeInOut(duration: 0.18)) {
            isFullscreen.toggle()
            inputGeneration = UUID()
        }
    }

    public func handleThreeFingerSwipe(_ direction: MacKeyMap.ThreeFingerSwipe) {
        guard canSendDictation else { return }
        trackpadEngine.releaseAllButtons()
        // Sticky modifiers must not turn a standard Control-arrow into another shortcut.
        releaseAllModifiers()
        executeShortcut(direction.shortcut)
    }

    /// Double-tap toggles fit and one remote pixel per local display pixel.
    public func handleDoubleTapZoom() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if zoomScale > 1.1 {
                zoomScale = 1.0
                viewOffset = .zero
            } else {
                zoomScale = actualSizeZoomScale
            }
        }
        triggerHaptic()
    }

    public var canSendClipboard: Bool {
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return false }
        #endif
        return canSendDictation && clipboardApplicationActive
    }
    public var canGetClipboard: Bool {
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return false }
        #endif
        return selectedApplicationInputActive && clipboardApplicationActive && client.state == .connected
    }

    func setClipboardApplicationActive(_ active: Bool) {
        guard clipboardApplicationActive != active else { return }
        let previousCount = observedClipboardCount
        clipboardApplicationActive = active
        clipboardGeneration.advance()
        manualClipboardRequest = false
        refreshClipboardMonitoring()
        // Preserve the last synchronized count even when a copy happens just
        // before suspension and the periodic check has not run yet.
        observedClipboardCount = previousCount
        if active && sharedClipboardEnabled {
            // A copy made in another app while suspended must reach the remote
            // clipboard before fetching it, rather than being overwritten.
            pollLocalClipboardChanges(fetchAfterUpload: true)
        }
    }

    public func setSharedClipboard(_ enabled: Bool) {
        guard sharedClipboardEnabled != enabled else { return }
        sharedClipboardEnabled = enabled
        clipboardGeneration.advance()
        manualClipboardRequest = false
        if !isTemporary { deviceStore.updateSharedClipboard(enabled, for: device) }
        refreshClipboardMonitoring()
        if enabled && canGetClipboard { client.requestRemoteClipboard() }
    }

    public func getRemoteClipboard() {
        guard canGetClipboard else { return }
        clipboardGeneration.advance()
        manualClipboardRequest = true
        if !client.requestRemoteClipboard() {
            manualClipboardRequest = false
            clipboardPasteError = "This connection cannot fetch clipboard content."
        } else { clipboardPasteError = nil }
    }

    public func sendLocalClipboard() {
        guard canSendClipboard else { return }
        if clipboardAsyncReader != nil { readLocalClipboard(action: .send); return }
        let items = clipboardReader()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] == "1" {
            AppLogger.shared.info("QA clipboard send: flavors=\(items.count), changeCount=\(clipboardCountReader())", category: "RFB")
        }
        #endif
        guard !items.isEmpty else { return }
        clipboardPasteError = uploadClipboard(items) ? nil : "Clipboard content could not be sent. Copy a smaller selection and try again."
    }

    private func uploadClipboard(_ items: [RFBClipboardFlavor]) -> Bool {
        if client.supportsAppleClipboard { return client.sendClipboardFlavors(items) }
        guard let text = ApplePasteboard.text(in: items) else { return false }
        return client.sendCutText(text)
    }

    private func refreshClipboardMonitoring() {
        clipboardReadTask?.cancel()
        clipboardReadTask = nil
        clipboardReadID = UUID()
        client.setAutomaticClipboardMonitoring(sharedClipboardEnabled && isForegroundSession && clipboardApplicationActive)
        clipboardMonitor?.cancel()
        clipboardMonitor = nil
        observedClipboardCount = clipboardCountReader()
        guard sharedClipboardEnabled, canSendClipboard else { return }
        clipboardMonitor = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                guard let self else { return }
                self.pollLocalClipboardChanges()
            }
        }
    }

    /// Compare metadata first; read clipboard bytes only after a new local copy.
    func pollLocalClipboardChanges(fetchAfterUpload: Bool = false) {
        guard sharedClipboardEnabled, canSendClipboard else {
            if fetchAfterUpload && canGetClipboard { client.requestRemoteClipboard() }
            return
        }
        guard clipboardReadTask == nil else { return }
        let count = clipboardCountReader()
        guard observedClipboardCount != count else {
            if fetchAfterUpload && canGetClipboard { client.requestRemoteClipboard() }
            return
        }
        if clipboardAsyncReader != nil { readLocalClipboard(action: .automatic(fetchAfterUpload)); return }
        observedClipboardCount = count
        let items = clipboardReader()
        // Unsupported/multiple items do not clear a valid remote clipboard.
        if !items.isEmpty { _ = uploadClipboard(items) }
        if fetchAfterUpload && canGetClipboard { client.requestRemoteClipboard() }
    }

    /// Explicit user action reads supported local flavors and pastes them remotely.
    public func syncClipboardToMac() {
        guard canSendClipboard else { return }
        if clipboardAsyncReader != nil { readLocalClipboard(action: .paste); return }
        let items = clipboardReader()
        #if DEBUG
        if ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DIAGNOSTICS"] == "1" {
            AppLogger.shared.info("QA clipboard paste: flavors=\(items.count), changeCount=\(clipboardCountReader())", category: "RFB")
        }
        #endif
        guard !items.isEmpty else { return }
        pasteClipboardFlavors(items)
    }

    private enum ClipboardReadAction { case send, paste, automatic(Bool) }

    private func readLocalClipboard(action: ClipboardReadAction) {
        guard let reader = clipboardAsyncReader else { return }
        clipboardReadTask?.cancel()
        let id = UUID(), generation = callbackGeneration.capture()
        let foreground = foregroundGeneration.capture(), clipboard = clipboardGeneration.capture()
        let count = clipboardCountReader()
        clipboardReadID = id
        clipboardReadTask = Task { @MainActor [weak self] in
            let items = await reader()
            guard let self else { return }
            defer { if self.clipboardReadID == id { self.clipboardReadTask = nil } }
            guard !Task.isCancelled, self.clipboardReadID == id,
                  self.callbackGeneration.matches(generation), self.foregroundGeneration.matches(foreground),
                  self.clipboardGeneration.matches(clipboard), self.canSendClipboard else { return }
            guard self.clipboardCountReader() == count else {
                if case .automatic = action { self.observedClipboardCount = nil }
                else { self.clipboardPasteError = "Clipboard changed. Try again." }
                return
            }
            guard let items else {
                if case .automatic = action { return }
                self.clipboardPasteError = "Unable to read clipboard. Try copying again."
                return
            }
            switch action {
            case .paste:
                if !items.isEmpty {
                    self.pasteClipboardFlavors(items)
                    if self.clipboardPasteError == nil { self.observedClipboardCount = count }
                }
            case .send:
                if !items.isEmpty {
                    let sent = self.uploadClipboard(items)
                    self.clipboardPasteError = sent ? nil : "Clipboard content could not be sent. Copy a smaller selection and try again."
                    if sent { self.observedClipboardCount = count }
                }
            case .automatic(let fetchAfterUpload):
                guard self.sharedClipboardEnabled else { return }
                guard items.isEmpty || self.uploadClipboard(items) else { return }
                self.observedClipboardCount = count
                if fetchAfterUpload && self.canGetClipboard { self.client.requestRemoteClipboard() }
            }
        }
    }

    func pasteClipboardFlavors(_ items: [RFBClipboardFlavor]) {
        guard canSendClipboard else { return }
        if let text = ApplePasteboard.text(in: items),
           text.utf8.prefix(ApplePasteboard.maximumTextBytes + 1).count > ApplePasteboard.maximumTextBytes {
            clipboardPasteError = "Clipboard text is too large. Copy a smaller selection and try again."
            return
        }
        releaseAllModifiers()
        switch client.queueClipboardAndPaste(items) {
        case .queued: clipboardPasteError = nil
        case .unsupported:
            if let text = ApplePasteboard.text(in: items) { pasteClipboardText(text) }
            else { clipboardPasteError = "This connection does not support this clipboard content." }
        case .rejected:
            clipboardPasteError = "Clipboard content could not be sent. Copy a smaller selection and try again."
        }
    }

    func pasteClipboardText(_ text: String) {
        guard canSendClipboard else { return }
        guard text.utf8.prefix(ApplePasteboard.maximumTextBytes + 1).count <= ApplePasteboard.maximumTextBytes else {
            clipboardPasteError = "Clipboard text is too large. Copy a smaller selection and try again."
            return
        }
        releaseAllModifiers()
        switch client.queueClipboardAndPaste(text) {
        case .queued:
            clipboardPasteError = nil
        case .unsupported:
            clipboardPasteError = nil
            sendTextString(text)
        case .rejected:
            clipboardPasteError = "Clipboard text could not be sent. Try again."
        }
    }

    /// Trigger tactile haptic feedback on iOS devices
    public func triggerHaptic() {
        #if canImport(UIKit)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }

    /// Direct pointer event for macOS native mouse tracking or iPad trackpad
    public func sendNativePointer(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) {
        guard controlInputAllowed, !isPanningViewport else { return }
        let (tx, ty) = multiDisplayManager.translateCoordinates(
            x: CGFloat(x),
            y: CGFloat(y),
            remoteTotalWidth: CGFloat(client.framebuffer.width),
            remoteTotalHeight: CGFloat(client.framebuffer.height)
        )
        client.sendPointerEvent(buttonMask: buttonMask, x: tx, y: ty)
    }

    /// Direct key event for macOS native keyboard passthrough
    public func sendNativeKey(down: Bool, keySym: UInt32) {
        handleHardwareKey(down: down, keySym: keySym)
    }

    /// A native view can disappear while the transport remains connected.
    /// Cancel its queued wheels after its local held input has been released.
    func resetNativePointerInput() {
        client.setPointerInputEnabled(false)
        client.setPointerInputEnabled(!isPanningViewport)
    }
}

private final class SessionCallbackGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    func capture() -> UUID { lock.lock(); defer { lock.unlock() }; return value }
    func matches(_ generation: UUID) -> Bool { capture() == generation }
    func advance() { lock.lock(); value = UUID(); lock.unlock() }
}
