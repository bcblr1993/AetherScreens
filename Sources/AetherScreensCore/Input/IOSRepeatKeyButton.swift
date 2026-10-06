#if canImport(UIKit)
import SwiftUI
import UIKit

/// Native tracking preserves ScrollView cancellation and VoiceOver activation.
struct IOSRepeatKeyButton: UIViewRepresentable {
    let title: String?
    let icon: String?
    let height: CGFloat
    let enabled: Bool
    let onBegin: () -> Void
    let onEnd: (Bool) -> Void
    let onActivate: () -> Void
    var accessibilityTitle: String? = nil

    func makeUIView(context: Context) -> RepeatButton {
        let button = RepeatButton(type: .custom)
        button.addTarget(button, action: #selector(RepeatButton.beginHold), for: .touchDown)
        button.addTarget(button, action: #selector(RepeatButton.finishHold), for: .touchUpInside)
        button.addTarget(button, action: #selector(RepeatButton.cancelHold), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        return button
    }
    func updateUIView(_ button: RepeatButton, context: Context) {
        button.onBegin = onBegin
        button.onEnd = onEnd
        button.onActivate = onActivate
        if !enabled && button.isEnabled { button.cancelHold() }
        button.isEnabled = enabled
        button.setTitle(title.map { AppLocalization.string($0) }, for: .normal)
        button.setImage(icon.flatMap { UIImage(systemName: $0) }, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.tintColor = .label
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.12)
        button.layer.cornerRadius = 8
        let arrowLabels = ["arrow.left": "Left Arrow", "arrow.up": "Up Arrow", "arrow.down": "Down Arrow", "arrow.right": "Right Arrow"]
        button.accessibilityLabel = accessibilityTitle.map { AppLocalization.string($0) } ?? title.map { AppLocalization.string($0) } ?? icon.map { AppLocalization.string(arrowLabels[$0] ?? $0) }
        button.alpha = enabled ? 1 : 0.4
    }
    static func dismantleUIView(_ button: RepeatButton, coordinator: ()) { button.cancelHold() }

    final class RepeatButton: UIButton {
        var onBegin: (() -> Void)?
        var onEnd: ((Bool) -> Void)?
        var onActivate: (() -> Void)?
        private var trackingHold = false
        @objc func beginHold() { trackingHold = true; onBegin?() }
        @objc func finishHold() {
            guard trackingHold else { return }
            trackingHold = false
            onEnd?(true)
        }
        @objc func cancelHold() {
            guard trackingHold else { return }
            trackingHold = false
            onEnd?(false)
        }
        override func accessibilityActivate() -> Bool {
            guard isEnabled else { return false }
            onActivate?()
            return true
        }
        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.6 : 1 }
        }
    }
}
#endif
