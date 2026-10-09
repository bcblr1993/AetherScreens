#if canImport(UIKit)
import SwiftUI
import UIKit
import Combine

struct ExternalPointerOverlay: UIViewRepresentable {
    let viewModel: SessionViewModel

    func makeUIView(context: Context) -> ExternalPointerView {
        let view = ExternalPointerView()
        view.subscription = viewModel.pointerUpdates.sink { [weak view] point in
            view?.updatePointer(point)
        }
        view.cursorSubscription = viewModel.cursorUpdates.sink { [weak view] shape in
            view?.arrow.setShape(shape)
        }
        return view
    }

    func updateUIView(_ uiView: ExternalPointerView, context: Context) {
        uiView.remoteRect = viewModel.activeCropRect
            ?? CGRect(x: 0, y: 0, width: viewModel.client.framebuffer.width, height: viewModel.client.framebuffer.height)
        uiView.setNeedsLayout()
    }
}

final class ExternalPointerView: UIView {
    var subscription: AnyCancellable?
    var remoteRect = CGRect.zero
    let arrow = RemoteCursorLayer()
    var cursorSubscription: AnyCancellable?
    private var pointer: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        arrow.isHidden = true
        layer.addSublayer(arrow)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updatePointer(_ point: CGPoint) {
        pointer = point
        positionArrow()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        positionArrow()
    }
    private func positionArrow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let pointer, let position = ExternalPointerGeometry.position(pointer, remoteRect: remoteRect, bounds: bounds)
        else { arrow.isHidden = true; return }
        arrow.position = position
        arrow.isHidden = false
    }
}
#endif
