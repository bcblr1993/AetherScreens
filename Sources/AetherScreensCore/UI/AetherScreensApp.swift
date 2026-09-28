import SwiftUI

public struct AetherScreensApp: App {
    public init() {}
    public var body: some Scene {
        WindowGroup {
            DeviceListView()
                .tint(.blue)
        }
    }
}
