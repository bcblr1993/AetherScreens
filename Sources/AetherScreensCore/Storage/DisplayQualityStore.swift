import Foundation

/// Per-computer wire color precision; unknown preferences retain full color.
public final class DisplayQualityStore: @unchecked Sendable {
    public static let shared = DisplayQualityStore()
    private let defaults: UserDefaults
    private let prefix = "aetherscreens.display-color-depth."

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load(for deviceID: UUID) -> RFBColorDepth {
        guard let value = defaults.string(forKey: prefix + deviceID.uuidString),
              let depth = RFBColorDepth(rawValue: value) else { return .fullColor }
        return depth
    }

    public func save(_ depth: RFBColorDepth, for deviceID: UUID) {
        defaults.set(depth.rawValue, forKey: prefix + deviceID.uuidString)
    }

    public func remove(for deviceID: UUID) {
        defaults.removeObject(forKey: prefix + deviceID.uuidString)
        defaults.removeObject(forKey: "aetherscreens.automatic-quality." + deviceID.uuidString)
    }

    public func loadAutomatic(for deviceID: UUID) -> Bool {
        defaults.bool(forKey: "aetherscreens.automatic-quality." + deviceID.uuidString)
    }

    public func saveAutomatic(_ enabled: Bool, for deviceID: UUID) {
        defaults.set(enabled, forKey: "aetherscreens.automatic-quality." + deviceID.uuidString)
    }
}
