import Foundation
import Combine

/// An external scene renders the same framebuffer with its own GPU state.
/// Availability never opts the user into displaying a remote session elsewhere.
@MainActor
public final class RemoteDisplayMirror: ObservableObject {
    @Published public private(set) var isAvailable = false
    @Published public private(set) var isMirroring = false
    public private(set) var canPresent = false
    var onEnabledChanged: ((Bool) -> Void)?
    private var presentationID: UUID?
    private var renderer: MetalScreenRenderer?

    public init() {}

    func updateAvailability(_ available: Bool) {
        if isAvailable != available { isAvailable = available }
        if !available { setMirroring(false) }
    }

    func updatePresentationAllowed(_ allowed: Bool) {
        canPresent = allowed
        if !allowed { setMirroring(false) }
    }

    public func setMirroring(_ enabled: Bool) {
        let next = enabled && isAvailable && canPresent
        guard next != isMirroring else { return }
        if !next {
            presentationID = nil
            renderer = nil
        }
        isMirroring = next
        onEnabledChanged?(next)
    }

    /// The external renderer must not steal the interactive renderer's MTKView
    /// or add its presentations to the interactive session's FPS counter.
    func beginPresentation(framebuffer: Framebuffer) -> (id: UUID, renderer: MetalScreenRenderer?)? {
        guard isMirroring, isAvailable, canPresent else { return nil }
        let id = UUID()
        let externalRenderer = MetalScreenRenderer(metrics: PerformanceMetrics())
        externalRenderer?.framebuffer = framebuffer
        presentationID = id
        renderer = externalRenderer
        return (id, externalRenderer)
    }

    func endPresentation(id: UUID) {
        guard presentationID == id else { return }
        setMirroring(false)
    }

    func notifyFrameUpdated() { renderer?.notifyFrameUpdated() }
}
