import Foundation

/// Tracks physical HID usages so layout/modifier changes cannot alter key-up.
/// Character values come from UIKit's active keyboard layout, not US HID letters.
final class HardwareKeyboardState {
    var onKeyEvent: ((Bool, UInt32) -> Void)?
    private var held: [Int: UInt32] = [:]
    var configuration = HardwareKeyboardConfiguration() {
        didSet { if oldValue != configuration { repeatUsage = nil } }
    }
    private var repeatUsage: Int?
    private var nextRepeatAt: TimeInterval = 0
    var hasRepeatCandidate: Bool { repeatUsage != nil }

    func advanceRepeat(at time: TimeInterval) {
        guard time.isFinite, let usage = repeatUsage, let key = held[usage],
              configuration.repeatEnabled, time >= nextRepeatAt else { return }
        onKeyEvent?(true, key)
        // Do not burst overdue repeats after a suspended or busy UI thread.
        nextRepeatAt = time + configuration.validatedInterval
    }

    static func isModifier(_ usage: Int) -> Bool { (0xE0...0xE7).contains(usage) }

    static func keySym(usage: Int, characters: String) -> UInt32? {
        switch usage {
        case 0x28, 0x58: return MacKeyMap.return
        case 0x29: return MacKeyMap.escape
        case 0x2A: return MacKeyMap.backspace
        case 0x2B: return MacKeyMap.tab
        case 0x39: return 0xFFE5 // Caps Lock
        case 0x3A...0x45: return MacKeyMap.f1 + UInt32(usage - 0x3A)
        case 0x68...0x73: return MacKeyMap.f12 + UInt32(usage - 0x67)
        case 0x4A: return MacKeyMap.home
        case 0x4B: return MacKeyMap.pageUp
        case 0x4C: return MacKeyMap.delete
        case 0x4D: return MacKeyMap.end
        case 0x4E: return MacKeyMap.pageDown
        case 0x4F: return MacKeyMap.arrowRight
        case 0x50: return MacKeyMap.arrowLeft
        case 0x51: return MacKeyMap.arrowDown
        case 0x52: return MacKeyMap.arrowUp
        case 0xE0: return MacKeyMap.controlLeft
        case 0xE1: return MacKeyMap.shiftLeft
        case 0xE2: return MacKeyMap.optionLeft
        case 0xE3: return MacKeyMap.commandLeft
        case 0xE4: return MacKeyMap.controlRight
        case 0xE5: return MacKeyMap.shiftRight
        case 0xE6: return MacKeyMap.optionRight
        case 0xE7: return MacKeyMap.commandRight
        default:
            guard characters.count == 1, let character = characters.first else { return nil }
            return MacKeyMap.keySym(for: character)
        }
    }

    @discardableResult
    func press(usage: Int, characters: String, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let key = held[usage] ?? Self.keySym(usage: usage, characters: characters) else { return false }
        let isNativeRepeat = held[usage] != nil
        held[usage] = key
        if isNativeRepeat {
            // Some keyboards/platforms deliver native repeats. Avoid a second
            // timer-generated stream while preserving the original keysym.
            if repeatUsage == usage { repeatUsage = nil }
        } else if configuration.repeatEnabled, !Self.isModifier(usage), usage != 0x39, time.isFinite {
            repeatUsage = usage
            nextRepeatAt = time + configuration.validatedDelay
        }
        onKeyEvent?(true, key) // Repeated key-downs are intentional.
        return true
    }

    @discardableResult
    func release(usage: Int) -> Bool {
        guard let key = held.removeValue(forKey: usage) else { return false }
        if repeatUsage == usage { repeatUsage = nil }
        if !held.values.contains(key) { onKeyEvent?(false, key) }
        return true
    }

    func releaseAll() {
        repeatUsage = nil
        // Release ordinary keys before modifiers, preserving shortcut ordering.
        for usage in held.keys.sorted(by: {
            if Self.isModifier($0) != Self.isModifier($1) { return !Self.isModifier($0) }
            return $0 < $1
        }) { release(usage: usage) }
    }
}

/// Applies physical-keyboard preferences while retaining each key-down mapping
/// for repeats and key-up. Toolbar shortcuts do not pass through this mapper.
struct HardwareKeyboardMapping {
    private var held: [UInt32: UInt32] = [:]

    mutating func event(down: Bool, key: UInt32, configuration: HardwareKeyboardConfiguration) -> UInt32? {
        if !down {
            guard let mapped = held.removeValue(forKey: key), !held.values.contains(mapped) else { return nil }
            return mapped
        }
        if let mapped = held[key] { return mapped }
        var mapped = key
        if configuration.swapCommandControl == true {
            switch key {
            case MacKeyMap.commandLeft: mapped = MacKeyMap.controlLeft
            case MacKeyMap.commandRight: mapped = MacKeyMap.controlRight
            case MacKeyMap.controlLeft: mapped = MacKeyMap.commandLeft
            case MacKeyMap.controlRight: mapped = MacKeyMap.commandRight
            default: break
            }
        }
        if key == 0x5C, configuration.commandBackslashSwitchesApps == true,
           held.values.contains(MacKeyMap.commandLeft) || held.values.contains(MacKeyMap.commandRight) {
            mapped = MacKeyMap.tab
        }
        held[key] = mapped
        return mapped
    }

    mutating func releaseAll() -> [UInt32] {
        let keys = Set(held.values).sorted {
            let a = (0xFFE1...0xFFEE).contains($0)
            let b = (0xFFE1...0xFFEE).contains($1)
            return a == b ? $0 < $1 : !a
        }
        held.removeAll()
        return keys
    }
}
