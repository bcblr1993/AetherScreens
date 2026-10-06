import Foundation

public struct KeyboardToolbarConfiguration: Codable, Equatable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable { case small = "Small", medium = "Medium", large = "Large" }
    public enum Position: String, Codable, CaseIterable, Sendable { case top = "Top", bottom = "Bottom" }
    public enum Action: String, Codable, CaseIterable, Sendable {
        case actions = "Actions", command = "Cmd", option = "Opt", control = "Ctrl", shift = "Shift"
        case escape = "esc", tab = "tab", space = "space", enter = "return", delete = "del"
        case left = "Left Arrow", up = "Up Arrow", down = "Down Arrow", right = "Right Arrow"
        case userPassword = "Type User Password"
        case functionKeys = "Fn", text = "Type", paste = "Paste Text", dictation = "Dictation", spacer = "Spacer"
        case pageUp = "Page Up", pageDown = "Page Down", home = "Home", end = "End"
        case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6"
        case f7 = "F7", f8 = "F8", f9 = "F9", f10 = "F10", f11 = "F11", f12 = "F12"

        public static let optionalKeys: [Self] = [.pageUp, .pageDown, .home, .end,
            .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        public var isVisibleByDefault: Bool { !Self.optionalKeys.contains(self) }
        public var keySym: UInt32? {
            switch self {
            case .pageUp: return MacKeyMap.pageUp
            case .pageDown: return MacKeyMap.pageDown
            case .home: return MacKeyMap.home
            case .end: return MacKeyMap.end
            case .f1: return MacKeyMap.f1
            case .f2: return MacKeyMap.f2
            case .f3: return MacKeyMap.f3
            case .f4: return MacKeyMap.f4
            case .f5: return MacKeyMap.f5
            case .f6: return MacKeyMap.f6
            case .f7: return MacKeyMap.f7
            case .f8: return MacKeyMap.f8
            case .f9: return MacKeyMap.f9
            case .f10: return MacKeyMap.f10
            case .f11: return MacKeyMap.f11
            case .f12: return MacKeyMap.f12
            default: return nil
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
    public var items: [Item] = Self.defaultItems
    public var hardwareKeyboard: HardwareKeyboardConfiguration?
    public var pencilDoubleTapAction: PencilGestureAction?
    public var pencilSqueezeAction: PencilGestureAction?
    public init() {}
    public func pencilAction(for gesture: PencilGesture) -> PencilGestureAction {
        switch gesture {
        case .doubleTap: return pencilDoubleTapAction ?? .none
        case .squeeze: return pencilSqueezeAction ?? .none
        }
    }

    public mutating func resetToolbar() {
        size = .medium
        position = .bottom
        items = Self.defaultItems
    }
    private static var defaultItems: [Item] {
        [.actions, .command, .option, .control, .shift, .spacer,
         .escape, .tab, .space, .enter, .delete, .spacer,
         .left, .up, .down, .right, .spacer, .functionKeys, .text, .paste, .userPassword, .dictation].map { Item(action: $0) }
         + Action.optionalKeys.map { Item(action: $0, isVisible: false) }
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
    var synchronizationDefaults: UserDefaults { defaults }
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func savedData(for deviceID: UUID) -> Data? {
        DevicePreferenceStorage.withLock { defaults.data(forKey: Self.keyPrefix + deviceID.uuidString) }
    }
    public func load(for deviceID: UUID) -> KeyboardToolbarConfiguration {
        DevicePreferenceStorage.withLock {
            guard let data = defaults.data(forKey: Self.keyPrefix + deviceID.uuidString),
                  var config = try? JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: data) else {
                return KeyboardToolbarConfiguration()
            }
            config.normalize()
            return config
        }
    }
    public func save(_ configuration: KeyboardToolbarConfiguration, for deviceID: UUID) {
        let changed = DevicePreferenceStorage.withLock {
            var normalized = configuration
            normalized.normalize()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(normalized) else { return false }
            let key = Self.keyPrefix + deviceID.uuidString
            guard defaults.data(forKey: key) != data else { return false }
            defaults.set(data, forKey: key)
            return true
        }
        if changed { DevicePreferenceStorage.notify(defaults, origin: .local) }
    }
}
