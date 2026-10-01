import XCTest
import zlib
@testable import AetherScreensCore

final class ZlibDecompressorTests: XCTestCase {
    func testContinuousRectanglesPreserveDictionaryAndExactPixels() throws {
        let compressor = try ZRLETestDeflater()
        let decoder = ZlibDecompressor()
        for index in 0..<512 {
            let size = index.isMultiple(of: 3) ? 65_540 : 4
            let pixels = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ index) })
            let compressed = try compressor.compress(pixels)
            XCTAssertEqual(decoder.decompress(data: compressed, expectedBytes: size), pixels,
                           "Persistent rectangle \(index) must preserve its complete pixel payload")
        }
    }

    func testRejectsShortAndOversizedPixelPayloads() throws {
        let pixels = Data([1, 2, 3, 255, 4, 5, 6, 255])
        let compressed = try ZRLETestDeflater().compress(pixels)
        XCTAssertNil(ZlibDecompressor().decompress(data: compressed, expectedBytes: 12))
        XCTAssertNil(ZlibDecompressor().decompress(data: compressed, expectedBytes: 4))
    }

    func testDecompressValidStream() throws {
        let decompressor = ZlibDecompressor()
        
        let originalText = "Apple Silicon & AetherScreens High Performance Remote Display"
        let originalData = originalText.data(using: .utf8)!

        // Compress using zlib
        var defStream = z_stream()
        let initRet = deflateInit_(&defStream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        XCTAssertEqual(initRet, Z_OK)

        var compData = Data(count: 1024)
        originalData.withUnsafeBytes { inPtr in
            defStream.next_in = UnsafeMutablePointer(mutating: inPtr.baseAddress!.assumingMemoryBound(to: Bytef.self))
            defStream.avail_in = uInt(originalData.count)
            compData.withUnsafeMutableBytes { outPtr in
                defStream.next_out = outPtr.baseAddress!.assumingMemoryBound(to: Bytef.self)
                defStream.avail_out = 1024
                deflate(&defStream, Z_SYNC_FLUSH)
            }
        }
        let compSize = 1024 - Int(defStream.avail_out)
        deflateEnd(&defStream)
        compData = compData.prefix(compSize)

        // Decompress with our ZlibDecompressor
        let decompressed = decompressor.decompress(data: compData, expectedBytes: originalData.count)
        XCTAssertNotNil(decompressed)
        XCTAssertEqual(decompressed, originalData)
        XCTAssertEqual(String(data: decompressed!, encoding: .utf8), originalText)
    }
}
