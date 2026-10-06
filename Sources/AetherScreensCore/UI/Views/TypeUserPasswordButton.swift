import SwiftUI

/// Native pointer tracking distinguishes a click from a held click and cancels
/// while scrolling off the button. Authentication starts only after release.
struct TypeUserPasswordButton: View {
    @ObservedObject var viewModel: SessionViewModel
    let height: CGFloat
    @State private var beganAt: TimeInterval?

    var body: some View {
        #if canImport(UIKit)
        IOSRepeatKeyButton(title: nil, icon: "key.fill", height: height,
            enabled: viewModel.canTypeUserPassword,
            onBegin: { beganAt = ProcessInfo.processInfo.systemUptime },
            onEnd: { accepted in
                let duration = beganAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
                beganAt = nil
                if accepted { viewModel.typeUserPassword(pressReturn: duration < 0.5) }
            }, onActivate: { viewModel.typeUserPassword() },
            accessibilityTitle: "Type User Password")
        .frame(width: height, height: height)
        .accessibilityIdentifier("type-user-password")
        #elseif canImport(AppKit)
        MacPasswordButton(enabled: viewModel.canTypeUserPassword) { viewModel.typeUserPassword(pressReturn: $0) }
            .frame(width: height, height: height)
            .help(AppLocalization.string("Hold to type without pressing Return."))
        #endif
    }
}

#if canImport(AppKit)
import AppKit

private struct MacPasswordButton: NSViewRepresentable {
    let enabled: Bool
    let activate: (Bool) -> Void
    func makeNSView(context: Context) -> PasswordButton {
        let button = PasswordButton()
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = button
        button.action = #selector(PasswordButton.activatePassword)
        button.setAccessibilityIdentifier("type-user-password")
        return button
    }
    func updateNSView(_ button: PasswordButton, context: Context) {
        button.isEnabled = enabled
        button.activate = activate
        button.setAccessibilityLabel(AppLocalization.string("Type User Password"))
    }
    final class PasswordButton: NSButton {
        var activate: ((Bool) -> Void)?
        private var beganAt: TimeInterval?
        override func mouseDown(with event: NSEvent) {
            beganAt = ProcessInfo.processInfo.systemUptime
            defer { beganAt = nil }
            super.mouseDown(with: event)
        }
        @objc func activatePassword() {
            let duration = beganAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
            activate?(duration < 0.5)
        }
    }
}
#endif
