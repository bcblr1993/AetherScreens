import SwiftUI
import CoreGraphics

/// Metal-backed remote desktop with native input, viewport controls and session diagnostics.
public struct RemoteDesktopView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @ObservedObject private var displayManager: MultiDisplayManager
    @ObservedObject private var externalDisplayMirror: RemoteDisplayMirror
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    #if canImport(UIKit)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @State private var showingLogs: Bool = false
    @State private var showingKeyboardCustomization = false
    private let managesSessionLifecycle: Bool
    private let onDisconnect: (() -> Void)?
    private let onReturnToLibrary: (() -> Void)?

    public init(viewModel: SessionViewModel, managesSessionLifecycle: Bool = true, onDisconnect: (() -> Void)? = nil,
                onReturnToLibrary: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.displayManager = viewModel.multiDisplayManager
        self.externalDisplayMirror = viewModel.externalDisplayMirror
        self.managesSessionLifecycle = managesSessionLifecycle
        self.onDisconnect = onDisconnect
        self.onReturnToLibrary = onReturnToLibrary
    }

    // Connection failures must reveal controls even when the session prefers fullscreen.
    private var usesFullscreenLayout: Bool { viewModel.isFullscreen && viewModel.sessionState == .connected }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.055, green: 0.07, blue: 0.09).ignoresSafeArea()

                // Remote Screen View (Metal accelerated if available)
                if viewModel.sessionState == .connected || viewModel.currentImage != nil {
                    remoteCanvas(geometry: geometry)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(viewModel.hasReceivedFirstFrame ? "remote-desktop-frame" : "remote-desktop-loading")
                } else {
                    connectingStateView
                }

                // Initial Frame Loading HUD
                if (viewModel.sessionState == .connected || viewModel.sessionState == .initializing) && !viewModel.hasReceivedFirstFrame {
                    firstFrameLoadingHUD
                }

                #if os(macOS)
                if !usesFullscreenLayout {
                    VStack {
                        floatingTopBar.padding(.top, 12)
                        Spacer()
                    }
                }
                #else
                if usesFullscreenLayout {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                viewModel.toggleFullscreen()
                                viewModel.isKeyboardVisible = true
                            } label: { controlIcon("keyboard") }
                            .accessibilityLabel(AppLocalization.string("Show Keyboard"))
                            .disabled(viewModel.isObserveOnly)
                            Button { viewModel.toggleFullscreen() } label: {
                                controlIcon("arrow.down.right.and.arrow.up.left")
                            }
                            .accessibilityLabel(AppLocalization.string("Exit Full Screen"))
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .background(.black.opacity(0.72), in: Capsule())
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, max(12, geometry.safeAreaInsets.trailing))
                        .padding(.top, max(4, geometry.safeAreaInsets.top))
                        Spacer()
                    }
                }
                #endif

                // Recovery must remain visible on failure/disconnected pages,
                // including Metal sessions that never populate currentImage.
                if let message = viewModel.curtainStatusMessage {
                    VStack {
                        Spacer()
                        Text(AppLocalization.string(message))
                            .font(.caption)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("session-curtain-status")
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
        }
        // Reserve room for controls so a zoomed desktop never hides behind the
        // keyboard. Safe-area insets also follow rotation and the software IME.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesFullscreenLayout && viewModel.isKeyboardVisible && viewModel.keyboardConfiguration.position == .bottom {
                MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if !usesFullscreenLayout {
                    #if canImport(UIKit)
                    if verticalSizeClass != .compact || !viewModel.isTextInputBarVisible {
                        floatingTopBar.padding(.vertical, 4)
                    }
                    #endif
                    if viewModel.isKeyboardVisible && viewModel.keyboardConfiguration.position == .top {
                        MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization)
                    }
                }
            }
        }
        // The clipped desktop must not leave the host view's white background
        // visible around the camera/home-indicator safe areas after rotation.
        .background {
            Color(red: 0.055, green: 0.07, blue: 0.09).ignoresSafeArea()
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .background {
            if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .pad {
                ExternalRemoteDisplayRegistration(session: viewModel)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        #endif
        #if canImport(UIKit)
        .ignoresSafeArea(.container, edges: usesFullscreenLayout ? .all : [])
        .statusBarHidden(viewModel.sessionState == .connected)
        .defersSystemGestures(on: viewModel.canTriggerHotCorner ? .all : [])
        #endif
        .alert(AppLocalization.string("Type User Password"), isPresented: Binding(
            get: { viewModel.userPasswordError != nil },
            set: { if !$0 { viewModel.userPasswordError = nil } }
        )) {
            Button(AppLocalization.string("OK"), role: .cancel) { viewModel.userPasswordError = nil }
        } message: {
            Text(AppLocalization.string(viewModel.userPasswordError ?? ""))
        }
        .onAppear {
            if managesSessionLifecycle { viewModel.startSession() }
        }
        .onDisappear {
            if managesSessionLifecycle { viewModel.endSession() }
        }
        .sheet(item: Binding(get: { viewModel.sshTrustRequest }, set: { request in
            if request == nil, let pending = viewModel.sshTrustRequest {
                viewModel.submitSSHTrust(id: pending.id, decision: .cancel)
            }
        })) { request in
            SSHTrustSheet(request: request, canRemember: !viewModel.isTemporary) { decision in
                viewModel.submitSSHTrust(id: request.id, decision: decision)
            }
        }
        .sheet(isPresented: $viewModel.isPromptingPassword) {
            PasswordPromptSheet(
                deviceName: viewModel.device.name,
                host: viewModel.device.host,
                username: viewModel.client.username,
                errorMessage: viewModel.passwordPromptError,
                canRememberPassword: viewModel.canRememberPassword,
                requiresMacAccount: viewModel.requiresMacAccountPrompt,
                onSubmit: { pwd, account, saveToKeychain in
                    viewModel.submitPassword(pwd, rememberInKeychain: saveToKeychain, accountUsername: account)
                },
                onCancel: {
                    viewModel.cancelPasswordPrompt()
                }
            )
            #if canImport(UIKit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $showingLogs) {
            DiagnosticLogView()
        }
        .sheet(isPresented: $showingKeyboardCustomization) {
            KeyboardToolbarSettingsView(configuration: $viewModel.keyboardConfiguration)
        }
        .alert(AppLocalization.string("Unable to Paste"), isPresented: Binding(
            get: { viewModel.clipboardPasteError != nil },
            set: { if !$0 { viewModel.clipboardPasteError = nil } }
        )) {
            Button(AppLocalization.string("Close"), role: .cancel) { viewModel.clipboardPasteError = nil }
        } message: {
            Text(AppLocalization.string(viewModel.clipboardPasteError ?? ""))
        }
        .alert(AppLocalization.string("Unable to Switch Display"), isPresented: Binding(
            get: { viewModel.displaySelectionError != nil },
            set: { if !$0 { viewModel.displaySelectionError = nil } }
        )) {
            Button(AppLocalization.string("Close"), role: .cancel) { viewModel.displaySelectionError = nil }
        } message: {
            Text(AppLocalization.string(viewModel.displaySelectionError ?? ""))
        }
        .alert(AppLocalization.string("Unable to Change Image Compression"), isPresented: Binding(
            get: { viewModel.imageCompressionError != nil },
            set: { if !$0 { viewModel.imageCompressionError = nil } }
        )) {
            Button(AppLocalization.string("Retry")) { viewModel.setImageCompression(viewModel.imageCompression) }
            Button(AppLocalization.string("Close"), role: .cancel) { viewModel.imageCompressionError = nil }
        } message: {
            Text(AppLocalization.string(viewModel.imageCompressionError ?? ""))
        }
    }

    // MARK: - Canvas Rendering Layer

    @ViewBuilder
    private func remoteCanvas(geometry: GeometryProxy) -> some View {
        let imageWidth = viewModel.activeCropRect?.width ?? CGFloat(viewModel.client.framebuffer.width)
        let imageHeight = viewModel.activeCropRect?.height ?? CGFloat(viewModel.client.framebuffer.height)
        let safeWidth = max(imageWidth, 1)
        let safeHeight = max(imageHeight, 1)
        let fitScale = min(geometry.size.width / safeWidth, geometry.size.height / safeHeight)
        let canvasWidth = safeWidth * fitScale * viewModel.zoomScale
        let canvasHeight = safeHeight * fitScale * viewModel.zoomScale
        let limitX = max(0, (canvasWidth - geometry.size.width) / 2)
        let limitY = max(0, (canvasHeight - geometry.size.height) / 2)
        let offsetX = max(-limitX, min(limitX, viewModel.viewOffset.width))
        let offsetY = max(-limitY, min(limitY, viewModel.viewOffset.height))
        let originX = (geometry.size.width - canvasWidth) / 2 + offsetX
        let originY = (geometry.size.height - canvasHeight) / 2 + offsetY

        ZStack(alignment: .topLeading) {
            // High Performance Metal View
            if let renderer = viewModel.metalRenderer {
                MetalScreenView(renderer: renderer, sourceRect: viewModel.activeCropRect)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .position(x: originX + canvasWidth / 2, y: originY + canvasHeight / 2)
            } else if let cgImage = viewModel.currentImage {
                Image(decorative: viewModel.activeCropRect.flatMap { cgImage.cropping(to: $0) } ?? cgImage, scale: 1.0)
                    .resizable()
                    .frame(width: canvasWidth, height: canvasHeight)
                    .position(x: originX + canvasWidth / 2, y: originY + canvasHeight / 2)
            }

            #if canImport(AppKit)
            // macOS Native Pointer and Keyboard Capture (M-chip Mac)
            if !viewModel.isObserveOnly || viewModel.isPanningViewport {
            MacNativeInputRepresentable(
                remoteWidth: imageWidth > 0 ? imageWidth : 1920,
                remoteHeight: imageHeight > 0 ? imageHeight : 1080,
                isPanning: viewModel.isPanningViewport,
                onPan: { dx, dy in
                    viewModel.panViewport(dx: dx, dy: dy, limitX: limitX, limitY: limitY)
                },
                onTextEvent: { text in viewModel.sendTextString(text) },
                onInputReset: { viewModel.resetNativePointerInput() },
                onPointerEvent: { mask, x, y in
                    viewModel.sendNativePointer(buttonMask: mask, x: x, y: y)
                },
                onKeyEvent: { down, keySym in
                    viewModel.sendNativeKey(down: down, keySym: keySym)
                }
            )
            .id(viewModel.inputGeneration)
            .frame(width: canvasWidth, height: canvasHeight)
            .position(x: originX + canvasWidth / 2, y: originY + canvasHeight / 2)
            }
            #endif

            #if canImport(UIKit)
            IOSRemoteInputView(
                engine: viewModel.trackpadEngine,
                inputDiagnosticIdentifier: viewModel.client.inputDiagnosticIdentifier,
                canvas: CGRect(x: originX, y: originY, width: canvasWidth, height: canvasHeight),
                zoom: viewModel.zoomScale,
                isPanning: viewModel.isPanningViewport,
                isObserveOnly: viewModel.isObserveOnly,
                isFullscreen: usesFullscreenLayout,
                onToggleFullscreen: { viewModel.toggleFullscreen() },
                onThreeFingerSwipe: { viewModel.handleThreeFingerSwipe($0) },
                hardwareKeyboardConfiguration: viewModel.keyboardConfiguration.hardwareKeyboard ?? HardwareKeyboardConfiguration(),
                hardwareKeyboardEnabled: viewModel.canSendDictation && !viewModel.isTextInputBarVisible && !showingLogs && !showingKeyboardCustomization,
                onHardwareKey: { viewModel.handleHardwareKey(down: $0, keySym: $1) },
                onPencilGesture: { viewModel.handlePencilGesture($0, location: $1, viewSize: $2) },
                boundaryGesturesEnabled: viewModel.canTriggerHotCorner && !showingLogs && !showingKeyboardCustomization && !viewModel.isTextInputBarVisible,
                onScreenBoundary: { viewModel.triggerScreenBoundary($0) },
                onPan: { dx, dy in
                    viewModel.panViewport(dx: dx, dy: dy, limitX: limitX, limitY: limitY)
                },
                onZoom: { viewModel.zoomScale = $0 }
            )
            .id(viewModel.inputGeneration)
            .frame(width: geometry.size.width, height: geometry.size.height)
            #endif

            // Local Lock Remote Mac notice; independent of real Curtain status.
            if viewModel.curtainManager.isCurtainActive {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                        Text(AppLocalization.string("Lock Screen shortcut sent"))
                            .font(.system(size: 12, weight: .semibold))

                        Button {
                            viewModel.curtainManager.toggleCurtain()
                        } label: {
                            Text(AppLocalization.string("Dismiss"))
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Button {
                            viewModel.reconnectSession()
                        } label: {
                            Text(AppLocalization.string("Reconnect"))
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(AppLocalization.string("Restore the session if input stops responding after unlocking"))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.purple.opacity(0.9), in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .padding(.top, 60)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onChange(of: fitScale, initial: true) { _, scale in
            viewModel.actualSizeZoomScale = max(1, 1 / max(0.001, scale * displayScale))
        }
    }

    // MARK: - Connecting State

    private var connectingStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            if case .failed = viewModel.sessionState {} else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            Text(AppLocalization.string(statusDescription))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            Text(viewModel.device.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Text(viewModel.device.host)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            if case .failed(let err) = viewModel.sessionState {
                Text(AppLocalization.message(err))
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                HStack(spacing: 12) {
                    Button(AppLocalization.string("Retry Connection")) {
                        viewModel.startSession()
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        viewModel.isPromptingPassword = true
                    } label: {
                        Label(AppLocalization.string("Enter Password"), systemImage: "key.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)

                Button {
                    showingLogs = true
                } label: {
                    Label(AppLocalization.string("View Diagnostic Logs"), systemImage: "text.book.closed")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .padding(24)
    }

    private var firstFrameLoadingHUD: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)

            Text(AppLocalization.string("Loading remote desktop…"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            if let progress = viewModel.downloadProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.current, total: progress.total)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(width: 220)

                    Text(AppLocalization.format("Received %.1f MB / %.1f MB (%.0f%%)", progress.current, progress.total, (progress.current / progress.total) * 100))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }
            } else {
                Text(AppLocalization.string("Connected. Waiting for remote frames…"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 20)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var statusDescription: String {
        switch viewModel.sessionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting to remote computer..."
        case .negotiatingVersion: return "Negotiating RFB 3.8 protocol..."
        case .authenticating: return "Authenticating with Mac..."
        case .initializing: return "Initializing screen sharing session..."
        case .connected: return "Connected"
        case .failed: return "Connection failed"
        }
    }

    // MARK: - Floating Top Controls Bar

    private var floatingTopBar: some View {
        HStack(spacing: 8) {
            // Close / Disconnect
            Button {
                if let onDisconnect {
                    onDisconnect()
                } else {
                    viewModel.endSession()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(AppLocalization.string("Disconnect"))

            // Keep monitor selection directly accessible without widening the toolbar.
            Menu {
                displayChoices
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "display")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    Circle()
                        .fill(viewModel.sessionState == .connected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(sessionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: sessionNameWidth, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(AppLocalization.string("Displays"))
            .accessibilityValue(AppLocalization.message(displayManager.currentDisplay?.name ?? "All Displays"))
            .accessibilityIdentifier("session-display-selector")
            .disabled(viewModel.pendingImageScale != nil)
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .fixedSize()
            #endif

            #if os(macOS)
            PerformanceHUDView(metrics: viewModel.metrics, isTailscale: viewModel.device.isTailscaleNode)
            #endif

            Spacer()

            #if os(macOS)
            Button { showingLogs = true } label: {
                controlIcon("list.bullet.rectangle")
            }
            .help(AppLocalization.string("View Diagnostic Logs"))
            #endif

            // Keep secondary controls inside a menu on narrow screens.
            Menu {
                if let onReturnToLibrary {
                    Button(action: onReturnToLibrary) {
                        Label(AppLocalization.string("Return to Computers"), systemImage: "rectangle.grid.2x2")
                    }
                    .accessibilityIdentifier("session-return-to-library")
                    Divider()
                }
                Button { viewModel.reconnectSession() } label: {
                    Label(AppLocalization.string("Reconnect"), systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("session-reconnect")
                Toggle(AppLocalization.string("Observe Only"), isOn: $viewModel.isObserveOnly)
                Menu(AppLocalization.format("Cursor Speed: %.2f×", viewModel.cursorSpeed)) {
                    Picker(AppLocalization.string("Cursor Speed"), selection: Binding(
                        get: { viewModel.cursorSpeed }, set: { viewModel.setCursorSpeed($0) }
                    )) {
                        ForEach([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { value in
                            Text(AppLocalization.format("%.2f×", value)).tag(value)
                        }
                    }
                }.accessibilityIdentifier("session-cursor-speed")
                Menu(AppLocalization.format("Image Compression: %@",
                                            AppLocalization.string(viewModel.imageCompression.rawValue))) {
                    Picker(AppLocalization.string("Image Compression"), selection: Binding(
                        get: { viewModel.imageCompression }, set: { viewModel.setImageCompression($0) }
                    )) {
                        ForEach(RemoteImageCompressionPolicy.allCases) { policy in
                            Text(AppLocalization.string(policy.rawValue)).tag(policy)
                        }
                    }
                    if viewModel.pendingImageScale != nil {
                        Text(AppLocalization.string("Changing Image Resolution…"))
                    }
                }
                .disabled(!viewModel.canChangeImageCompression)
                .accessibilityIdentifier("session-image-compression")
                .accessibilityValue(AppLocalization.string(viewModel.imageCompression.rawValue))
                Button { viewModel.typeUserPassword() } label: {
                    Label(AppLocalization.string("Type User Password"), systemImage: "key.fill")
                }.disabled(!viewModel.canTypeUserPassword).accessibilityIdentifier("session-type-user-password")
                Button { viewModel.typeUserPassword(pressReturn: false) } label: {
                    Text(AppLocalization.string("Type Password Without Return"))
                }.disabled(!viewModel.canTypeUserPassword).accessibilityIdentifier("session-type-password-without-return")
                ClipboardMenu(viewModel: viewModel)
                HotCornerMenu(viewModel: viewModel)
                Button { showingKeyboardCustomization = true } label: {
                    Label(AppLocalization.string("Customize Keyboard Toolbar"), systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("session-customize-keyboard")
                Divider()
                #if canImport(UIKit)
                Button { showingLogs = true } label: {
                    Label(AppLocalization.string("Diagnostic Logs"), systemImage: "list.bullet.rectangle")
                }
                #endif
                Menu {
                    Button(AppLocalization.string("Fit to Window")) {
                        viewModel.zoomScale = 1
                        viewModel.viewOffset = .zero
                        viewModel.isPanningViewport = false
                    }
                    Button(AppLocalization.string("Actual Size")) {
                        viewModel.zoomScale = viewModel.actualSizeZoomScale
                    }
                    Button(AppLocalization.string("Zoom In")) {
                        viewModel.zoomScale = min(max(4, viewModel.actualSizeZoomScale), viewModel.zoomScale * 1.25)
                    }
                    Button(AppLocalization.string("Zoom Out")) {
                        viewModel.zoomScale = max(1, viewModel.zoomScale / 1.25)
                        if viewModel.zoomScale == 1 {
                            viewModel.viewOffset = .zero
                            viewModel.isPanningViewport = false
                        }
                    }
                    Toggle(AppLocalization.string("Pan View"), isOn: $viewModel.isPanningViewport)
                        #if canImport(UIKit)
                        .disabled(viewModel.zoomScale <= 1 || viewModel.isObserveOnly)
                        #else
                        .disabled(viewModel.zoomScale <= 1)
                        #endif
                } label: {
                    Label(AppLocalization.string("View"), systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("session-view-menu")
                Divider()
                Menu {
                    displayChoices
                } label: {
                    Label(AppLocalization.string("Displays"), systemImage: "display")
                }
                .accessibilityIdentifier("session-displays")
                #if os(iOS) && !targetEnvironment(macCatalyst)
                if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .pad,
                   externalDisplayMirror.isAvailable {
                    Toggle(AppLocalization.string("Mirror to External Display"), isOn: Binding(
                        get: { externalDisplayMirror.isMirroring },
                        set: { externalDisplayMirror.setMirroring($0) }))
                        .disabled(!externalDisplayMirror.canPresent)
                        .accessibilityIdentifier("session-external-display-mirror")
                }
                #endif
                Button {
                    viewModel.changeCurtain()
                } label: {
                    Label(AppLocalization.string(viewModel.curtainActionTitle), systemImage: "eye.slash")
                }
                .disabled(!viewModel.canChangeCurtain)
                .help(AppLocalization.string("Requires an available Remote Management session outside the login window."))
                .accessibilityIdentifier("session-curtain-toggle")
                Button {
                    viewModel.triggerHaptic()
                    viewModel.curtainManager.toggleCurtain()
                } label: {
                    Label(AppLocalization.string(viewModel.curtainManager.isCurtainActive ? "Dismiss Lock Notice" : "Lock Remote Mac"), systemImage: "lock")
                }
                .disabled(viewModel.isObserveOnly && !viewModel.curtainManager.isCurtainActive)
            } label: {
                controlIcon("ellipsis")
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .fixedSize()
            #endif
            .accessibilityLabel(AppLocalization.string("Session Options"))

            // Touch vs Trackpad Mode Toggle
            #if canImport(UIKit)
            Menu {
                Picker(AppLocalization.string("Input Mode"), selection: $viewModel.inputMode) {
                    Label(AppLocalization.string("Trackpad"), systemImage: "hand.point.up.left.fill").tag(TrackpadEngine.Mode.trackpad)
                    Label(AppLocalization.string("Touch"), systemImage: "hand.tap.fill").tag(TrackpadEngine.Mode.touch)
                }
            } label: {
                controlIcon(viewModel.inputMode == .trackpad ? "hand.point.up.left.fill" : "hand.tap.fill")
            }
            .accessibilityLabel(AppLocalization.string("Input Mode"))
            #endif

            // Keyboard Toolbar Toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.isKeyboardVisible.toggle()
                }
            } label: {
                controlIcon("keyboard")
            }
            .accessibilityLabel(AppLocalization.string(viewModel.isKeyboardVisible ? "Hide Keyboard" : "Show Keyboard"))
            .disabled(viewModel.isObserveOnly)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var displayChoices: some View {
        ForEach(displayManager.availableDisplays) { display in
            Button {
                viewModel.selectDisplay(id: display.id)
            } label: {
                HStack {
                    Text(AppLocalization.message(display.name))
                    if displayManager.pendingDisplayId == display.id {
                        ProgressView().accessibilityLabel(AppLocalization.string("Switching Display"))
                    }
                    if displayManager.selectedDisplayId == display.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .disabled(viewModel.pendingImageScale != nil)
        }
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var sessionTitle: String {
        if viewModel.isObserveOnly { return AppLocalization.format("Observe · %@", viewModel.device.name) }
        if viewModel.isPanningViewport { return AppLocalization.format("Pan · %@", viewModel.device.name) }
        return viewModel.device.name
    }

    private var sessionNameWidth: CGFloat {
        #if os(macOS)
        170
        #else
        90
        #endif
    }
}
