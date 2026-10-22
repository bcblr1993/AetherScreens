import CoreGraphics

/// Decides when the session's floating top bar is shown so it stops covering the remote screen.
/// The view feeds pointer positions and pin state, and runs the single pending timer this state asks for.
struct SessionTopBarAutoHide: Equatable {
    enum Timer: Equatable { case reveal, hide }
    /// Only zone crossings matter, so ordinary pointer motion leaves the state unchanged.
    private enum PointerZone: Equatable { case revealing, onBar, elsewhere }

    /// Pointer distance from the top edge that starts revealing a hidden bar.
    static let revealZone: CGFloat = 6
    /// Pointer distance from the top edge that keeps a revealed bar visible (covers the bar itself).
    static let retainZone: CGFloat = 64
    static let revealDelay: Double = 0.3
    static let hideDelay: Double = 1.5

    private(set) var isRevealed = true
    private(set) var isPinned = true
    private(set) var pendingTimer: Timer?
    /// Changes whenever the pending timer changes, so stale timers can be told apart and cancelled.
    private(set) var timerGeneration = 0
    private var pointerZone = PointerZone.elsewhere

    static func delay(for timer: Timer) -> Double {
        timer == .reveal ? revealDelay : hideDelay
    }

    mutating func setPinned(_ pinned: Bool) {
        guard pinned != isPinned else { return }
        isPinned = pinned
        if pinned {
            isRevealed = true
            schedule(nil)
        } else {
            reevaluate()
        }
    }

    /// `y` is the distance from the top edge; nil means the pointer left the session view.
    mutating func pointerMoved(toY y: CGFloat?) {
        pointerZone = switch y {
        case let y? where y <= Self.revealZone: .revealing
        case let y? where y <= Self.retainZone: .onBar
        default: .elsewhere
        }
        reevaluate()
    }

    mutating func timerFired(_ timer: Timer, generation: Int) {
        guard timer == pendingTimer, generation == timerGeneration, !isPinned else { return }
        isRevealed = timer == .reveal
        schedule(nil)
    }

    private mutating func reevaluate() {
        guard !isPinned else { return }
        let wanted: Timer?
        if isRevealed {
            wanted = pointerZone == .elsewhere ? .hide : nil
        } else {
            wanted = pointerZone == .revealing ? .reveal : nil
        }
        // Keep a running timer: restarting it on every move would let continuous motion defer it forever.
        if wanted != pendingTimer { schedule(wanted) }
    }

    private mutating func schedule(_ timer: Timer?) {
        pendingTimer = timer
        timerGeneration &+= 1
    }
}
