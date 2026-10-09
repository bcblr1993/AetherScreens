import Foundation

/// First-frame pixel transfer: allow progress, bound both stalls and total time.
/// Shared by ordinary RFB and the experimental native record transport.
struct NativeFirstFrameDeadline {
    let started: TimeInterval
    private(set) var lastProgress: TimeInterval
    init(now: TimeInterval) { started = now; lastProgress = now }
    mutating func recordPayloadProgress(now: TimeInterval) {
        lastProgress = max(lastProgress, now)
    }
    func remaining(now: TimeInterval) -> TimeInterval {
        max(0, min(started + 60 - now, lastProgress + 20 - now))
    }
}
