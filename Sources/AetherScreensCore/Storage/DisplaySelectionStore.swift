import Foundation

/// Per-device remembered display selection and virtual split mode.
public struct DisplaySelectionPreference: Codable, Equatable, Sendable {
    public var selectedDisplayID: Int
    public var virtualSplitModeRawValue: String

    public var virtualSplitMode: MultiDisplayManager.VirtualSplitMode {
        MultiDisplayManager.VirtualSplitMode(rawValue: virtualSplitModeRawValue) ?? .none
    }

    public init(selectedDisplayID: Int = 0, virtualSplitMode: MultiDisplayManager.VirtualSplitMode = .none) {
        self.selectedDisplayID = selectedDisplayID
        self.virtualSplitModeRawValue = virtualSplitMode.rawValue
    }
}

public final class DisplaySelectionStore: @unchecked Sendable {
    public static let shared = DisplaySelectionStore()

    private let defaults: UserDefaults
    private let keyPrefix = "com.aetherscreens.displaySelection."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(for deviceID: UUID) -> DisplaySelectionPreference? {
        guard let data = defaults.data(forKey: keyPrefix + deviceID.uuidString) else { return nil }
        return try? JSONDecoder().decode(DisplaySelectionPreference.self, from: data)
    }

    public func save(_ preference: DisplaySelectionPreference, for deviceID: UUID) {
        if let data = try? JSONEncoder().encode(preference) {
            defaults.set(data, forKey: keyPrefix + deviceID.uuidString)
        }
    }

    public func remove(for deviceID: UUID) {
        defaults.removeObject(forKey: keyPrefix + deviceID.uuidString)
    }
}
