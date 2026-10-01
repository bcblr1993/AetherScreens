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
            trackpadEngine.releaseAllButtons()
            trackpadEngine.mode = inputMode
        }
    }
    @Published public var isObserveOnly = false {
        didSet {
            releaseAllModifiers()
            trackpadEngine.releaseAllButtons()
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
            if !isTemporary { keyboardStore.save(keyboardConfiguration, for: device.id) }
        }
    }
    private let keyboardStore: KeyboardToolbarStore
    public var canRememberPassword: Bool { !isTemporary }
    private let deviceStore: DeviceStore
    private nonisolated let callbackGeneration = SessionCallbackGeneration()

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
                if case .failed = state {
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
            let generation = self.callbackGeneration.capture()
            renderer?.notifyFrameUpdated()
            Task { @MainActor [weak self] in
                guard let self, self.callbackGeneration.matches(generation) else { return }
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

    /// Move the local viewport without emitting remote pointer events.
    public func panViewport(dx: CGFloat, dy: CGFloat, limitX: CGFloat, limitY: CGFloat) {
        let x = max(-limitX, min(limitX, viewOffset.width))
        let y = max(-limitY, min(limitY, viewOffset.height))
        viewOffset = CGSize(width: max(-limitX, min(limitX, x + dx)),
                            height: max(-limitY, min(limitY, y + dy)))
    }

    /// Connect to remote Mac
    public func startSession() {
        callbackGeneration.advance()
        hasReceivedFirstFrame = false
        downloadProgress = nil
        lastFramebufferSize = .zero
        multiDisplayManager.reset(width: client.framebuffer.width, height: client.framebuffer.height)
        client.connect()
    }

    /// Reauthenticate without leaving the viewport; also clear held local input.
    public func reconnectSession() {
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
        cancelPasswordPrompt()
        inputGeneration = UUID()
        if curtainManager.isCurtainActive { curtainManager.toggleCurtain() }
        startSession()
    }

    /// Disconnect from remote Mac
    public func endSession() {
        callbackGeneration.advance()
        releaseAllModifiers()
        trackpadEngine.releaseAllButtons()
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
        cancelPasswordPrompt()
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

private final class SessionCallbackGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    func capture() -> UUID { lock.lock(); defer { lock.unlock() }; return value }
    func matches(_ generation: UUID) -> Bool { capture() == generation }
    func advance() { lock.lock(); value = UUID(); lock.unlock() }
}
