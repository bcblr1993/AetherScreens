import SwiftUI

/// The same native menu is used in the session controls and keyboard toolbar.
struct HotCornerMenu: View {
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        if viewModel.device.deviceType == .mac {
            Group {
                if viewModel.canTriggerHotCorner {
                    Menu {
                        ForEach(TrackpadEngine.HotCorner.allCases) { corner in
                            Button(AppLocalization.string(corner.rawValue)) {
                                viewModel.triggerHotCorner(corner)
                            }
                            .accessibilityIdentifier("hot-corner-" + String(describing: corner))
                        }
                    } label: {
                        menuLabel
                    }
                } else {
                    // Native nested menus may keep their container enabled even
                    // with .disabled(). An unavailable action is a disabled row.
                    Button {} label: { menuLabel }
                        .disabled(true)
                }
            }
            .help(AppLocalization.string("Trigger a corner configured on the remote Mac's selected display"))
            .accessibilityIdentifier("session-hot-corners")
        }
    }

    private var menuLabel: some View {
        Label(AppLocalization.string("Hot Corners"), systemImage: "arrow.up.left.and.arrow.down.right")
    }
}
