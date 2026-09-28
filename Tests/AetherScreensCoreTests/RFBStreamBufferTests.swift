import XCTest
@testable import AetherScreensCore

final class RFBStreamBufferTests: XCTestCase {

    func testStreamBufferSlicingAndAccumulation() {
        var buffer = Data()

        // Simulate incoming chunk 1: 5 bytes of a 10-byte message
        let chunk1 = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        buffer.append(chunk1)
        XCTAssertEqual(buffer.count, 5)

        // Request 10 bytes: not enough yet
        let targetCount = 10
        XCTAssertTrue(buffer.count < targetCount)

        // Simulate incoming chunk 2: remaining 5 bytes + 3 extra bytes for next message
        let chunk2 = Data([0x06, 0x07, 0x08, 0x09, 0x0A, 0xBB, 0xCC, 0xDD])
        buffer.append(chunk2)
        XCTAssertEqual(buffer.count, 13)

        // Now we have enough bytes: extract targetCount (10)
        let message = buffer.prefix(targetCount)
        buffer.removeSubrange(0..<targetCount)

        XCTAssertEqual(Array(message), [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(Array(buffer), [0xBB, 0xCC, 0xDD])
    }

    func testLargeFrameBufferChunkAccumulation() {
        var buffer = Data()
        let totalExpected = 1920 * 100 * 4 // 100 rows of 1920 32-bit pixels = 768,000 bytes
        let chunkSize = 16384 // Typical TCP receive window chunk

        var bytesSent = 0
        var chunkIndex: UInt8 = 0
        while bytesSent < totalExpected {
            let thisChunkSize = min(chunkSize, totalExpected - bytesSent)
            let chunk = Data(repeating: chunkIndex, count: thisChunkSize)
            buffer.append(chunk)
            bytesSent += thisChunkSize
            chunkIndex = chunkIndex &+ 1
        }

        XCTAssertEqual(buffer.count, totalExpected)

        // Read exact totalExpected
        let extracted = buffer.prefix(totalExpected)
        buffer.removeSubrange(0..<totalExpected)

        XCTAssertEqual(extracted.count, totalExpected)
        XCTAssertEqual(buffer.count, 0)
    }
}
