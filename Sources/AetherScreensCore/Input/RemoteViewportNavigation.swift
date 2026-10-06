import CoreGraphics

/// Reveal a relative pointer without changing its remote coordinates or moving
/// the viewport beyond the desktop. Absolute touch/Pencil input stays anchored.
enum RemoteViewportNavigation {
    static func followDelta(cursor: CGPoint, remoteSize: CGSize, canvas: CGRect,
                            viewport: CGSize, margin: CGFloat = 28) -> CGSize {
        let values = [cursor.x, cursor.y, remoteSize.width, remoteSize.height,
                      canvas.minX, canvas.minY, canvas.width, canvas.height,
                      viewport.width, viewport.height, margin]
        guard values.allSatisfy(\.isFinite), remoteSize.width > 0, remoteSize.height > 0,
              canvas.width > 0, canvas.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        func delta(position: CGFloat, origin: CGFloat, extent: CGFloat, visible: CGFloat) -> CGFloat {
            guard extent > visible else { return 0 }
            let inset = max(0, min(margin, visible / 4))
            let desired = position < inset ? inset - position : position > visible - inset ? visible - inset - position : 0
            // The desktop must continue covering the viewport at either edge.
            return min(-origin, max(visible - extent - origin, desired))
        }
        let x = canvas.minX + min(remoteSize.width, max(0, cursor.x)) * canvas.width / remoteSize.width
        let y = canvas.minY + min(remoteSize.height, max(0, cursor.y)) * canvas.height / remoteSize.height
        return CGSize(width: delta(position: x, origin: canvas.minX, extent: canvas.width, visible: viewport.width),
                      height: delta(position: y, origin: canvas.minY, extent: canvas.height, visible: viewport.height))
    }
}
