import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Metal-backed remote desktop with native input, viewport controls and session diagnostics.
public struct RemoteDesktopView: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    @ObservedObject public var viewModel: SessionViewModel
    @ObservedObject private var displayManager: MultiDisplayManager
    @ObservedObject private var lockNotice: CurtainModeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if canImport(UIKit)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    @State private var showingLogs: Bool = false
    @State private var showingKeyboardCustomization = false
    @State private var showingDisplayQuality = false
    @State private var showingFileUpload = false
    @State private var droppedUploadURL: URL?
    @State private var isUploadDropTargeted = false
    @State private var showingFileDownload = false
    private let managesSessionLifecycle: Bool
    private let onDisconnect: (() -> Void)?
    private let onReturnToLibrary: (() -> Void)?

    public init(viewModel: SessionViewModel, managesSessionLifecycle: Bool = true, onDisconnect: (() -> Void)? = nil,
                onReturnToLibrary: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.displayManager = viewModel.multiDisplayManager
        self.lockNotice = viewModel.curtainManager
        self.managesSessionLifecycle = managesSessionLifecycle
        self.onDisconnect = onDisconnect
        self.onReturnToLibrary = onReturnToLibrary
    }

    // Connection failures must reveal controls even when the session prefers fullscreen.
    private var usesFullscreenLayout: Bool { viewModel.isFullscreen && viewModel.sessionState == .connected }

    private var canAcceptFileDrop: Bool {
        viewModel.canStartFileUpload && !showingFileUpload && !showingFileDownload &&
            !showingLogs && !showingKeyboardCustomization && !showingDisplayQuality
    }

    private var isWaitingForFirstFrame: Bool {
        (viewModel.sessionState == .connected || viewModel.sessionState == .initializing)
            && !viewModel.hasReceivedFirstFrame
    }

    public var body: some View {
        GeometryReader { geometry in
            #if os(iOS)
            let sideDock = UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height
            let carouselDock = viewModel.keyboardConfiguration.position == .carousel
            let floatingDock = UIDevice.current.userInterfaceIdiom == .pad && viewModel.keyboardConfiguration.position == .floating
            #else
            let sideDock = false
            let floatingDock = false
            let carouselDock = false
            #endif
            ZStack {
                Color(red: 0.055, green: 0.07, blue: 0.09).ignoresSafeArea()

                // Remote Screen View (Metal accelerated if available)
                if viewModel.sessionState == .connected || viewModel.currentImage != nil {
                    remoteCanvas(geometry: geometry)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(viewModel.hasReceivedFirstFrame ? "remote-desktop-frame" : "remote-desktop-loading")
                        .overlay {
                            if viewModel.sessionState != .connected && viewModel.sessionState != .initializing {
                                ZStack {
                                    Color.black.opacity(0.65)
                                    connectingStateView
                                }
                            }
                        }
                } else {
                    connectingStateView
                }

                // Initial Frame Loading HUD
                ZStack {
                    if isWaitingForFirstFrame {
                        firstFrameLoadingHUD
                            .frame(maxWidth: min(360, max(0, geometry.size.width - 32)))
                    }
                }
                // Animate HUD insertion/removal independently of framebuffer and input updates.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isWaitingForFirstFrame)

                // Floating Top Controls Bar & Diagnostic HUD
                if !usesFullscreenLayout {
                    let toolbarAtTop = sideDock || viewModel.keyboardConfiguration.position == .top
                    ZStack(alignment: toolbarAtTop ? .topLeading : .bottomLeading) {
                        VStack {
                            floatingTopBar(availableWidth: geometry.size.width).padding(.top, 12)
                            Spacer()
                        }
                        if viewModel.isKeyboardVisible && !floatingDock && !carouselDock {
                            // Keep one view identity across rotation so expansion and focus survive.
                            MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization, usesSideDock: sideDock)
                                .padding(.top, toolbarAtTop ? 76 : 0)
                                .transition(reduceMotion ? .opacity : .move(edge: sideDock ? .leading : (toolbarAtTop ? .top : .bottom)).combined(with: .opacity))
                        }
                    }
                    // Animate controls only; pointer and framebuffer updates must stay immediate.
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9),
                               value: viewModel.isKeyboardVisible)
                }
                // Animate overlay presentation without carrying its transaction
                // into the remote canvas or pointer transport.
                ZStack {
                    if !usesFullscreenLayout && viewModel.isKeyboardVisible && floatingDock {
                        FloatingKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingKeyboardCustomization)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                    #if os(iOS)
                    if !usesFullscreenLayout && viewModel.isKeyboardVisible && carouselDock {
                        CarouselKeyboardToolbar(viewModel: viewModel) {
                            if let onDisconnect { onDisconnect() }
                            else { viewModel.requestDisconnect(); dismiss() }
                        }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                    #endif
                }
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9),
                           value: viewModel.isKeyboardVisible)
            }
        }
        .overlay(alignment: .topTrailing) {
            FileTransferProgressView(store: viewModel.fileTransfers)
                .padding(12)
                #if canImport(UIKit)
                .padding(.top, usesFullscreenLayout ? 0 : 76)
                #else
                .padding(.top, 44)
                #endif
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.passwordSaveNotice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(AppLocalization.string(notice)).font(.caption)
                    Spacer(minLength: 0)
                    Button { viewModel.passwordSaveNotice = nil } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalization.string("Dismiss"))
                    .accessibilityHint(AppLocalization.string("Close this notice and continue the connection."))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, usesFullscreenLayout ? 12 : 68)
                .accessibilityIdentifier("password-save-notice")
            }
        }
        #if canImport(UIKit)
        .ignoresSafeArea(usesFullscreenLayout ? .all : [])
        .statusBarHidden(usesFullscreenLayout)
        #endif
        .onAppear {
            if managesSessionLifecycle { viewModel.startSession() }
        }
        .onDisappear {
            if managesSessionLifecycle { viewModel.endSession() }
        }
        #if canImport(UIKit)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: viewModel.setForegroundSession(false)
            case .active: viewModel.setForegroundSession(true)
            // System authentication and transient overlays may be inactive.
            case .inactive: break
            @unknown default: break
            }
        }
        #endif
        .alert(AppLocalization.string("Clipboard"), isPresented: Binding(
            get: { viewModel.clipboardTransferNotice != nil },
            set: { if !$0 { viewModel.clipboardTransferNotice = nil } }
        )) {
            Button(AppLocalization.string("OK"), role: .cancel) { viewModel.clipboardTransferNotice = nil }
        } message: {
            Text(AppLocalization.string(viewModel.clipboardTransferNotice ?? ""))
        }
        .sheet(item: Binding(
            get: { viewModel.sshPrompt },
            // The sheet cancels using its captured prompt identity on disappear;
            // a delayed dismissal must not cancel a newer confirmation phase.
            set: { _ in }
        )) { prompt in
            SessionSSHSheet(viewModel: viewModel, prompt: prompt)
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
        .sheet(isPresented: $showingDisplayQuality) {
            DisplayQualitySettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingFileUpload, onDismiss: { droppedUploadURL = nil }) {
            FileUploadSheet(viewModel: viewModel, initialURL: droppedUploadURL)
        }
        .sheet(isPresented: $showingFileDownload) {
            FileDownloadSheet(viewModel: viewModel)
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
                cursorUpdates: viewModel.cursorUpdates,
                remoteWidth: imageWidth > 0 ? imageWidth : 1920,
                remoteHeight: imageHeight > 0 ? imageHeight : 1080,
                viewport: CGRect(x: -originX, y: -originY,
                    width: geometry.size.width, height: geometry.size.height),
                isPanning: viewModel.isPanningViewport,
                onPan: { dx, dy in
                    viewModel.panViewport(dx: dx, dy: dy, limitX: limitX, limitY: limitY)
                },
                onMagnification: { factor, anchor in
                    let scale = max(1, min(max(4, viewModel.actualSizeZoomScale), viewModel.zoomScale * factor))
                    let offset = ViewportZoom.offset(current: viewModel.viewOffset,
                        oldScale: viewModel.zoomScale, newScale: scale,
                        baseCanvas: CGSize(width: safeWidth * fitScale, height: safeHeight * fitScale),
                        viewport: geometry.size, anchor: anchor)
                    if offset != viewModel.viewOffset { viewModel.viewOffset = offset }
                    if scale != viewModel.zoomScale { viewModel.zoomScale = scale }
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

            #if canImport(UIKit)
            IOSRemoteInputView(
                cursorUpdates: viewModel.cursorUpdates,
                engine: viewModel.trackpadEngine,
                canvas: CGRect(x: originX, y: originY, width: canvasWidth, height: canvasHeight),
                zoom: viewModel.zoomScale,
                maximumZoom: max(4, viewModel.actualSizeZoomScale),
                isPanning: viewModel.isPanningViewport,
                isObserveOnly: viewModel.isObserveOnly,
                isFullscreen: usesFullscreenLayout,
                onToggleFullscreen: { viewModel.toggleFullscreen() },
                onThreeFingerSwipe: { viewModel.handleThreeFingerSwipe($0) },
                onPan: { dx, dy in
                    viewModel.panViewport(dx: dx, dy: dy, limitX: limitX, limitY: limitY)
                },
                onZoom: { scale, anchor in
                    let offset = ViewportZoom.offset(current: viewModel.viewOffset,
                        oldScale: viewModel.zoomScale, newScale: scale,
                        baseCanvas: CGSize(width: safeWidth * fitScale, height: safeHeight * fitScale),
                        viewport: geometry.size, anchor: anchor)
                    if offset != viewModel.viewOffset { viewModel.viewOffset = offset }
                    if scale != viewModel.zoomScale { viewModel.zoomScale = scale }
                },
                onKeyEvent: { viewModel.remoteInteraction.send(); viewModel.sendNativeKey(down: $0, keySym: $1) },
                onRemoteInteraction: { viewModel.remoteInteraction.send() },
                onPencilToolbarToggle: { location in
                    guard !usesFullscreenLayout, viewModel.keyboardConfiguration.position == .carousel,
                          viewModel.isKeyboardVisible else { return }
                    viewModel.pencilToolbarToggle.send(location)
                }
            )
            .id(viewModel.inputGeneration)
            .frame(width: geometry.size.width, height: geometry.size.height)
            #endif

            // Observe the notice directly so it updates without another frame.
            if lockNotice.isCurtainActive {
                VStack {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            lockNoticeMessage
                            lockNoticeActions
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            lockNoticeMessage
                            lockNoticeActions
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.purple.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    .padding(.horizontal, 12)
                    .padding(.top, 60)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            ZStack {
                if isUploadDropTargeted && canAcceptFileDrop {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .padding(8)
                        Label(AppLocalization.string("Drop a file or folder to choose where to send it"), systemImage: "doc.badge.arrow.up")
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(24)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isUploadDropTargeted)
        }
        .dropDestination(for: URL.self, action: { urls, _ in
            guard canAcceptFileDrop, urls.count == 1,
                  let url = urls.first, url.isFileURL else { return false }
            isUploadDropTargeted = false
            droppedUploadURL = url
            viewModel.fileUploadNotice = nil
            showingFileUpload = true
            return true
        }, isTargeted: { isUploadDropTargeted = $0 })
        .onChange(of: fitScale, initial: true) { _, scale in
            viewModel.actualSizeZoomScale = max(1, 1 / max(0.001, scale * displayScale))
        }
        .onChange(of: CGSize(width: limitX, height: limitY), initial: true) { _, limits in
            // Persist the visible clamp after zoom, rotation or display changes;
            // otherwise zooming back in restores an obsolete off-screen offset.
            viewModel.panViewport(dx: 0, dy: 0, limitX: limits.width, limitY: limits.height)
        }
    }

    private var lockNoticeMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 18))
                .accessibilityHidden(true)
            Text(AppLocalization.string("Lock Screen shortcut sent"))
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockNoticeActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                lockNoticeDismissAction
                lockNoticeReconnectAction
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                lockNoticeDismissAction
                lockNoticeReconnectAction
            }
        }
    }

    private var lockNoticeDismissAction: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                lockNotice.toggleCurtain()
            }
        } label: {
            Text(AppLocalization.string("Dismiss"))
                .font(.caption2.weight(.bold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var lockNoticeReconnectAction: some View {
        Button {
            viewModel.reconnectSession()
        } label: {
            Text(AppLocalization.string("Reconnect"))
                .font(.caption2.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string("Restore the session if input stops responding after unlocking"))
    }

    // MARK: - Connecting State

    private var hasConnectionFailure: Bool {
        if case .failed = viewModel.sessionState { return true }
        return false
    }

    private var connectingStateView: some View {
        ScrollView {
            connectionStatusContent
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .padding(.top, 76)
        .padding(.bottom, 24)
        .accessibilityIdentifier("connection-recovery")
    }

    private var connectionRetryAction: some View {
        Button { viewModel.reconnectSession() } label: {
            Text(AppLocalization.string("Retry Connection"))
                .frame(minHeight: 44)
        }
            .buttonStyle(.borderedProminent)
    }

    private var connectionPasswordAction: some View {
        Button { viewModel.isPromptingPassword = true } label: {
            Label(AppLocalization.string("Enter Password"), systemImage: "key.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var connectionStatusContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "display")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            if viewModel.isAwaitingAutomaticReconnect || (viewModel.sessionState != .disconnected && !hasConnectionFailure) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            Text(AppLocalization.string(statusDescription))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.85))

            Text(viewModel.device.name)
                .font(.headline)
                .foregroundStyle(.white)

            Text(viewModel.device.host)
                .font(.caption.monospaced())
                .foregroundColor(.white.opacity(0.5))

            if case .failed(let err) = viewModel.sessionState {
                Text(AppLocalization.message(err))
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if viewModel.sessionState == .disconnected || hasConnectionFailure {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        connectionRetryAction
                        connectionPasswordAction
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 12) {
                        connectionRetryAction
                        connectionPasswordAction
                    }
                }
                .padding(.top, 4)

                Button {
                    showingLogs = true
                } label: {
                    Label(AppLocalization.string("View Diagnostic Logs"), systemImage: "text.book.closed")
                        .font(.caption)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
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
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)

            if let progress = viewModel.downloadProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.current, total: progress.total)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                        .frame(maxWidth: .infinity)

                    Text(AppLocalization.format("Received %.1f MB / %.1f MB (%.0f%%)", progress.current, progress.total, (progress.current / progress.total) * 100))
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.75))
                }
            } else {
                Text(AppLocalization.string("Connected. Waiting for remote frames…"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 20)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
    }

    private var statusDescription: String {
        if viewModel.isAwaitingAutomaticReconnect { return "Connection lost. Retrying automatically…" }
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

    private func floatingTopBar(availableWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            // Close / Disconnect
            Button {
                if let onDisconnect {
                    onDisconnect()
                } else {
                    viewModel.requestDisconnect()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                    #if canImport(UIKit)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    #endif
            }
            .accessibilityLabel(AppLocalization.string("Disconnect"))

            // Machine Name & State Dot
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.sessionState == .connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(sessionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: sessionNameWidth(availableWidth: availableWidth), alignment: .leading)
                    .accessibilityLabel(sessionTitle)
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
                if let onReturnToLibrary {
                    Button(action: onReturnToLibrary) {
                        Label(AppLocalization.string("Return to Computers"), systemImage: "rectangle.grid.2x2")
                    }
                    .accessibilityIdentifier("session-return-to-library")
                    Divider()
                }
                Button { droppedUploadURL = nil; viewModel.fileUploadNotice = nil; showingFileUpload = true } label: {
                    Label(AppLocalization.string("Send File or Folder"), systemImage: "doc.badge.arrow.up")
                }
                .disabled(!viewModel.canStartFileUpload)
                .accessibilityIdentifier("session-send-file")
                Button { viewModel.fileDownloadNotice = nil; showingFileDownload = true } label: {
                    Label(AppLocalization.string("Receive File or Folder"), systemImage: "arrow.down.doc")
                }
                .disabled(!viewModel.canStartFileDownload)
                .accessibilityIdentifier("session-receive-file")
                Toggle(AppLocalization.string("Observe Only"), isOn: $viewModel.isObserveOnly)
                Button { showingKeyboardCustomization = true } label: {
                    Label(AppLocalization.string("Customize Keyboard Toolbar"), systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("session-customize-keyboard")
                Button { showingDisplayQuality = true } label: {
                    Label(AppLocalization.string("Display Quality"), systemImage: "photo")
                }
                .accessibilityIdentifier("session-display-quality")
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
                Toggle(AppLocalization.string("Pan View"), isOn: $viewModel.isPanningViewport)
                    #if canImport(UIKit)
                    .disabled(viewModel.zoomScale <= 1 || viewModel.isObserveOnly)
                    #else
                    .disabled(viewModel.zoomScale <= 1)
                    #endif
                Divider()
                ForEach(displayManager.availableDisplays) { display in
                    Button {
                        displayManager.selectDisplay(id: display.id)
                    } label: {
                        HStack {
                            Text(AppLocalization.message(display.name))
                            if displayManager.selectedDisplayId == display.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Button {
                    viewModel.triggerHaptic()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        lockNotice.toggleCurtain()
                    }
                } label: {
                    Label(AppLocalization.string(lockNotice.isCurtainActive ? "Dismiss Lock Notice" : "Lock Remote Mac"), systemImage: "lock")
                }
                .disabled(viewModel.isObserveOnly && !lockNotice.isCurtainActive)
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
            .accessibilityLabel(AppLocalization.string("Input Mode"))
            #endif

            // Keyboard Toolbar Toggle
            Button {
                viewModel.isKeyboardVisible.toggle()
            } label: {
                controlIcon("keyboard")
            }
            .accessibilityLabel(AppLocalization.string(viewModel.isKeyboardVisible ? "Hide Keyboard" : "Show Keyboard"))
            .disabled(viewModel.isObserveOnly)
        }
        .buttonStyle(ControlPressStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(.horizontal, 12)
    }

    private func controlIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            #if canImport(UIKit)
            .frame(width: 44, height: 44)
            #else
            .frame(width: 34, height: 34)
            #endif
            .contentShape(Rectangle())
    }

    private var sessionTitle: String {
        if viewModel.isObserveOnly { return AppLocalization.format("Observe · %@", viewModel.device.name) }
        if viewModel.isPanningViewport { return AppLocalization.format("Pan · %@", viewModel.device.name) }
        return viewModel.device.name
    }

    private func sessionNameWidth(availableWidth: CGFloat) -> CGFloat {
        #if os(macOS)
        return min(170, max(30, availableWidth - 500))
        #else
        return min(260, max(30, availableWidth - 296))
        #endif
    }
}
