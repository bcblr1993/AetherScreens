import CoreGraphics

struct ScrollWheelAccumulator {
    private var remainderX: CGFloat = 0
    private var remainderY: CGFloat = 0
    private var previousPrecise: Bool?

    mutating func consume(dx: CGFloat, dy: CGFloat, precise: Bool, preciseDivisor: CGFloat = 10) -> [RFBConstants.ButtonMask] {
        // A mouse notch must not cancel against a fractional trackpad gesture.
        if let previousPrecise, previousPrecise != precise {
            remainderX = 0
            remainderY = 0
        }
        previousPrecise = precise
        let divisor: CGFloat = precise ? preciseDivisor : 1
        guard divisor.isFinite, divisor > 0 else { remainderX = 0; remainderY = 0; return [] }
        func ticks(delta: CGFloat, remainder: inout CGFloat) -> Int {
            guard delta.isFinite else { remainder = 0; return 0 }
            let total = remainder + delta / divisor
            guard total.isFinite else { remainder = 0; return 0 }
            // Keep sub-tick precision, but never replay overflow from a capped
            // event on subsequent zero-delta or opposite-direction events.
            remainder = total.truncatingRemainder(dividingBy: 1)
            let bounded = min(abs(total) + 1e-9, 64)
            let count = Int(bounded)
            if count > Int(min(abs(total), 64)) { remainder = 0 }
            return total >= 0 ? count : -count
        }
        let ticksX = ticks(delta: dx, remainder: &remainderX)
        let ticksY = ticks(delta: dy, remainder: &remainderY)
        return Array(repeating: ticksY > 0 ? .scrollUp : .scrollDown, count: abs(ticksY))
            + Array(repeating: ticksX > 0 ? .scrollLeft : .scrollRight, count: abs(ticksX))
    }
}
