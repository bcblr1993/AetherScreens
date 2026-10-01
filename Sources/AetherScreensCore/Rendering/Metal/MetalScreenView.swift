import SwiftUI
import MetalKit

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper for MTKView on iOS / iPadOS
public struct MetalScreenView: UIViewRepresentable {
    public let renderer: MetalScreenRenderer
    public let sourceRect: CGRect?

    public init(renderer: MetalScreenRenderer, sourceRect: CGRect? = nil) {
        self.renderer = renderer
        self.sourceRect = sourceRect
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        // The display can accept 120 Hz updates, but remains idle between remote frames.
        mtkView.preferredFramesPerSecond = 120
        mtkView.contentMode = .scaleAspectFit
        renderer.setSourceRect(sourceRect)
        renderer.attach(to: mtkView)
        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        renderer.setSourceRect(sourceRect)
    }
}

#elseif canImport(AppKit)
import AppKit

/// SwiftUI wrapper for MTKView on macOS (Apple Silicon Mac)
public struct MetalScreenView: NSViewRepresentable {
    public let renderer: MetalScreenRenderer
    public let sourceRect: CGRect?

    public init(renderer: MetalScreenRenderer, sourceRect: CGRect? = nil) {
        self.renderer = renderer
        self.sourceRect = sourceRect
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        // Support ProMotion (120Hz) on MacBook Pro Liquid Retina XDR
        mtkView.preferredFramesPerSecond = 120
        renderer.setSourceRect(sourceRect)
        renderer.attach(to: mtkView)
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        renderer.setSourceRect(sourceRect)
    }
}
#endif
