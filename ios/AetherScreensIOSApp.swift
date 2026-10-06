import SwiftUI
import AetherScreensCore

@main
struct AetherScreensIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ForegroundLibraryRootView()
                .tint(.blue)
        }
    }
}
