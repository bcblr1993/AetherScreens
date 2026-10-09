import Foundation

/// Tracks the local Lock Screen shortcut notice; it does not implement remote Curtain mode.
public final class CurtainModeManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isCurtainActive: Bool = false
    private let lock = NSLock()

    public var onCurtainStateChanged: (@Sendable (Bool) -> Void)?

    public init() {}

    /// Toggle the local shortcut notice.
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
