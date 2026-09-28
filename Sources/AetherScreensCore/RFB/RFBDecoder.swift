import Foundation

/// Decodes incoming binary stream messages from the RFB server.
public enum RFBDecoder {

    /// Parses the 12-byte protocol version string (e.g. "RFB 003.008\n").
    public static func parseVersion(_ data: Data) -> (major: Int, minor: Int)? {
        guard data.count >= 12,
              let str = String(data: data.prefix(12), encoding: .ascii) else {
            return nil
        }
        // Expected format: "RFB 003.008\n"
        let parts = str.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard parts.count == 2, parts[0] == "RFB" else { return nil }

        let versionParts = parts[1].split(separator: ".")
        guard versionParts.count == 2,
              let major = Int(versionParts[0]),
              let minor = Int(versionParts[1]) else {
            return nil
        }
        return (major, minor)
    }

    /// Parses the list of security types offered by the server.
    public static func parseSecurityTypes(_ data: Data) -> [RFBConstants.SecurityType]? {
        guard !data.isEmpty else { return nil }
        let count = Int(data[0])
        guard count > 0 else {
            // Count 0 indicates an error follows
            return []
        }
        guard data.count >= 1 + count else { return nil }

        var types: [RFBConstants.SecurityType] = []
        for i in 1...count {
            types.append(RFBConstants.SecurityType(rawValue: data[i]))
        }
        return types
    }

    /// Parses the 4-byte SecurityResult code (0 = OK, 1 = Failed).
    public static func parseSecurityResult(_ data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    /// Parses the ServerInit message.
    public static func parseServerInit(_ data: Data) -> (initData: RFBServerInit, bytesConsumed: Int)? {
        // Minimum size: 2 (width) + 2 (height) + 16 (pixel format) + 4 (name length) = 24 bytes
        guard data.count >= 24 else { return nil }

        let width = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let height = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }

        let pixelFormatData = data.subdata(in: 4..<20)
        guard let pixelFormat = RFBPixelFormat.parse(from: pixelFormatData) else { return nil }

        let nameLength = Int(data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        let totalNeeded = 24 + nameLength
        guard data.count >= totalNeeded else { return nil }

        let nameData = data.subdata(in: 24..<totalNeeded)
        let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "Mac Desktop"

        let serverInit = RFBServerInit(width: width, height: height, pixelFormat: pixelFormat, name: name)
        return (serverInit, totalNeeded)
    }

    /// Parses the FramebufferUpdate header (messageType 0).
    /// Returns the number of rectangles to read.
    public static func parseFramebufferUpdateHeader(_ data: Data) -> UInt16? {
        // [type: 1 byte] [pad: 1 byte] [numRects: 2 bytes] = 4 bytes
        guard data.count >= 4, data[0] == RFBConstants.ServerMessageType.framebufferUpdate.rawValue else {
            return nil
        }
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    /// Parses a single rectangle header (12 bytes: x, y, width, height, encodingType).
    public static func parseRectangleHeader(_ data: Data) -> (
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16,
        encoding: RFBConstants.EncodingType
    )? {
        guard data.count >= 12 else { return nil }
        let x = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let y = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let width = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let height = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let encRaw = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: Int32.self).bigEndian }

        return (x, y, width, height, RFBConstants.EncodingType(rawValue: encRaw))
    }

    /// Parses ServerCutText (clipboard text from remote Mac).
    public static func parseServerCutText(_ data: Data) -> String? {
        // [type: 1] [pad: 3] [length: 4] [text: length]
        guard data.count >= 8, data[0] == RFBConstants.ServerMessageType.serverCutText.rawValue else {
            return nil
        }
        let length = Int(data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
        guard data.count >= 8 + length else { return nil }

        let textData = data.subdata(in: 8..<(8 + length))
        return String(data: textData, encoding: .utf8) ?? String(data: textData, encoding: .isoLatin1)
    }
}
