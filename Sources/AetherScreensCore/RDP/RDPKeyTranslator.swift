import Foundation
import RDPKit

/// Turns X11 keysyms from the shared input pipeline into RDP keyboard events.
///
/// Printable characters normally travel as Unicode events so they arrive correctly whatever
/// keyboard layout either side uses. Windows ignores held modifiers for Unicode events, though,
/// so while Ctrl, Alt or Win is down punctuation is sent as its US scancode instead
/// (Ctrl+/, Ctrl+-, Ctrl+= and similar shortcuts). A release always uses the same event kind
/// as its press, even if modifiers changed in between.
struct RDPKeyTranslator {
    private var heldShortcutModifiers: Set<UInt32> = []
    private var keysPressedAsScancode: Set<UInt32> = []

    private static let shortcutModifiers: Set<UInt32> = [0xffe3, 0xffe4, 0xffe9, 0xffea, 0xffeb, 0xffec]

    mutating func events(keySym: UInt32, down: Bool) -> [RDPSlowPathInputEvent] {
        if Self.shortcutModifiers.contains(keySym) {
            if down { heldShortcutModifiers.insert(keySym) } else { heldShortcutModifiers.remove(keySym) }
        }

        if let scancode = RDPClient.mapKeySymToScancode(keySym) {
            return [.keyboard(scancode: scancode, isReleased: !down)]
        }

        let useScancode: Bool
        if down {
            useScancode = !heldShortcutModifiers.isEmpty && Self.punctuationScancode(keySym) != nil
            if useScancode { keysPressedAsScancode.insert(keySym) }
        } else {
            useScancode = keysPressedAsScancode.remove(keySym) != nil
        }
        if useScancode, let scancode = Self.punctuationScancode(keySym) {
            return [.keyboard(scancode: scancode, isReleased: !down)]
        }

        return Self.unicodeCodeUnits(for: keySym).map { .unicode(codeUnit: $0, isReleased: !down) }
    }

    /// UTF-16 units for a printable keysym: Latin-1 keysyms equal their code point and
    /// `0x01000000 | codepoint` carries any other Unicode scalar. Function-key keysyms
    /// (0xFF00...0xFFFF) and legacy non-Unicode keysyms have no text and produce nothing.
    static func unicodeCodeUnits(for keySym: UInt32) -> [UInt16] {
        let codePoint: UInt32
        if (0x20...0x7e).contains(keySym) || (0xa0...0xff).contains(keySym) {
            codePoint = keySym
        } else if keySym & 0xff00_0000 == 0x0100_0000 {
            codePoint = keySym & 0x00ff_ffff
        } else {
            return []
        }
        guard let scalar = Unicode.Scalar(codePoint) else { return [] }
        return Array(String(Character(scalar)).utf16)
    }

    /// US-layout scancodes for punctuation, including the shifted symbols on the number row.
    static func punctuationScancode(_ keySym: UInt32) -> RDPKeyboardScancode? {
        let code: UInt16
        switch keySym {
        case 0x60, 0x7e: code = 0x29 // ` ~
        case 0x2d, 0x5f: code = 0x0c // - _
        case 0x3d, 0x2b: code = 0x0d // = +
        case 0x5b, 0x7b: code = 0x1a // [ {
        case 0x5d, 0x7d: code = 0x1b // ] }
        case 0x5c, 0x7c: code = 0x2b // \ |
        case 0x3b, 0x3a: code = 0x27 // ; :
        case 0x27, 0x22: code = 0x28 // ' "
        case 0x2c, 0x3c: code = 0x33 // , <
        case 0x2e, 0x3e: code = 0x34 // . >
        case 0x2f, 0x3f: code = 0x35 // / ?
        case 0x21: code = 0x02 // !
        case 0x40: code = 0x03 // @
        case 0x23: code = 0x04 // #
        case 0x24: code = 0x05 // $
        case 0x25: code = 0x06 // %
        case 0x5e: code = 0x07 // ^
        case 0x26: code = 0x08 // &
        case 0x2a: code = 0x09 // *
        case 0x28: code = 0x0a // (
        case 0x29: code = 0x0b // )
        default: return nil
        }
        return RDPKeyboardScancode(code: code)
    }
}
