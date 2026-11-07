import Foundation

/// KeySym definitions and Mac keyboard shortcut helpers according to X11 / RFB specs.
public enum MacKeyMap {

    // MARK: - Modifiers
    public static let shiftLeft: UInt32   = 0xFFE1
    public static let shiftRight: UInt32  = 0xFFE2
    public static let controlLeft: UInt32 = 0xFFE3
    public static let controlRight: UInt32 = 0xFFE4
    public static let optionLeft: UInt32  = 0xFFE9 // Alt
    public static let optionRight: UInt32 = 0xFFEA
    public static let commandLeft: UInt32 = 0xFFEB // Super / Cmd
    public static let commandRight: UInt32 = 0xFFEC

    // MARK: - Standard Special Keys
    public static let backspace: UInt32   = 0xFF08
    public static let tab: UInt32         = 0xFF09
    public static let `return`: UInt32    = 0xFF0D
    public static let escape: UInt32      = 0xFF1B
    public static let delete: UInt32      = 0xFFFF
    public static let space: UInt32       = 0x0020
    public static let v: UInt32           = 0x0076

    // MARK: - Directional Keys
    public static let arrowLeft: UInt32   = 0xFF51
    public static let arrowUp: UInt32     = 0xFF52
    public static let arrowRight: UInt32  = 0xFF53
    public static let arrowDown: UInt32   = 0xFF54
    public static let pageUp: UInt32      = 0xFF55
    public static let pageDown: UInt32    = 0xFF56
    public static let home: UInt32        = 0xFF50
    public static let end: UInt32         = 0xFF57

    // MARK: - Function Keys
    public static let f1: UInt32  = 0xFFBE
    public static let f2: UInt32  = 0xFFBF
    public static let f3: UInt32  = 0xFFC0
    public static let f4: UInt32  = 0xFFC1
    public static let f5: UInt32  = 0xFFC2
    public static let f6: UInt32  = 0xFFC3
    public static let f7: UInt32  = 0xFFC4
    public static let f8: UInt32  = 0xFFC5
    public static let f9: UInt32  = 0xFFC6
    public static let f10: UInt32 = 0xFFC7
    public static let f11: UInt32 = 0xFFC8
    public static let f12: UInt32 = 0xFFC9

    /// Convert a single Character into an X11 KeySym.
    public static func keySym(for char: Character) -> UInt32? {
        guard char.unicodeScalars.count == 1, let scalar = char.unicodeScalars.first else { return nil }
        let val = scalar.value
        // Printable Latin-1 maps directly; other Unicode scalars use X11 Unicode keysyms.
        if val >= 0x20 && val <= 0xFF {
            return UInt32(val)
        }
        return val >= 0x100 ? 0x01000000 | val : nil
    }

    private static let shiftedUSASCII: Set<Character> = Set("!@#$%^&*()_+{}|:\"<>?~")

    /// Whether typing this character on a US keyboard requires holding Shift.
    public static func requiresShift(for char: Character) -> Bool {
        char.isUppercase || shiftedUSASCII.contains(char)
    }

    /// Build a hardware-accurate keystroke sequence for typing a password at a remote login/lock screen.
    public static func passwordKeystrokeSequence(
        for password: String,
        appendReturn: Bool = false
    ) -> [(key: UInt32, down: Bool)] {
        var sequence: [(key: UInt32, down: Bool)] = []
        sequence.reserveCapacity(password.count * 4 + (appendReturn ? 2 : 0))
        for char in password {
            guard let sym = keySym(for: char) else { continue }
            let shifted = requiresShift(for: char)
            if shifted {
                sequence.append((shiftLeft, true))
            }
            sequence.append((sym, true))
            sequence.append((sym, false))
            if shifted {
                sequence.append((shiftLeft, false))
            }
        }
        if appendReturn {
            sequence.append((Self.return, true))
            sequence.append((Self.return, false))
        }
        return sequence
    }

    /// Finger direction follows the desktop's natural Space navigation.
    public enum ThreeFingerSwipe: CaseIterable, Sendable {
        case up, down, left, right
        public var shortcut: MacShortcut {
            switch self {
            case .up: return .missionControl
            case .down: return .appExpose
            case .left: return .nextSpace
            case .right: return .previousSpace
            }
        }
    }

    /// Predefined Mac Shortcuts (combination of modifier keys and target key)
    public enum MacShortcut: String, CaseIterable, Identifiable, Sendable {
        case spotlight = "Spotlight (⌘Space)"
        case appSwitcher = "App Switcher (⌘Tab)"
        case missionControl = "Mission Control (⌃↑)"
        case appExpose = "App Windows (⌃↓)"
        case previousSpace = "Previous Space (⌃←)"
        case nextSpace = "Next Space (⌃→)"
        case lockScreen = "Lock Screen (⌃⌘Q)"
        case showDesktop = "Show Desktop (⌘F3)"
        case forceQuit = "Force Quit (⌥⌘Esc)"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .spotlight: return "magnifyingglass"
            case .appSwitcher: return "square.on.square"
            case .missionControl: return "rectangle.3.group"
            case .appExpose: return "rectangle.on.rectangle"
            case .previousSpace: return "arrow.left.square"
            case .nextSpace: return "arrow.right.square"
            case .lockScreen: return "lock.fill"
            case .showDesktop: return "menubar.rectangle"
            case .forceQuit: return "exclamationmark.octagon.fill"
            }
        }

        public var keySequence: [(key: UInt32, down: Bool)] {
            switch self {
            case .spotlight:
                return [
                    (commandLeft, true), (space, true),
                    (space, false), (commandLeft, false)
                ]
            case .appSwitcher:
                return [
                    (commandLeft, true), (tab, true),
                    (tab, false), (commandLeft, false)
                ]
            case .missionControl:
                return [
                    (controlLeft, true), (arrowUp, true),
                    (arrowUp, false), (controlLeft, false)
                ]
            case .appExpose, .previousSpace, .nextSpace:
                let arrow: UInt32 = self == .appExpose ? arrowDown : self == .previousSpace ? arrowLeft : arrowRight
                return [(controlLeft, true), (arrow, true), (arrow, false), (controlLeft, false)]
            case .lockScreen:
                return [
                    (controlLeft, true), (commandLeft, true), (UInt32(Character("q").asciiValue!), true),
                    (UInt32(Character("q").asciiValue!), false), (commandLeft, false), (controlLeft, false)
                ]
            case .showDesktop:
                return [
                    (commandLeft, true), (f3, true),
                    (f3, false), (commandLeft, false)
                ]
            case .forceQuit:
                return [
                    (optionLeft, true), (commandLeft, true), (escape, true),
                    (escape, false), (commandLeft, false), (optionLeft, false)
                ]
            }
        }
    }
}
