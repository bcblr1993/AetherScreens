import XCTest
import zlib
@testable import AetherScreensCore

final class ZlibDecompressorTests: XCTestCase {
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
