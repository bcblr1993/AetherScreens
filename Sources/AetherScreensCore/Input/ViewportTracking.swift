import Foundation

/// Keeps immediate local navigation until SwiftUI supplies changed geometry.
struct ViewportProjection {
    private var lastLayout: CGRect?
    private var pendingPans: [CGRect] = []
    private(set) var canvas: CGRect = .zero

    mutating func applyLayout(_ rect: CGRect) {
        guard rect != lastLayout else { return }
        lastLayout = rect
        if let acknowledged = pendingPans.firstIndex(where: {
            // Local panning adds to the canvas origin; SwiftUI recomputes it
            // from the centered origin plus offset. Equivalent arithmetic can
            // differ by rounding. Keep size exact so zoom/resize still resets.
            $0.size == rect.size && abs($0.minX - rect.minX) <= 0.000001 &&
                abs($0.minY - rect.minY) <= 0.000001
        }) {
            // SwiftUI can acknowledge an earlier sample after another pointer
            // sample has already moved the canvas. Keep the newer projection.
            pendingPans.removeFirst(acknowledged + 1)
            return
        }
        pendingPans.removeAll(keepingCapacity: true)
        canvas = rect
    }

    mutating func pan(_ delta: CGSize) {
        guard delta != .zero else { return }
        canvas = canvas.offsetBy(dx: delta.width, dy: delta.height)
        pendingPans.append(canvas)
        // Bound history when a view stops receiving layout acknowledgements.
        if pendingPans.count > 128 { pendingPans.removeFirst() }
    }
}

/// Keeps a moving trackpad pointer inside a zoomed viewport without exposing
/// space beyond the remote desktop or disturbing an axis that already fits.
enum ViewportTracking {
    static func panDelta(canvas: CGRect, viewport: CGRect, pointer: CGPoint,
                         movement: CGSize, margin: CGFloat = 32) -> CGSize {
        func shift(origin: CGFloat, extent: CGFloat, viewportOrigin: CGFloat,
                   viewportExtent: CGFloat, position: CGFloat, direction: CGFloat) -> CGFloat {
            guard extent > viewportExtent, viewportExtent > 0 else { return 0 }
            let inset = min(margin, viewportExtent / 4)
            let lower = viewportOrigin + inset
            let upper = viewportOrigin + viewportExtent - inset
            let requested: CGFloat
            if direction < 0 && position < lower { requested = lower - position }
            else if direction > 0 && position > upper { requested = upper - position }
            else { return 0 }
            return max(viewportOrigin + viewportExtent - extent - origin,
                       min(viewportOrigin - origin, requested))
        }
        return CGSize(width: shift(origin: canvas.minX, extent: canvas.width,
                                   viewportOrigin: viewport.minX, viewportExtent: viewport.width,
                                   position: pointer.x, direction: movement.width),
                      height: shift(origin: canvas.minY, extent: canvas.height,
                                    viewportOrigin: viewport.minY, viewportExtent: viewport.height,
                                    position: pointer.y, direction: movement.height))
    }
}
