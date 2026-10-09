import XCTest
import zlib
@testable import AetherScreensCore

final class AppleCursorCacheTests: XCTestCase {
    func testSeparatedAlphaOverridesWireAlphaAndPremultipliesColors() throws {
        let cache = AppleCursorCache()
        let plain = Data([100,200,255,9, 100,200,255,9, 100,200,255,9, 0,128,255])
        let cursor = try XCTUnwrap(try cache.decode(message: packet(id: 91, plain: plain),
            width: 3, height: 1, hotspotX: 2, hotspotY: 0))
        XCTAssertEqual(cursor.pixels, Data([0,0,0,0, 50,100,128,128, 100,200,255,255]))
        XCTAssertEqual(cursor.hotspotX, 2)
        XCTAssertEqual(cursor.makeCGImage()?.width, 3)
        let selected = try cache.decode(message: select(91), width: 0, height: 0, hotspotX: 0, hotspotY: 0)
        XCTAssertEqual(selected, cursor)
        XCTAssertTrue(selected?.makeCGImage() === cursor.makeCGImage())
        XCTAssertEqual(cache.retainedBytes, 12)
    }

    func testOpaqueIDsLRUEvictionAndResetKeepUnknownSelectionEmpty() throws {
        let cache = AppleCursorCache(byteLimit: 8, entryLimit: 2)
        for id: UInt32 in [0, 0xffff_ffff] { _ = try store(cache, id: id) }
        XCTAssertNotNil(try cache.decode(message: select(0), width: 0, height: 0, hotspotX: 0, hotspotY: 0))
        _ = try store(cache, id: 1000)
        XCTAssertNil(try cache.decode(message: select(0xffff_ffff), width: 0, height: 0, hotspotX: 0, hotspotY: 0))
        XCTAssertNotNil(try cache.decode(message: select(0), width: 0, height: 0, hotspotX: 0, hotspotY: 0))
        XCTAssertEqual(cache.count, 2); XCTAssertEqual(cache.retainedBytes, 8)
        cache.reset()
        XCTAssertEqual(cache.count, 0); XCTAssertEqual(cache.retainedBytes, 0)
        XCTAssertNil(try cache.decode(message: select(0), width: 0, height: 0, hotspotX: 0, hotspotY: 0))
    }

    func testMalformedReplacementPreservesPreviousShape() throws {
        let cache = AppleCursorCache()
        let original = try store(cache, id: 7)
        let invalid = word(7) + word(3) + Data([1,2,3])
        XCTAssertThrowsError(try cache.decode(message: invalid, width: 1, height: 1, hotspotX: 0, hotspotY: 0))
        XCTAssertEqual(try cache.decode(message: select(7), width: 0, height: 0, hotspotX: 0, hotspotY: 0), original)
        XCTAssertEqual(cache.count, 1); XCTAssertEqual(cache.retainedBytes, 4)
    }

    func testGeometryLengthsAndCompressionBoundsAreRejected() throws {
        let cache = AppleCursorCache()
        let valid = try packet(id: 1, plain: Data([1,2,3,4,255]))
        for (w,h,x,y) in [(513,1,0,0), (1,513,0,0), (1,1,1,0), (1,1,0,1), (0,1,0,0), (-1,1,0,0)] {
            XCTAssertThrowsError(try cache.decode(message: valid, width: w, height: h, hotspotX: x, hotspotY: y))
        }
        for message in [Data(), Data(valid.dropLast()), valid + Data([0]), word(1) + word(UInt32.max)] {
            XCTAssertThrowsError(try cache.decode(message: message, width: 1, height: 1, hotspotX: 0, hotspotY: 0))
        }
        XCTAssertThrowsError(try cache.decode(message: select(1), width: 1, height: 1, hotspotX: 0, hotspotY: 0))
        for size in [4, 6, 10_000] {
            XCTAssertThrowsError(try cache.decode(message: packet(id: 1, plain: Data(repeating: 0, count: size)),
                width: 1, height: 1, hotspotX: 0, hotspotY: 0))
        }
        XCTAssertEqual(cache.retainedBytes, 0)
    }

    func testSyncFlushAndFinishedStreamsRequireCompleteConsumption() throws {
        let cache = AppleCursorCache()
        let plain = Data([1,2,3,99,255])
        for flush in [Z_SYNC_FLUSH, Z_FINISH] {
            XCTAssertNotNil(try cache.decode(message: packet(id: 1, plain: plain, flush: flush),
                width: 1, height: 1, hotspotX: 0, hotspotY: 0))
        }
        let compressed = try compress(plain, flush: Z_FINISH) + Data([0])
        XCTAssertThrowsError(try cache.decode(message: word(1) + word(UInt32(compressed.count)) + compressed,
            width: 1, height: 1, hotspotX: 0, hotspotY: 0))
    }

    func testDisplayableShapeCanExceedRetentionBudgetWithoutGrowingCache() throws {
        for cache in [AppleCursorCache(byteLimit: 3), AppleCursorCache(entryLimit: 0)] {
            XCTAssertNotNil(try store(cache, id: 1))
            XCTAssertEqual(cache.count, 0); XCTAssertEqual(cache.retainedBytes, 0)
            XCTAssertNil(try cache.decode(message: select(1), width: 0, height: 0, hotspotX: 0, hotspotY: 0))
        }
    }

    private func store(_ cache: AppleCursorCache, id: UInt32) throws -> RFBRemoteCursor? {
        try cache.decode(message: packet(id: id, plain: Data([1,2,3,0,255])),
                         width: 1, height: 1, hotspotX: 0, hotspotY: 0)
    }
    private func word(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private func select(_ id: UInt32) -> Data { word(id) + word(0) }
    private func packet(id: UInt32, plain: Data, flush: Int32 = Z_SYNC_FLUSH) throws -> Data {
        let compressed = try compress(plain, flush: flush)
        return word(id) + word(UInt32(compressed.count)) + compressed
    }
    private func compress(_ plain: Data, flush: Int32) throws -> Data {
        var stream = z_stream()
        XCTAssertEqual(deflateInit_(&stream, 9, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)), Z_OK)
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(compressBound(uLong(plain.count))) + 16)
        let status = plain.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { buffer in
                stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
                stream.avail_in = uInt(plain.count)
                stream.next_out = buffer.baseAddress!.assumingMemoryBound(to: Bytef.self)
                stream.avail_out = uInt(buffer.count)
                return deflate(&stream, flush)
            }
        }
        XCTAssertTrue(status == Z_OK || status == Z_STREAM_END)
        XCTAssertEqual(stream.avail_in, 0)
        output.count = Int(stream.total_out)
        return output
    }
}
