import SwiftUI

struct ClipboardMenu: View {
    @ObservedObject var viewModel: SessionViewModel
    var body: some View {
        Menu(AppLocalization.string("Clipboard")) {
            Toggle(AppLocalization.string("Use Shared Clipboard"), isOn: Binding(
                get: { viewModel.sharedClipboardEnabled }, set: { viewModel.setSharedClipboard($0) }
            )).accessibilityIdentifier("session-shared-clipboard")
            Button(AppLocalization.string("Send Clipboard")) { viewModel.sendLocalClipboard() }
                .disabled(!viewModel.canSendClipboard)
                .accessibilityIdentifier("session-send-clipboard")
            Button(AppLocalization.string("Get Clipboard")) { viewModel.getRemoteClipboard() }
                .disabled(!viewModel.canGetClipboard)
                .accessibilityIdentifier("session-get-clipboard")
        }.accessibilityIdentifier("session-clipboard-menu")
    }
}
