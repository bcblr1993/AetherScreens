import Foundation

/// Legacy Lock Remote Mac notice, retained for existing UI/test compatibility.
/// This local toggle is not evidence of remote privacy or Apple Curtain Mode.
/// Real console-visibility requests use RFBClient's separate curtain status.
public final class CurtainModeManager: ObservableObject, @unchecked Sendable {
    @Published public private(set) var isCurtainActive: Bool = false
    private let lock = NSLock()

    public var onCurtainStateChanged: (@Sendable (Bool) -> Void)?

    public init() {}

    /// Toggle the local lock-shortcut notice.
    public func toggleCurtain() {
        lock.lock()
        isCurtainActive.toggle()
        let active = isCurtainActive
        lock.unlock()

        onCurtainStateChanged?(active)
    }

    /// Set the local lock-shortcut notice explicitly.
    public func setCurtain(active: Bool) {
        lock.lock()
        isCurtainActive = active
        lock.unlock()

        onCurtainStateChanged?(active)
    }
}
