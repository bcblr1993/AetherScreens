import CoreGraphics

enum ExternalPointerGeometry {
    static func position(_ pointer: CGPoint, remoteRect: CGRect, bounds: CGRect) -> CGPoint? {
        guard remoteRect.width > 0, remoteRect.height > 0, bounds.width > 0, bounds.height > 0,
              remoteRect.width.isFinite, remoteRect.height.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, remoteRect.contains(pointer) else { return nil }
        let scale = min(bounds.width / remoteRect.width, bounds.height / remoteRect.height)
        return CGPoint(x: bounds.minX + (bounds.width - remoteRect.width * scale) / 2 + (pointer.x - remoteRect.minX) * scale,
                       y: bounds.minY + (bounds.height - remoteRect.height * scale) / 2 + (pointer.y - remoteRect.minY) * scale)
    }
}
