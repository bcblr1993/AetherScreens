import Foundation

/// Serializes native preference writes with library imports. Notifications are
/// posted after writers release this lock, so a library can capture the edit.
enum DevicePreferenceStorage {
    static let didChange = Notification.Name("AetherScreensDevicePreferencesDidChange")
    enum Origin: Equatable { case local, remote }
    private static let lock = NSRecursiveLock()

    static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }

    static func notify(_ defaults: UserDefaults, origin: Origin) {
        NotificationCenter.default.post(name: didChange, object: defaults, userInfo: ["origin": origin])
    }
}

/// Only actual saved overrides are captured. Loading a factory toolbar creates
/// random item IDs and must never be used to decide whether preferences changed.
struct DevicePreferenceSnapshot: Codable, Equatable {
    let language: AppLanguage?
    let scope: Set<UUID>
    private let keyboards: [String: KeyboardToolbarConfiguration]
    private enum CodingKeys: String, CodingKey { case language, scope, keyboards }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language)
        let ids = try values.decode([UUID].self, forKey: .scope)
        scope = Set(ids)
        guard scope.count == ids.count else { throw DeviceSyncDocument.Failure.invalidDocument }
        keyboards = try values.decode([String: KeyboardToolbarConfiguration].self, forKey: .keyboards)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(language, forKey: .language)
        try values.encode(scope.sorted { $0.uuidString < $1.uuidString }, forKey: .scope)
        try values.encode(keyboards, forKey: .keyboards)
    }

    var keyboardConfigurations: [UUID: KeyboardToolbarConfiguration] {
        keyboards.reduce(into: [:]) { result, entry in
            if let id = UUID(uuidString: entry.key) { result[id] = entry.value }
        }
    }

    init(language: AppLanguage?, keyboards: [UUID: KeyboardToolbarConfiguration], scope: Set<UUID>) {
        self.language = language; self.scope = scope
        self.keyboards = Dictionary(uniqueKeysWithValues: keyboards.map { ($0.key.uuidString, $0.value) })
    }

    init(defaults: UserDefaults, scope: Set<UUID>) throws {
        let language: AppLanguage?
        if let raw = defaults.object(forKey: AppLocalization.preferenceKey) {
            guard let raw = raw as? String, let selection = AppLanguage(rawValue: raw) else {
                throw DeviceSyncDocument.Failure.invalidDocument
            }
            language = selection
        } else { language = nil }
        var keyboards: [UUID: KeyboardToolbarConfiguration] = [:]
        for id in scope {
            let key = KeyboardToolbarStore.keyPrefix + id.uuidString
            guard let raw = defaults.object(forKey: key) else { continue }
            guard let bytes = raw as? Data,
                  let value = try? JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: bytes) else {
                throw DeviceSyncDocument.Failure.invalidDocument
            }
            keyboards[id] = value
        }
        self.init(language: language, keyboards: keyboards, scope: scope)
    }

    init(data: Data) throws {
        do { self = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw DeviceSyncDocument.Failure.invalidDocument }
        guard keyboards.keys.allSatisfy({ key in
            UUID(uuidString: key).map { $0.uuidString == key && scope.contains($0) } == true
        }) else {
            throw DeviceSyncDocument.Failure.invalidDocument
        }
    }

    func encoded() throws -> Data { try Self.encode(self) }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// Encode every value before mutating a mirror. No partial application on a
    /// serialization failure, and unrelated/temporary computer keys stay intact.
    func apply(to defaults: UserDefaults) throws {
        let encoded = try keyboards.mapValues { try Self.encode($0) }
        if let language { defaults.set(language.rawValue, forKey: AppLocalization.preferenceKey) }
        else { defaults.removeObject(forKey: AppLocalization.preferenceKey) }
        for id in scope {
            let key = KeyboardToolbarStore.keyPrefix + id.uuidString
            if let bytes = encoded[id.uuidString] { defaults.set(bytes, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }

    /// Finish an interrupted compatibility-mirror write one key at a time.
    /// A later native edit differs from both sides and is retained for capture.
    func recoverMirror(in defaults: UserDefaults, previous: Self) throws -> Bool {
        var changed = false
        let currentLanguage = defaults.object(forKey: AppLocalization.preferenceKey)
        let oldLanguage = previous.language?.rawValue
        let newLanguage = language?.rawValue
        if (currentLanguage == nil && oldLanguage == nil) || (currentLanguage as? String == oldLanguage && currentLanguage is String) {
            if oldLanguage != newLanguage {
                if let newLanguage { defaults.set(newLanguage, forKey: AppLocalization.preferenceKey) }
                else { defaults.removeObject(forKey: AppLocalization.preferenceKey) }
                changed = true
            }
        }
        let encoded = try keyboards.mapValues { try Self.encode($0) }
        for id in scope {
            let key = KeyboardToolbarStore.keyPrefix + id.uuidString
            let raw = defaults.object(forKey: key)
            let current = (raw as? Data).flatMap { try? JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: $0) }
            let old = previous.keyboards[id.uuidString], new = keyboards[id.uuidString]
            let matchesOld = raw == nil ? old == nil : current != nil && current == old
            if matchesOld && old != new {
                if let bytes = encoded[id.uuidString] { defaults.set(bytes, forKey: key) }
                else { defaults.removeObject(forKey: key) }
                changed = true
            }
        }
        return changed
    }
}
