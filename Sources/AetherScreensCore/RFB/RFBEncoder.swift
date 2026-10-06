import Foundation

/// Encodes client-to-server messages according to the RFB 3.8 specification.
public enum RFBEncoder {
    /// Keep negotiation tied to implemented decoders. Apple image encodings
    /// 1000...1002 and 1011 have IANA assignments, but that registration does not
    /// describe their payloads or provide a decoder. In particular, advertising
    /// display-layout metadata does not enable progressive image refinement.
    static func sessionEncodings(supportsAppleDisplayMetadata: Bool) -> [RFBConstants.EncodingType] {
        var encodings: [RFBConstants.EncodingType] = [
            .zrle, .zlib, .copyRect, .desktopSize, .extendedDesktopSize, .raw
        ]
        if supportsAppleDisplayMetadata { encodings += [.appleDisplayInfo, .appleDisplayLayout] }
        return encodings
    }

    /// Apple scales the encoded desktop; physical display settings stay intact.
    static func encodeAppleServerScaling(_ factor: Double) -> Data? {
        guard factor.isFinite, factor > 0, factor <= 1 else { return nil }
        var message = Data([8, 0])
        withUnsafeBytes(of: factor.bitPattern.bigEndian) { message.append(contentsOf: $0) }
        return message
    }

    static func encodeAppleSetDisplay(_ id: UInt32?) -> Data {
        var message = Data([0x0D, id == nil ? 1 : 0, 0, 0])
        withUnsafeBytes(of: (id ?? 0).bigEndian) { message.append(contentsOf: $0) }
        return message
    }

    /// Apple session visibility: 0 hides the console, 1 restores it. An empty
    /// UTF-8 note avoids sending user/account information to the physical screen.
    /// Protocol reference and physical-display limitations: docs/curtain-protocol.md.
    static func encodeAppleCurtain(hidden: Bool) -> Data {
        Data([12, 0, 0, hidden ? 0 : 1, 0, 0])
    }

    /// Apple's interval is in microseconds, not a display identifier. All ones
    /// disables push. Pace capture at 60 Hz rather than allowing unbounded pushes
    /// to hold the server's input reader behind a slow framebuffer transfer.
    static func encodeAppleAutoFramebufferUpdate(width: UInt16, height: UInt16,
                                                 intervalMicroseconds: UInt32 = 16_667) -> Data {
        var data = Data([9, 0, 0, 1])
        withUnsafeBytes(of: intervalMicroseconds.bigEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0, 0, 0, 0])
        withUnsafeBytes(of: width.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// Encode `SetPixelFormat` (message-type 0)
    public static func encodeSetPixelFormat(_ format: RFBPixelFormat) -> Data {
        var data = Data(capacity: 20)
        data.append(RFBConstants.ClientMessageType.setPixelFormat.rawValue)
        data.append(contentsOf: [0, 0, 0]) // 3 bytes padding
        data.append(format.serializedData)
        return data
    }

    /// Encode `SetEncodings` (message-type 2)
    public static func encodeSetEncodings(_ encodings: [RFBConstants.EncodingType]) -> Data {
        var data = Data(capacity: 4 + encodings.count * 4)
        data.append(RFBConstants.ClientMessageType.setEncodings.rawValue)
        data.append(0) // padding
        let count = UInt16(encodings.count).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: count) { Array($0) })

        for enc in encodings {
            let encRaw = enc.rawValue.bigEndian
            data.append(contentsOf: withUnsafeBytes(of: encRaw) { Array($0) })
        }
        return data
    }

    /// Encode `FramebufferUpdateRequest` (message-type 3)
    public static func encodeFramebufferUpdateRequest(
        incremental: Bool,
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16
    ) -> Data {
        var data = Data(capacity: 10)
        data.append(RFBConstants.ClientMessageType.framebufferUpdateRequest.rawValue)
        data.append(incremental ? 1 : 0)
        data.append(contentsOf: withUnsafeBytes(of: x.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: y.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })
        return data
    }

    /// Encode `KeyEvent` (message-type 4)
    public static func encodeKeyEvent(down: Bool, keySym: UInt32) -> Data {
        var data = Data(capacity: 8)
        data.append(RFBConstants.ClientMessageType.keyEvent.rawValue)
        data.append(down ? 1 : 0)
        data.append(contentsOf: [0, 0]) // 2 bytes padding
        data.append(contentsOf: withUnsafeBytes(of: keySym.bigEndian) { Array($0) })
        return data
    }

    /// Encode `PointerEvent` (message-type 5)
    public static func encodePointerEvent(buttonMask: RFBConstants.ButtonMask, x: UInt16, y: UInt16) -> Data {
        var data = Data(capacity: 6)
        data.append(RFBConstants.ClientMessageType.pointerEvent.rawValue)
        data.append(buttonMask.rawValue)
        data.append(contentsOf: withUnsafeBytes(of: x.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: y.bigEndian) { Array($0) })
        return data
    }

    /// Legacy text uses LF; extended UTF-8 clipboard text uses CRLF on the wire.
    static func clipboardText(_ text: String, extended: Bool) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return extended ? lines.replacingOccurrences(of: "\n", with: "\r\n") : lines
    }

    /// Encode `ClientCutText` (message-type 6) - Clipboard sync
    public static func encodeClientCutText(_ text: String) -> Data? {
        guard let textData = clipboardText(text, extended: false).data(using: .isoLatin1, allowLossyConversion: false) else { return nil }
        var data = Data(capacity: 8 + textData.count)
        data.append(RFBConstants.ClientMessageType.clientCutText.rawValue)
        data.append(contentsOf: [0, 0, 0]) // 3 bytes padding
        let length = UInt32(textData.count).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        data.append(textData)
        return data
    }
}
