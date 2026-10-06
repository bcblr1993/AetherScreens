import Foundation

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
