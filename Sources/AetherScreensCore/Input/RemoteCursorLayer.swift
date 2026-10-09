#if canImport(UIKit)
import UIKit

/// Shape changes cache their image once; pointer samples only move this layer.
final class RemoteCursorLayer: CALayer {
    let fallback = CAShapeLayer()
    private let bitmap = CALayer()

    override init() {
        super.init()
        fallback.path = PointerArrowShape.path
        fallback.fillColor = UIColor.white.cgColor
        fallback.strokeColor = UIColor.black.cgColor
        fallback.lineWidth = 1.5
        fallback.lineJoin = .round
        bitmap.anchorPoint = .zero
        bitmap.contentsGravity = .resize
        addSublayer(fallback)
        addSublayer(bitmap)
        setShape(nil)
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setShape(_ shape: RFBRemoteCursor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let image = shape?.makeCGImage()
        let explicitlyHidden = shape?.isHidden == true
        fallback.isHidden = explicitlyHidden || image != nil
        bitmap.contents = image
        bitmap.isHidden = explicitlyHidden || image == nil
        guard let shape, !explicitlyHidden, image != nil else { return }
        bitmap.bounds = CGRect(x: 0, y: 0, width: shape.width, height: shape.height)
        bitmap.position = CGPoint(x: -shape.hotspotX, y: -shape.hotspotY)
    }
}
#endif
