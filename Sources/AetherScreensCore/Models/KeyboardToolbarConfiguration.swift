import Foundation

public struct KeyboardToolbarConfiguration: Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable { case small = "Small", medium = "Medium", large = "Large" }
    public enum Position: String, Codable, CaseIterable, Sendable { case top = "Top", bottom = "Bottom" }
    public enum Action: String, Codable, CaseIterable, Sendable {
        case actions = "Actions", command = "Cmd", option = "Opt", control = "Ctrl", shift = "Shift"
        case escape = "esc", tab = "tab", space = "space", enter = "return", delete = "del"
        case left = "Left Arrow", up = "Up Arrow", down = "Down Arrow", right = "Right Arrow"
        case functionKeys = "Fn", text = "Type", paste = "Paste Text", spacer = "Spacer"
    }
    public struct Item: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var action: Action
        public var isVisible: Bool
        public init(id: UUID = UUID(), action: Action, isVisible: Bool = true) {
            self.id = id; self.action = action; self.isVisible = isVisible
        }
    }
    public var size: Size = .medium
    public var position: Position = .bottom
    public var items: [Item] = Self.defaultItems
    public init() {}
    private static var defaultItems: [Item] {
        [.actions, .command, .option, .control, .shift, .spacer,
         .escape, .tab, .space, .enter, .delete, .spacer,
         .left, .up, .down, .right, .spacer, .functionKeys, .text, .paste].map { Item(action: $0) }
    }
    /// Keep non-spacer actions unique and retain newly introduced controls when loading older settings.
    public mutating func normalize() {
        var seen = Set<Action>()
        var ids = Set<UUID>()
        items = items.filter { item in
            guard ids.insert(item.id).inserted else { return false }
            return item.action == .spacer || seen.insert(item.action).inserted
        }
        for action in Action.allCases where action != .spacer && !seen.contains(action) {
            items.append(Item(action: action))
        }
    }
    public mutating func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

/// Per-computer UI preferences contain neither credentials nor connection addresses.
public final class KeyboardToolbarStore: @unchecked Sendable {
    public static let shared = KeyboardToolbarStore()
    public static let keyPrefix = "com.aethernative.aetherscreens.keyboard."
    private let defaults: UserDefaults
    private let lock = NSLock()
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load(for deviceID: UUID) -> KeyboardToolbarConfiguration {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.keyPrefix + deviceID.uuidString),
              var config = try? JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: data) else {
            return KeyboardToolbarConfiguration()
        }
        config.normalize()
        return config
    }
    public func save(_ configuration: KeyboardToolbarConfiguration, for deviceID: UUID) {
        lock.lock(); defer { lock.unlock() }
        var normalized = configuration
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: Self.keyPrefix + deviceID.uuidString)
    }
}
