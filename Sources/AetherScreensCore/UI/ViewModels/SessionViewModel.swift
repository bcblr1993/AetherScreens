import Foundation
import SwiftUI
import CoreGraphics
import Combine

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
    public let curtainManager: CurtainModeManager
    public let multiDisplayManager: MultiDisplayManager
    public let metrics: PerformanceMetrics
    public let metalRenderer: MetalScreenRenderer?

    @Published public var sessionState: RFBClient.State = .disconnected
    @Published public var currentImage: CGImage?
    @Published public var hasReceivedFirstFrame: Bool = false
    @Published public var downloadProgress: (current: Double, total: Double)? = nil
    @Published public var inputMode: TrackpadEngine.Mode = .trackpad {
        didSet {
            trackpadEngine.mode = inputMode
        }
    }
    @Published public var isObserveOnly = false {
        didSet {
            releaseAllModifiers()
            if isObserveOnly { isKeyboardVisible = false }
            client.setInputEnabled(!isObserveOnly)
            inputGeneration = UUID()
        }
    }
    @Published public var isKeyboardVisible: Bool = false
    @Published public var showShortcutsMenu: Bool = false
    @Published public var showDisplaysMenu: Bool = false
    @Published public var isTextInputBarVisible: Bool = false
    @Published public var textInputBuffer: String = ""

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
    @Published public var isPanningViewport: Bool = false
    @Published public private(set) var inputGeneration = UUID()
    private var frameCountSinceLastSnapshot: Int = 0
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
    public var canRememberPassword: Bool { !isTemporary }
    private let deviceStore: DeviceStore

    public init(device: RemoteDevice, password: String?, isTemporary: Bool = false,
                deviceStore: DeviceStore = .shared, keyboardStore: KeyboardToolbarStore = .shared) {
        self.device = device
        self.isTemporary = isTemporary
        self.deviceStore = deviceStore
        self.keyboardStore = keyboardStore
        self.keyboardConfiguration = isTemporary ? KeyboardToolbarConfiguration() : keyboardStore.load(for: device.id)
        let rfb = RFBClient(
            host: device.host,
            port: device.port,
            password: password,
            username: device.username
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
            guard let self = self else { return }
            let (tx, ty) = self.multiDisplayManager.translateCoordinates(
                x: CGFloat(x),
                y: CGFloat(y),
                remoteTotalWidth: CGFloat(self.client.framebuffer.width),
                remoteTotalHeight: CGFloat(self.client.framebuffer.height)
            )
            self.client.sendPointerEvent(buttonMask: mask, x: tx, y: ty)
        }

        // Handle Curtain Mode toggle
        curtainManager.onCurtainStateChanged = { [weak self] isActive in
            Task { @MainActor in
                guard let self = self else { return }
                if isActive {
                    // Send Lock Screen shortcut (Ctrl + Cmd + Q)
                    self.executeShortcut(.lockScreen)
                }
            }
        }

        // Handle Multi-Display Selection
        multiDisplayManager.onDisplaySelected = { [weak self] display in
            Task { @MainActor in
                guard let self = self else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if let d = display, d.id > 0 {
                        self.activeCropRect = d.bounds
                        self.trackpadEngine.remoteWidth = d.bounds.width
                        self.trackpadEngine.remoteHeight = d.bounds.height
                    } else {
                        self.activeCropRect = nil
                        self.trackpadEngine.remoteWidth = CGFloat(self.client.framebuffer.width)
                        self.trackpadEngine.remoteHeight = CGFloat(self.client.framebuffer.height)
                        self.zoomScale = 1.0
                        self.viewOffset = .zero
                    }
                    self.trackpadEngine.resetCursor()
                }
            }
        }

        // Handle RFB client state changes
        client.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.sessionState = state
                if state == .connected, let self, !self.isTemporary {
                    self.deviceStore.recordConnection(for: self.device)
                }
            }
        }

        // Handle Interactive VNC Password Prompt from Server
        client.onRequestPassword = { [weak self] continuation in
            Task { @MainActor in
                guard let self = self else {
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
            Task { @MainActor in
                guard let self else { continuation(nil, nil); return }
                self.macAccountContinuation = continuation
                self.requiresMacAccountPrompt = true
                self.passwordPromptError = nil
                self.isPromptingPassword = true
            }
        }

        let sessionMetrics = metrics
        client.onBytesReceived = { count in sessionMetrics.recordBytesReceived(count) }

        // Handle incoming frame download progress
        client.onDownloadProgress = { [weak self] current, total in
            Task { @MainActor in
                self?.downloadProgress = (current, total)
            }
        }

        // Handle incoming screen frame updates
        let renderer = metalRenderer
        client.onFrameUpdated = { [weak self] in
            renderer?.notifyFrameUpdated()
            Task { @MainActor in
                guard let self = self else { return }
                if !self.hasReceivedFirstFrame { self.hasReceivedFirstFrame = true }
                if self.downloadProgress != nil { self.downloadProgress = nil }
                if self.metalRenderer == nil {
                    self.currentImage = self.client.framebuffer.makeCGImage()
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
                self.frameCountSinceLastSnapshot += 1
                if !self.isTemporary && (self.frameCountSinceLastSnapshot == 5 || self.frameCountSinceLastSnapshot % 60 == 0) {
                    let framebuffer = self.client.framebuffer
                    let deviceId = self.device.id
                    DispatchQueue.global(qos: .utility).async {
                        if let image = framebuffer.makeCGImage() {
                            ThumbnailStore.shared.saveThumbnail(image, for: deviceId)
                        }
                    }
                }
            }
        }

        // Handle incoming clipboard text
        client.onClipboardReceived = { text in
            #if canImport(UIKit)
            Task { @MainActor in
                UIPasteboard.general.string = text
            }
            #elseif canImport(AppKit)
            Task { @MainActor in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            #endif
        }
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
    public func cancelPasswordPrompt() {
        isPromptingPassword = false
        let cont = passwordContinuation
        passwordContinuation = nil
        cont?(nil)
        let accountContinuation = macAccountContinuation
        macAccountContinuation = nil
        accountContinuation?(nil, nil)
        client.disconnect()
    }

    /// Connect to remote Mac
    public func startSession() {
        hasReceivedFirstFrame = false
        downloadProgress = nil
        client.connect()
    }

    /// Reauthenticate without leaving the viewport; also clear held local input.
    public func reconnectSession() {
        releaseAllModifiers()
        client.disconnect()
        inputGeneration = UUID()
        if curtainManager.isCurtainActive { curtainManager.toggleCurtain() }
        startSession()
    }

    /// Disconnect from remote Mac
    public func endSession() {
        let framebuffer = client.framebuffer
        let deviceId = device.id
        if !isTemporary {
            DispatchQueue.global(qos: .utility).async {
                if let image = framebuffer.makeCGImage() {
                    ThumbnailStore.shared.saveThumbnail(image, for: deviceId)
                }
            }
        }
        hasReceivedFirstFrame = false
        downloadProgress = nil
        client.disconnect()
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

    /// Send a single key tap (down + up)
    public func sendKeyTap(_ keySym: UInt32) {
        client.sendKeyEvent(down: true, keySym: keySym)
        let generation = inputGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.inputGeneration == generation else { return }
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
        client.sendText(text)
        releaseActiveOnceModifiers()
    }

    /// Execute a predefined Mac shortcut
    public func executeShortcut(_ shortcut: MacKeyMap.MacShortcut) {
        let sequence = shortcut.keySequence
        for item in sequence {
            client.sendKeyEvent(down: item.down, keySym: item.key)
        }
        releaseActiveOnceModifiers()
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

    /// Insert local clipboard text into the focused remote field. Apple Screen Sharing
    /// does not accept legacy ClientCutText in the tested account session.
    public func syncClipboardToMac() {
        guard !isObserveOnly else { return }
        #if canImport(UIKit)
        if let string = UIPasteboard.general.string {
            sendTextString(string)
        }
        #elseif canImport(AppKit)
        if let string = NSPasteboard.general.string(forType: .string) {
            sendTextString(string)
        }
        #endif
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
        client.sendKeyEvent(down: down, keySym: keySym)
    }
}
