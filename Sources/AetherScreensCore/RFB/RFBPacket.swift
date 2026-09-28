import Foundation

/// Represents the RFB pixel format structure (16 bytes).
public struct RFBPixelFormat: Equatable, Sendable {
    public var bitsPerPixel: UInt8
    public var depth: UInt8
    public var bigEndianFlag: UInt8
    public var trueColorFlag: UInt8
    public var redMax: UInt16
    public var greenMax: UInt16
    public var blueMax: UInt16
    public var redShift: UInt8
    public var greenShift: UInt8
    public var blueShift: UInt8

    public init(
        bitsPerPixel: UInt8 = 32,
        depth: UInt8 = 24,
        bigEndianFlag: UInt8 = 0,
        trueColorFlag: UInt8 = 1,
        redMax: UInt16 = 255,
        greenMax: UInt16 = 255,
        blueMax: UInt16 = 255,
        redShift: UInt8 = 16,
        greenShift: UInt8 = 8,
        blueShift: UInt8 = 0
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.bigEndianFlag = bigEndianFlag
        self.trueColorFlag = trueColorFlag
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    /// Standard 32-bit BGRA format commonly used by iOS / Metal
    public static let standardBGRA32 = RFBPixelFormat(
        bitsPerPixel: 32,
        depth: 24,
        bigEndianFlag: 0,
        trueColorFlag: 1,
        redMax: 255,
        greenMax: 255,
        blueMax: 255,
        redShift: 16,
        greenShift: 8,
        blueShift: 0
    )

    /// Standard 32-bit RGBA format
    public static let standardRGBA32 = RFBPixelFormat(
        bitsPerPixel: 32,
        depth: 24,
        bigEndianFlag: 0,
        trueColorFlag: 1,
        redMax: 255,
        greenMax: 255,
        blueMax: 255,
        redShift: 0,
        greenShift: 8,
        blueShift: 16
    )

    public var bytesPerPixel: Int {
        return Int(bitsPerPixel) / 8
    }

    public var serializedData: Data {
        var data = Data(capacity: 16)
        data.append(bitsPerPixel)
        data.append(depth)
        data.append(bigEndianFlag)
        data.append(trueColorFlag)
        data.append(contentsOf: withUnsafeBytes(of: redMax.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: greenMax.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blueMax.bigEndian) { Array($0) })
        data.append(redShift)
        data.append(greenShift)
        data.append(blueShift)
        data.append(contentsOf: [0, 0, 0]) // 3 bytes padding
        return data
    }

    public static func parse(from data: Data) -> RFBPixelFormat? {
        guard data.count >= 16 else { return nil }
        let bitsPerPixel = data[data.startIndex]
        let depth = data[data.startIndex + 1]
        let bigEndianFlag = data[data.startIndex + 2]
        let trueColorFlag = data[data.startIndex + 3]
        
        let redMax = data.subdata(in: (data.startIndex + 4)..<(data.startIndex + 6)).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        let greenMax = data.subdata(in: (data.startIndex + 6)..<(data.startIndex + 8)).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        let blueMax = data.subdata(in: (data.startIndex + 8)..<(data.startIndex + 10)).withUnsafeBytes {
            $0.load(as: UInt16.self).bigEndian
        }
        let redShift = data[data.startIndex + 10]
        let greenShift = data[data.startIndex + 11]
        let blueShift = data[data.startIndex + 12]

        return RFBPixelFormat(
            bitsPerPixel: bitsPerPixel,
            depth: depth,
            bigEndianFlag: bigEndianFlag,
            trueColorFlag: trueColorFlag,
            redMax: redMax,
            greenMax: greenMax,
            blueMax: blueMax,
            redShift: redShift,
            greenShift: greenShift,
            blueShift: blueShift
        )
    }
}

/// ServerInit message received from RFB server.
public struct RFBServerInit: Equatable, Sendable {
    public let width: UInt16
    public let height: UInt16
    public let pixelFormat: RFBPixelFormat
    public let name: String

    public init(width: UInt16, height: UInt16, pixelFormat: RFBPixelFormat, name: String) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.name = name
    }
}

/// A dirty rectangle inside a FramebufferUpdate message.
public struct RFBRectangle: Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
    public let width: UInt16
    public let height: UInt16
    public let encoding: RFBConstants.EncodingType
    public let pixelData: Data

    public init(
        x: UInt16,
        y: UInt16,
        width: UInt16,
        height: UInt16,
        encoding: RFBConstants.EncodingType,
        pixelData: Data
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.encoding = encoding
        self.pixelData = pixelData
    }
}
