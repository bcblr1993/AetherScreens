#if os(macOS)
import Combine
import Foundation
import Sparkle

/// Sparkle owns archive verification, download, installation and relaunch UI.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?

    init() {
        // SwiftPM command-line builds have no configured .app bundle.
        let configured = Bundle.main.bundleIdentifier == "com.aethernative.aetherscreens"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
            && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
        controller = SPUStandardUpdaterController(startingUpdater: configured,
                                                  updaterDelegate: nil, userDriverDelegate: nil)
        guard configured else { return }
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.canCheckForUpdates = enabled }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
#endif
