import Foundation

public struct KeyboardToolbarConfiguration: Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable { case small = "Small", medium = "Medium", large = "Large" }
    public enum Position: String, Codable, CaseIterable, Sendable { case top = "Top", bottom = "Bottom", floating = "Floating", carousel = "Carousel" }
    public enum KeyRepeat: String, Codable, CaseIterable, Sendable {
        case off = "Off", slow = "Slow", normal = "Normal", fast = "Fast"
        var delayNanoseconds: UInt64 {
            switch self { case .off, .slow: return 600_000_000; case .normal: return 450_000_000; case .fast: return 300_000_000 }
        }
        var intervalNanoseconds: UInt64 {
            switch self { case .off, .slow: return 120_000_000; case .normal: return 65_000_000; case .fast: return 45_000_000 }
        }
    }
    public enum Action: String, Codable, CaseIterable, Sendable {
        case actions = "Actions", command = "Cmd", option = "Opt", control = "Ctrl", shift = "Shift"
        case escape = "esc", tab = "tab", space = "space", enter = "return", delete = "del"
        case left = "Left Arrow", up = "Up Arrow", down = "Down Arrow", right = "Right Arrow"
        case functionKeys = "Fn", text = "Type", paste = "Paste Text", spacer = "Spacer"
        case home = "Home", end = "End", pageUp = "Page Up", pageDown = "Page Down"

        fileprivate var isVisibleByDefault: Bool {
            switch self {
            case .home, .end, .pageUp, .pageDown: return false
            default: return true
            }
        }
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
    public var keyRepeat: KeyRepeat = .normal
    public var items: [Item] = Self.defaultItems
    public init() {}
    private enum CodingKeys: String, CodingKey { case size, position, keyRepeat, items }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        size = try values.decode(Size.self, forKey: .size)
        position = try values.decode(Position.self, forKey: .position)
        items = try values.decode([Item].self, forKey: .items)
        keyRepeat = try values.decodeIfPresent(KeyRepeat.self, forKey: .keyRepeat) ?? .normal
    }
    private static var defaultItems: [Item] {
        [.actions, .command, .option, .control, .shift, .spacer,
         .escape, .tab, .space, .enter, .delete, .spacer,
         .left, .up, .down, .right, .spacer, .functionKeys, .text, .paste,
         .home, .end, .pageUp, .pageDown].map { Item(action: $0, isVisible: $0.isVisibleByDefault) }
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
            items.append(Item(action: action, isVisible: action.isVisibleByDefault))
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
