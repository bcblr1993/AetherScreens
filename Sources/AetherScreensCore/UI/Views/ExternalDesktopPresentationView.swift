import SwiftUI

/// A presentation surface; session ownership and input remain on the controlling device.
public struct ExternalDesktopPresentationView: View {
    @ObservedObject private var registry: SessionRegistry
    @ObservedObject private var languageSettings = AppLanguageSettings.shared

    public init(registry: SessionRegistry? = nil) {
        self.registry = registry ?? .shared
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let id = registry.activeSessionID, let session = registry.session(for: id) {
                ExternalSessionCanvas(viewModel: session).id(id)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").font(.system(size: 48))
                    Text(AppLocalization.string("Connect to a computer to show its desktop here."))
                        .font(.title2)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(40)
            }
        }
        .accessibilityIdentifier("external-desktop-presentation")
    }
}

private final class ExternalCanvasRenderer: ObservableObject {
    let renderer: MetalScreenRenderer?
    init(viewModel: SessionViewModel) {
        renderer = MetalScreenRenderer(metrics: PerformanceMetrics())
        renderer?.framebuffer = viewModel.client.framebuffer
    }
}

private struct ExternalSessionCanvas: View {
    @ObservedObject var viewModel: SessionViewModel
    @StateObject private var surface: ExternalCanvasRenderer

    init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
        _surface = StateObject(wrappedValue: ExternalCanvasRenderer(viewModel: viewModel))
    }

    private var connectionLabel: String {
        switch viewModel.sessionState {
        case .disconnected, .failed: return "Disconnected"
        default: return "Connecting…"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.sessionState == .connected && viewModel.hasReceivedFirstFrame {
                    let crop = viewModel.activeCropRect
                    let width = crop?.width ?? CGFloat(viewModel.client.framebuffer.width)
                    let height = crop?.height ?? CGFloat(viewModel.client.framebuffer.height)
                    let ratio = max(width, 1) / max(height, 1)
                    if let renderer = surface.renderer {
                        MetalScreenView(renderer: renderer, sourceRect: crop)
                            .aspectRatio(ratio, contentMode: .fit)
                    } else if let image = viewModel.currentImage {
                        Image(decorative: crop.flatMap { image.cropping(to: $0) } ?? image, scale: 1)
                            .resizable().aspectRatio(contentMode: .fit)
                    }
                    #if canImport(UIKit)
                    ExternalPointerOverlay(viewModel: viewModel)
                    #endif
                } else {
                    VStack(spacing: 12) {
                        Text(viewModel.device.name).font(.title2)
                        Text(AppLocalization.string(connectionLabel))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onReceive(viewModel.frameUpdates) { surface.renderer?.notifyFrameUpdated() }
        .onAppear { surface.renderer?.notifyFrameUpdated() }
        .allowsHitTesting(false)
    }
}
