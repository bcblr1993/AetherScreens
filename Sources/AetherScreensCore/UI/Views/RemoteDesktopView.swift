import SwiftUI
import CoreGraphics

/// Metal-backed remote desktop with native input, viewport controls and session diagnostics.
public struct RemoteDesktopView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var lastDragLocation: CGPoint?
    @State private var isDraggingMouse: Bool = false
    @State private var showingLogs: Bool = false
    @State private var showingKeyboardCustomization = false
    private let managesSessionLifecycle: Bool
    private let onDisconnect: (() -> Void)?

    public init(viewModel: SessionViewModel, managesSessionLifecycle: Bool = true, onDisconnect: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.managesSessionLifecycle = managesSessionLifecycle
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.055, green: 0.07, blue: 0.09).ignoresSafeArea()

                // Remote Screen View (Metal accelerated if available)
                if viewModel.sessionState == .connected || viewModel.currentImage != nil {
                    remoteCanvas(geometry: geometry)
                        .accessibilityIdentifier(viewModel.hasReceivedFirstFrame ? "remote-desktop-frame" : "remote-desktop-loading")
                } else {
                    connectingStateView
                }

                // Initial Frame Loading HUD
                if (viewModel.sessionState == .connected || viewModel.sessionState == .initializing) && !viewModel.hasReceivedFirstFrame {
                    firstFrameLoadingHUD
                }

                // Floating Top Controls Bar & Diagnostic HUD
                VStack {
                    floatingTopBar
                        .padding(.top, 12)
                    if viewModel.isKeyboardVisible && viewModel.keyboardConfiguration.position == .top {
                        MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization)
                            .transition(.move(edge: .top))
                    }
                    Spacer()

                    // Bottom Mac Keyboard Toolbar (if toggled)
                    if viewModel.isKeyboardVisible && viewModel.keyboardConfiguration.position == .bottom {
                        MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization)
                            .transition(.move(edge: .bottom))
                    }
                }
            }
        }
        .onAppear {
            if managesSessionLifecycle { viewModel.startSession() }
        }
        .onDisappear {
            if managesSessionLifecycle { viewModel.endSession() }
        }
        .sheet(isPresented: $viewModel.isPromptingPassword) {
            PasswordPromptSheet(
                deviceName: viewModel.device.name,
                host: viewModel.device.host,
                username: viewModel.device.username,
                errorMessage: viewModel.passwordPromptError,
                canRememberPassword: viewModel.canRememberPassword,
                onSubmit: { pwd, saveToKeychain in
                    viewModel.submitPassword(pwd, rememberInKeychain: saveToKeychain)
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
    }

    // MARK: - Canvas Rendering Layer

    @ViewBuilder
    private func remoteCanvas(geometry: GeometryProxy) -> some View {
        let imageWidth = CGFloat(viewModel.client.framebuffer.width)
        let imageHeight = CGFloat(viewModel.client.framebuffer.height)
        let safeWidth = max(imageWidth, 1)
        let safeHeight = max(imageHeight, 1)
        let fitScale = min(geometry.size.width / safeWidth, geometry.size.height / safeHeight)
        let canvasWidth = safeWidth * fitScale * viewModel.zoomScale
        let canvasHeight = safeHeight * fitScale * viewModel.zoomScale
        let originX = (geometry.size.width - canvasWidth) / 2 + viewModel.viewOffset.width
        let originY = (geometry.size.height - canvasHeight) / 2 + viewModel.viewOffset.height

        ZStack(alignment: .topLeading) {
            // High Performance Metal View
            if let renderer = viewModel.metalRenderer {
                MetalScreenView(renderer: renderer)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .position(x: originX + canvasWidth / 2, y: originY + canvasHeight / 2)
            } else if let cgImage = viewModel.currentImage {
                Image(decorative: cgImage, scale: 1.0)
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
                    let limitX = max(0, (canvasWidth - geometry.size.width) / 2)
                    let limitY = max(0, (canvasHeight - geometry.size.height) / 2)
                    viewModel.viewOffset.width = max(-limitX, min(limitX, viewModel.viewOffset.width + dx))
                    viewModel.viewOffset.height = max(-limitY, min(limitY, viewModel.viewOffset.height + dy))
                },
                onTextEvent: { text in viewModel.sendTextString(text) },
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

            // Virtual Cursor Overlay (in Trackpad mode on iOS)
            #if canImport(UIKit)
            if !viewModel.isObserveOnly && viewModel.inputMode == .trackpad && imageWidth > 0 && imageHeight > 0 {
                let cursorScreenX = originX + viewModel.trackpadEngine.cursorX * canvasWidth / imageWidth
                let cursorScreenY = originY + viewModel.trackpadEngine.cursorY * canvasHeight / imageHeight

                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .position(x: cursorScreenX, y: cursorScreenY)
            }
            #endif

            // Curtain Mode Active Overlay Banner
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
        #if canImport(UIKit)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                if viewModel.inputMode == .touch {
                    viewModel.trackpadEngine.handleDirectTouch(
                        point: CGPoint(x: point.x - originX, y: point.y - originY),
                        viewSize: CGSize(width: canvasWidth, height: canvasHeight)
                    )
                }
            case .ended:
                break
            }
        }
        .gesture(
            // Pan / Drag gesture with tactile haptics
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if let last = lastDragLocation {
                        let dx = value.location.x - last.x
                        let dy = value.location.y - last.y

                        if viewModel.inputMode == .trackpad {
                            viewModel.trackpadEngine.handlePanDelta(dx: dx, dy: dy)
                        } else {
                            viewModel.trackpadEngine.handleDirectTouch(
                                point: CGPoint(x: value.location.x - originX, y: value.location.y - originY),
                                viewSize: CGSize(width: canvasWidth, height: canvasHeight)
                            )
                        }
                    }
                    lastDragLocation = value.location
                }
                .onEnded { _ in
                    lastDragLocation = nil
                    if isDraggingMouse {
                        viewModel.trackpadEngine.endDrag()
                        isDraggingMouse = false
                    }
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .exclusively(before: SpatialTapGesture(count: 1))
                .onEnded { result in
                    switch result {
                    case .first:
                        viewModel.handleDoubleTapZoom()
                    case .second(let tap):
                        if viewModel.inputMode == .touch {
                            viewModel.trackpadEngine.handleDirectTouch(
                                point: CGPoint(x: tap.location.x - originX, y: tap.location.y - originY),
                                viewSize: CGSize(width: canvasWidth, height: canvasHeight)
                            )
                        }
                        viewModel.triggerHaptic()
                        viewModel.trackpadEngine.handleTap()
                    }
                }
        )
        .simultaneousGesture(
            // Pinch to Zoom
            MagnificationGesture()
                .onChanged { scale in
                    viewModel.zoomScale = max(1.0, min(scale, 4.0))
                }
        )
        #endif
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
            }
            .accessibilityLabel(AppLocalization.string("Disconnect"))

            // Machine Name & State Dot
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.sessionState == .connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.isObserveOnly ? AppLocalization.format("Observe · %@", viewModel.device.name) : viewModel.device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: sessionNameWidth, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())

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
                Toggle(AppLocalization.string("Observe Only"), isOn: $viewModel.isObserveOnly)
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
                #if os(macOS)
                Toggle(AppLocalization.string("Pan View"), isOn: $viewModel.isPanningViewport)
                    .disabled(viewModel.zoomScale <= 1)
                #endif
                Divider()
                ForEach(viewModel.multiDisplayManager.availableDisplays) { display in
                    Button {
                        viewModel.multiDisplayManager.selectDisplay(id: display.id)
                    } label: {
                        HStack {
                            Text(AppLocalization.message(display.name))
                            if viewModel.multiDisplayManager.selectedDisplayId == display.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Button {
                    viewModel.triggerHaptic()
                    viewModel.curtainManager.toggleCurtain()
                } label: {
                    Label(AppLocalization.string(viewModel.curtainManager.isCurtainActive ? "Dismiss Lock Notice" : "Lock Remote Mac"), systemImage: "lock")
                }
                .disabled(viewModel.isObserveOnly && !viewModel.curtainManager.isCurtainActive)
                Button { viewModel.reconnectSession() } label: {
                    Label(AppLocalization.string("Reconnect"), systemImage: "arrow.clockwise")
                }
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

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
    }

    private var sessionNameWidth: CGFloat {
        #if os(macOS)
        170
        #else
        90
        #endif
    }
}
