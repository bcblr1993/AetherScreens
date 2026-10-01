import XCTest
import zlib
@testable import AetherScreensCore

final class ExtendedClipboardTests: XCTestCase {
    func testCompressedUnicodeClipboardDelivery() throws {
        let text = "中文 clipboard\nsecond line"
        let utf8 = Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) + Data([0])
        var plain = Data()
        plain.append(contentsOf: withUnsafeBytes(of: UInt32(utf8.count).bigEndian) { Array($0) })
        plain.append(utf8)
        var size = compressBound(uLong(plain.count))
        var compressed = [UInt8](repeating: 0, count: Int(size))
        let status = plain.withUnsafeBytes { bytes in
            compress2(&compressed, &size, bytes.bindMemory(to: UInt8.self).baseAddress!, uLong(plain.count), Z_DEFAULT_COMPRESSION)
        }
        XCTAssertEqual(status, Z_OK)
        var payload = Data([0x10, 0, 0, 1])
        payload.append(contentsOf: compressed.prefix(Int(size)))
        let client = RFBClient(host: "localhost")
        let received = expectation(description: "Complete UTF-8 clipboard decoded")
        client.onClipboardReceived = { actual in
            XCTAssertEqual(actual, text)
            received.fulfill()
        }
        client.handleExtendedClipboard(payload)
        wait(for: [received], timeout: 1)
    }

    func testMalformedClipboardIsIgnored() {
        let client = RFBClient(host: "localhost")
        client.onClipboardReceived = { _ in XCTFail("Malformed clipboard must not be delivered") }
        for payload in [Data(), Data([0x10, 0, 0, 1]), Data([0x10, 0, 0, 1, 0xFF, 0xFF])] {
            client.handleExtendedClipboard(payload)
        }
    }
}
