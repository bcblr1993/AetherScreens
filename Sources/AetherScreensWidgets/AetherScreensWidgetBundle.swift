import SwiftUI
import WidgetKit

@main
struct AetherScreensWidgetBundle: WidgetBundle {
    var body: some Widget {
        SavedComputerWidget()
        #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        SessionLiveActivityWidget()
        #endif
    }
}
