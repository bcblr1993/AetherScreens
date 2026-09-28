import XCTest
@testable import AetherScreensCore

final class RFBPacketTests: XCTestCase {

    func testPixelFormatSerialization() {
        let original = RFBPixelFormat.standardBGRA32
        let data = original.serializedData
        XCTAssertEqual(data.count, 16)

        guard let parsed = RFBPixelFormat.parse(from: data) else {
            XCTFail("Failed to parse serialized RFBPixelFormat")
            return
        }

        XCTAssertEqual(parsed.bitsPerPixel, 32)
        XCTAssertEqual(parsed.depth, 24)
        XCTAssertEqual(parsed.bigEndianFlag, 0)
        XCTAssertEqual(parsed.trueColorFlag, 1)
        XCTAssertEqual(parsed.redMax, 255)
        XCTAssertEqual(parsed.greenMax, 255)
        XCTAssertEqual(parsed.blueMax, 255)
        XCTAssertEqual(parsed.redShift, 16)
        XCTAssertEqual(parsed.greenShift, 8)
        XCTAssertEqual(parsed.blueShift, 0)
        XCTAssertEqual(parsed.bytesPerPixel, 4)
    }

    func testRFBVersionParsing() {
        let validV38 = Data("RFB 003.008\n".utf8)
        let res = RFBDecoder.parseVersion(validV38)
        XCTAssertNotNil(res)
        XCTAssertEqual(res?.major, 3)
        XCTAssertEqual(res?.minor, 8)

        let validV37 = Data("RFB 003.007\n".utf8)
        let res37 = RFBDecoder.parseVersion(validV37)
        XCTAssertEqual(res37?.major, 3)
        XCTAssertEqual(res37?.minor, 7)

        let invalid = Data("HTTP 1.1\n".utf8)
        XCTAssertNil(RFBDecoder.parseVersion(invalid))
    }

    func testSecurityTypesParsing() {
        // [count: 2] [type 1: None (1)] [type 2: VNCAuth (2)]
        let data = Data([2, 1, 2])
        let types = RFBDecoder.parseSecurityTypes(data)
        XCTAssertEqual(types?.count, 2)
        XCTAssertTrue(types?.contains(.none) ?? false)
        XCTAssertTrue(types?.contains(.vncAuth) ?? false)

        let emptyTypes = RFBDecoder.parseSecurityTypes(Data([0]))
        XCTAssertEqual(emptyTypes?.count, 0)
    }

    func testSecurityResultParsing() {
        // Success: 0x00000000
        let successData = Data([0, 0, 0, 0])
        XCTAssertEqual(RFBDecoder.parseSecurityResult(successData), 0)

        // Failed: 0x00000001
        let failData = Data([0, 0, 0, 1])
        XCTAssertEqual(RFBDecoder.parseSecurityResult(failData), 1)
    }

    func testServerInitParsing() {
        var data = Data()
        // width: 1920 (0x0780), height: 1080 (0x0438)
        data.append(contentsOf: [0x07, 0x80])
        data.append(contentsOf: [0x04, 0x38])
        // pixel format: 16 bytes
        data.append(RFBPixelFormat.standardBGRA32.serializedData)
        // name length: 11
        let name = "MacBook Pro"
        let nameBytes = Array(name.utf8)
        let len = UInt32(nameBytes.count).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: len) { Array($0) })
        data.append(contentsOf: nameBytes)

        let parsed = RFBDecoder.parseServerInit(data)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.initData.width, 1920)
        XCTAssertEqual(parsed?.initData.height, 1080)
        XCTAssertEqual(parsed?.initData.name, "MacBook Pro")
        XCTAssertEqual(parsed?.bytesConsumed, data.count)
    }

    func testEncoderPointerEvent() {
        let mask: RFBConstants.ButtonMask = [.left, .right]
        let data = RFBEncoder.encodePointerEvent(buttonMask: mask, x: 500, y: 300)

        XCTAssertEqual(data.count, 6)
        XCTAssertEqual(data[0], RFBConstants.ClientMessageType.pointerEvent.rawValue)
        XCTAssertEqual(data[1], mask.rawValue)

        let x = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let y = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        XCTAssertEqual(x, 500)
        XCTAssertEqual(y, 300)
    }

    func testEncoderKeyEvent() {
        let keySym: UInt32 = MacKeyMap.return
        let data = RFBEncoder.encodeKeyEvent(down: true, keySym: keySym)

        XCTAssertEqual(data.count, 8)
        XCTAssertEqual(data[0], RFBConstants.ClientMessageType.keyEvent.rawValue)
        XCTAssertEqual(data[1], 1) // down flag

        let decodedSym = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(decodedSym, keySym)
    }

    func testEncoderFramebufferUpdateRequest() {
        let data = RFBEncoder.encodeFramebufferUpdateRequest(incremental: true, x: 10, y: 20, width: 800, height: 600)
        XCTAssertEqual(data.count, 10)
        XCTAssertEqual(data[0], RFBConstants.ClientMessageType.framebufferUpdateRequest.rawValue)
        XCTAssertEqual(data[1], 1) // incremental

        let x = data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let y = data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let w = data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let h = data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }

        XCTAssertEqual(x, 10)
        XCTAssertEqual(y, 20)
        XCTAssertEqual(w, 800)
        XCTAssertEqual(h, 600)
    }

    func testEncoderClientCutText() {
        let testString = "Hello from iPhone"
        let data = RFBEncoder.encodeClientCutText(testString)

        XCTAssertEqual(data[0], RFBConstants.ClientMessageType.clientCutText.rawValue)
        let len = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        XCTAssertEqual(Int(len), testString.utf8.count)

        let textBytes = data.subdata(in: 8..<(8 + Int(len)))
        XCTAssertEqual(String(data: textBytes, encoding: .utf8), testString)
    }
}
