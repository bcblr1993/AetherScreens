import Foundation

/// Manages Curtain Mode (幕帘模式) - prevents physical onlookers at the remote Mac from viewing session activity.
public final class CurtainModeManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isCurtainActive: Bool = false
    private let lock = NSLock()

    public var onCurtainStateChanged: (@Sendable (Bool) -> Void)?

    public init() {}

    /// Toggle curtain mode on remote Mac
    public func toggleCurtain() {
        lock.lock()
        isCurtainActive.toggle()
        let active = isCurtainActive
        lock.unlock()

        onCurtainStateChanged?(active)
    }

    /// Set curtain state explicitly
    public func setCurtain(active: Bool) {
        lock.lock()
        isCurtainActive = active
        lock.unlock()

        onCurtainStateChanged?(active)
    }
}
