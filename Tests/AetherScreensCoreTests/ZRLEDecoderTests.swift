import XCTest
import zlib
@testable import AetherScreensCore

final class ZRLEDecoderTests: XCTestCase {
    private let a: [UInt8] = [12, 34, 56]
    private let b: [UInt8] = [78, 90, 123]

    func testRawCompactBGRPixelsBecomeOpaqueBGRA() throws {
        let encoded = [UInt8(0)] + a + b + [255, 0, 128]
        XCTAssertEqual(try decode(encoded, width: 3, height: 1), Data(a + [255] + b + [255] + [255, 0, 128, 255]))
    }

    func testLargeRawTilesPreserveAllPixelsAndPartialTileEdges() throws {
        let fixture = zrleRawTileFixture(width: 257, height: 257)
        let compressed = try ZRLETestDeflater().compress(fixture.tiles)
        XCTAssertGreaterThan(compressed.count, 65_536)
        XCTAssertEqual(ZRLEDecoder().decode(data: compressed, width: 257, height: 257), fixture.pixels)
    }

    func testSolidTilesTraverseRowsAndPartialEdges() throws {
        let colors: [[UInt8]] = [a, b, [1, 2, 3], [4, 5, 6]]
        let encoded = colors.flatMap { [UInt8(1)] + $0 }
        let actual = try decode(encoded, width: 70, height: 65)
        for y in 0..<65 {
            for x in 0..<70 {
                let color = colors[(y / 64) * 2 + x / 64]
                XCTAssertEqual(Array(actual[(y * 70 + x) * 4..<(y * 70 + x + 1) * 4]), color + [255])
            }
        }
    }

    func testOneBitPaletteRowsRestartAfterPadding() throws {
        let encoded = [UInt8(2)] + a + b + [0xa0, 0x40]
        XCTAssertEqual(try decode(encoded, width: 3, height: 2), bgra([b, a, b, a, b, a]))
    }

    func testTwoBitNonPowerOfTwoPaletteAndFourBitPalette() throws {
        let c: [UInt8] = [1, 2, 3]
        XCTAssertEqual(try decode([3] + a + b + c + [0x18, 0x90], width: 3, height: 2), bgra([a, b, c, c, b, a]))
        let colors: [[UInt8]] = (0..<5).map { [UInt8($0), 2, 3] }
        XCTAssertEqual(try decode([5] + colors.flatMap { $0 } + [0x04, 0x20, 0x31, 0x40], width: 3, height: 2),
                       bgra([colors[0], colors[4], colors[2], colors[3], colors[1], colors[4]]))
    }

    func testPlainRunsCrossRowsAndUseExtendedLengthBytes() throws {
        let encoded = [UInt8(128)] + a + [255, 0] + b + Array(repeating: UInt8(255), count: 15) + [14]
        let actual = try decode(encoded, width: 64, height: 64)
        XCTAssertEqual(actual, bgra(Array(repeating: a, count: 256) + Array(repeating: b, count: 3840)))
    }

    func testMaximumPaletteAndSinglePixelRun() throws {
        let colors: [[UInt8]] = (1...127).map { [UInt8($0), 2, 3] }
        var encoded: [UInt8] = [255]
        encoded.append(contentsOf: colors.flatMap { $0 })
        encoded.append(contentsOf: [0, 254])
        encoded.append(contentsOf: Array(repeating: UInt8(255), count: 16))
        encoded.append(14)
        XCTAssertEqual(try decode(encoded, width: 64, height: 64),
                       bgra([colors[0]] + Array(repeating: colors[126], count: 4095)))
    }

    func testContinuousDictionaryPersistsAcrossRectanglesAndResetRestartsIt() throws {
        let encoder = try ZRLETestDeflater()
        let first = try encoder.compress(Data([1] + a))
        let second = try encoder.compress(Data([1] + b))
        let decoder = ZRLEDecoder()
        XCTAssertEqual(decoder.decode(data: first, width: 2, height: 1), bgra([a, a]))
        XCTAssertEqual(decoder.decode(data: second, width: 2, height: 1), bgra([b, b]))
        XCTAssertNil(ZRLEDecoder().decode(data: second, width: 2, height: 1), "A fresh decoder cannot consume a continuation without its zlib header")
        decoder.reset()
        let restarted = try ZRLETestDeflater().compress(Data([1] + b))
        XCTAssertEqual(decoder.decode(data: restarted, width: 2, height: 1), bgra([b, b]))
    }

    func testRejectsReservedTypesTruncationInvalidIndicesAndOversizedRuns() throws {
        let invalid: [[UInt8]] = [
            [17], [127], [129], [0] + a, [1, 12, 34], [2] + a + b,
            [3] + a + b + [1, 2, 3] + [0xf0],
            [130] + a + b + [127], [128] + a + [255, 0], [128] + a,
            [1] + a + [0]
        ]
        for payload in invalid {
            let compressed = try ZRLETestDeflater().compress(Data(payload))
            XCTAssertNil(ZRLEDecoder().decode(data: compressed, width: 2, height: 1), "Malformed tile: \(payload)")
        }
        let unterminated = try ZRLETestDeflater().compress(Data([128] + a + [255]))
        XCTAssertNil(ZRLEDecoder().decode(data: unterminated, width: 64, height: 64))
        XCTAssertNil(ZRLEDecoder().decode(data: Data([0]), width: 2, height: 1))
    }

