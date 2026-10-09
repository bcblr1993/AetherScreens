import XCTest
@testable import AetherScreensCore

final class TightRectangleDecoderTests: XCTestCase {
    func testFragmentedFillAndCopyPreserveFollowingMessage() {
        for packet in [Data([0x80,255,0,0]), Data([0,255,0,0])] {
            let decoder = TightRectangleDecoder()
            for count in 0..<packet.count {
                guard case .incomplete = decoder.decode(Data(packet.prefix(count)), width: 1, height: 1, colorDepth: .fullColor) else {
                    XCTFail("Truncated prefix must wait"); continue
                }
            }
            guard case .decoded(let pixels, let consumed) = decoder.decode(packet + Data([42]), width: 1, height: 1, colorDepth: .fullColor) else {
                XCTFail("Expected pixels"); continue
            }
            XCTAssertEqual(pixels, Data([0,0,255,255]))
            XCTAssertEqual(consumed, packet.count)
        }
    }

    func testCompressedPacketCanBeProbedWithoutMutatingDictionary() throws {
        let encoder = try ZRLETestDeflater()
        let decoder = TightRectangleDecoder()
        for value: UInt8 in [20, 30] {
            let compressed = try encoder.compress(Data(repeating: value, count: 12))
            XCTAssertLessThan(compressed.count, 128)
            let packet = Data([0, UInt8(compressed.count)]) + compressed
            for count in 0..<packet.count {
                guard case .incomplete = decoder.decode(Data(packet.prefix(count)), width: 4, height: 1, colorDepth: .fullColor) else {
                    XCTFail("Incomplete compressed payload changed state"); continue
                }
            }
            guard case .decoded(let pixels, let consumed) = decoder.decode(packet, width: 4, height: 1, colorDepth: .fullColor) else {
                XCTFail("Expected compressed pixels"); return
            }
            XCTAssertEqual(consumed, packet.count)
            XCTAssertEqual(pixels, Data(Array(repeating: [value,value,value,255], count: 4).flatMap { $0 }))
        }
    }
}
