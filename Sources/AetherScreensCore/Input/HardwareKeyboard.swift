import Foundation

/// Converts USB keyboard usages and layout characters to RFB keysyms.
/// Physical modifiers are forwarded separately so shortcuts execute remotely.
enum HardwareKeyboard {
    static func keySym(usage: Int, characters: String) -> UInt32? {
        switch usage {
        case 0x28, 0x58: return MacKeyMap.return
        case 0x29: return MacKeyMap.escape
        case 0x2a: return MacKeyMap.backspace
        case 0x2b: return MacKeyMap.tab
        case 0x39: return 0xffe5 // Caps Lock
        case 0x3a...0x45: return MacKeyMap.f1 + UInt32(usage - 0x3a)
        case 0x49: return 0xff63 // Insert
        case 0x4a: return MacKeyMap.home
        case 0x4b: return MacKeyMap.pageUp
        case 0x4c: return MacKeyMap.delete
        case 0x4d: return MacKeyMap.end
        case 0x4e: return MacKeyMap.pageDown
        case 0x4f: return MacKeyMap.arrowRight
        case 0x50: return MacKeyMap.arrowLeft
        case 0x51: return MacKeyMap.arrowDown
        case 0x52: return MacKeyMap.arrowUp
        case 0xe0: return MacKeyMap.controlLeft
        case 0xe1: return MacKeyMap.shiftLeft
        case 0xe2: return MacKeyMap.optionLeft
        case 0xe3: return MacKeyMap.commandLeft
        case 0xe4: return MacKeyMap.controlRight
        case 0xe5: return MacKeyMap.shiftRight
        case 0xe6: return MacKeyMap.optionRight
        case 0xe7: return MacKeyMap.commandRight
        default:
            guard characters.count == 1, let character = characters.first else { return nil }
            return MacKeyMap.keySym(for: character)
        }
    }

    static func isModifier(_ usage: Int) -> Bool { (0xe0...0xe7).contains(usage) }
}

/// Tracks the original down keysym by physical usage, including repeat events.
/// Key-up characters may differ after releasing Shift or changing input layouts.
struct HardwareKeyboardState {
    private var pressed: [Int: UInt32] = [:]

    mutating func begin(usage: Int, characters: String) -> UInt32? {
        if let existing = pressed[usage] { return existing }
        guard let key = HardwareKeyboard.keySym(usage: usage, characters: characters) else { return nil }
        pressed[usage] = key
        return key
    }

    mutating func end(usage: Int) -> UInt32? { pressed.removeValue(forKey: usage) }

    mutating func releaseAll() -> [UInt32] {
        // Release printable keys before modifiers so teardown cannot form a new shortcut.
        let keys = pressed.keys.sorted {
            if HardwareKeyboard.isModifier($0) != HardwareKeyboard.isModifier($1) {
                return !HardwareKeyboard.isModifier($0)
            }
            return $0 < $1
        }.compactMap { pressed[$0] }
        pressed.removeAll()
        return keys
    }
}