    func testDimensionAndInflationLimitsRejectOversizedAllocations() throws {
        for dimensions in [(0, 1), (1, 0), (-1, 1), (Int.max, 2), (65535, 65535)] {
            XCTAssertNil(ZRLEDecoder.maximumTileBytes(width: dimensions.0, height: dimensions.1))
        }
        let bomb = try ZRLETestDeflater().compress(Data(repeating: 1, count: 100_000))
        XCTAssertNil(ZRLEDecoder().decode(data: bomb, width: 1, height: 1))
    }

    func testBoundedInflationDrainsMultipleChunksAndRejectsExcessOutput() throws {
        let original = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let compressed = try ZRLETestDeflater().compress(original)
        XCTAssertEqual(ZlibDecompressor().decompress(data: compressed, maximumBytes: original.count), original)
        XCTAssertNil(ZlibDecompressor().decompress(data: compressed, maximumBytes: original.count - 1))
        XCTAssertNil(ZlibDecompressor().decompress(data: compressed, maximumBytes: 65_536))
    }

    func testFullHDTileImageRoundTripsWithMuchSmallerWirePayload() throws {
        var tiles = Data()
        for y in stride(from: 0, to: 1080, by: 64) {
            for x in stride(from: 0, to: 1920, by: 64) { tiles.append(contentsOf: [1, UInt8(x / 64), UInt8(y / 64), 42]) }
        }
        let compressed = try ZRLETestDeflater().compress(tiles)
        let started = ProcessInfo.processInfo.systemUptime
        let actual = try XCTUnwrap(ZRLEDecoder().decode(data: compressed, width: 1920, height: 1080))
        print("[ZRLE fixture] Full HD: \(compressed.count) compressed bytes vs \(actual.count) Raw bytes; decode \((ProcessInfo.processInfo.systemUptime - started) * 1000) ms")
        XCTAssertLessThan(compressed.count, actual.count / 100)
        for y in 0..<1080 {
            let row = actual.subdata(in: y * 1920 * 4..<(y + 1) * 1920 * 4)
            for x in stride(from: 0, to: 1920, by: 64) {
                XCTAssertEqual(Array(row[x * 4..<x * 4 + 4]), [UInt8(x / 64), UInt8(y / 64), 42, 255])
            }
        }
    }

    private func decode(_ bytes: [UInt8], width: Int, height: Int) throws -> Data {
        let compressed = try ZRLETestDeflater().compress(Data(bytes))
        return try XCTUnwrap(ZRLEDecoder().decode(data: compressed, width: width, height: height))
    }
    private func bgra(_ colors: [[UInt8]]) -> Data { Data(colors.flatMap { $0 + [255] }) }
}

/// Independently builds the expected row-major image first, then serializes its BGR tile samples.
func zrleRawTileFixture(width: Int, height: Int) -> (tiles: Data, pixels: Data) {
    var random: UInt32 = 0x12345678
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)
    for _ in 0..<(width * height) {
        random = random &* 1664525 &+ 1013904223
        pixels.append(contentsOf: [UInt8(truncatingIfNeeded: random >> 24), UInt8(truncatingIfNeeded: random >> 16), UInt8(truncatingIfNeeded: random >> 8), 255])
    }
    var tiles = Data()
    for y in stride(from: 0, to: height, by: 64) {
        for x in stride(from: 0, to: width, by: 64) {
            tiles.append(0)
            for row in y..<min(y + 64, height) {
                for column in x..<min(x + 64, width) {
                    let start = (row * width + column) * 4
                    tiles.append(contentsOf: pixels[start..<start + 3])
                }
            }
        }
    }
    return (tiles, Data(pixels))
}

/// Encoder uses the system zlib implementation; tile payloads in tests are independent wire examples.
final class ZRLETestDeflater {
    private var stream = z_stream()
    init() throws {
        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw NSError(domain: "ZRLETestDeflater", code: 1)
        }
    }
    deinit { deflateEnd(&stream) }
    func compress(_ data: Data) throws -> Data {
        var result = Data()
        try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.baseAddress!.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(data.count)
            defer { stream.next_in = nil; stream.next_out = nil }
            repeat {
                var chunk = Data(count: 65_536)
                let status = chunk.withUnsafeMutableBytes { output -> Int32 in
                    stream.next_out = output.baseAddress!.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = 65_536
                    return deflate(&stream, Z_SYNC_FLUSH)
                }
                guard status == Z_OK else { throw NSError(domain: "ZRLETestDeflater", code: Int(status)) }
                result.append(chunk.prefix(65_536 - Int(stream.avail_out)))
            } while stream.avail_in > 0 || stream.avail_out == 0
        }
        return result
    }
}
