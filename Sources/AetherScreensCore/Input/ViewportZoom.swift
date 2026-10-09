import Foundation

/// Preserves the remote point beneath a local pinch anchor, within desktop bounds.
enum ViewportZoom {
    static func offset(current: CGSize, oldScale: CGFloat, newScale: CGFloat,
                       baseCanvas: CGSize, viewport: CGSize, anchor: CGPoint) -> CGSize {
        guard oldScale > 0, newScale > 0, oldScale.isFinite, newScale.isFinite,
              baseCanvas.width > 0, baseCanvas.height > 0,
              viewport.width > 0, viewport.height > 0,
              anchor.x.isFinite, anchor.y.isFinite else { return .zero }
        let ratio = newScale / oldScale
        func axis(offset: CGFloat, base: CGFloat, extent: CGFloat, anchor: CGFloat) -> CGFloat {
            let oldLimit = max(0, (base * oldScale - extent) / 2)
            let clamped = max(-oldLimit, min(oldLimit, offset))
            let relative = anchor - extent / 2
            let projected = relative - ratio * (relative - clamped)
            let limit = max(0, (base * newScale - extent) / 2)
            return max(-limit, min(limit, projected))
        }
        return CGSize(width: axis(offset: current.width, base: baseCanvas.width,
                                  extent: viewport.width, anchor: anchor.x),
                      height: axis(offset: current.height, base: baseCanvas.height,
                                   extent: viewport.height, anchor: anchor.y))
    }
}
