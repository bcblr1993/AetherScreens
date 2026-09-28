import SwiftUI
import AetherScreensCore

@main
struct AetherScreensIOSApp: App {
    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .tint(.blue)
        }
    }
}
