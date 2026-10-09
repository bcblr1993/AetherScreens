import XCTest
@testable import AetherScreensCore

final class TightStreamsTests: XCTestCase {
    func testFourIndependentPersistentDictionariesAndSelectiveReset() throws {
        var encoders = try (0..<4).map { _ in try ZRLETestDeflater() }
        let decoder = TightStreams()
        for round in 0..<12 {
            if round == 6 {
                decoder.reset(control: 0x82) // Fill control also resets stream 1.
                encoders[1] = try ZRLETestDeflater()
            }
            for stream in 0..<4 {
                let pixels = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 * (stream + 1) + round) })
                XCTAssertEqual(decoder.decompress(try encoders[stream].compress(pixels),
                                 stream: stream, expectedBytes: pixels.count), pixels)
            }
        }
        decoder.reset(control: 0x9f) // JPEG control resets all four streams.
        for stream in 0..<4 {
            let pixels = Data(repeating: UInt8(stream), count: 32)
            XCTAssertEqual(decoder.decompress(try ZRLETestDeflater().compress(pixels),
                             stream: stream, expectedBytes: 32), pixels)
        }
    }

    func testRejectsInvalidStreamAndExpansionBounds() throws {
        let data = try ZRLETestDeflater().compress(Data(repeating: 42, count: 24))
        for stream in [-1, 4, Int.max] {
            XCTAssertNil(TightStreams().decompress(data, stream: stream, expectedBytes: 24))
        }
        for size in [0, 11, 12, 25, Int.max] {
            XCTAssertNil(TightStreams().decompress(data, stream: 0, expectedBytes: size))
        }
        XCTAssertNil(TightStreams().decompress(Data(), stream: 0, expectedBytes: 24))
    }
}
