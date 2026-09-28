import XCTest
@testable import AetherScreensCore

final class WakeOnLANTests: XCTestCase {

    func testMACAddressParsingColonFormat() {
        let macStr = "00:1A:2B:3C:4D:5E"
        let bytes = WakeOnLANService.parseMACAddress(macStr)
        XCTAssertNotNil(bytes)
        XCTAssertEqual(bytes?.count, 6)
        XCTAssertEqual(bytes, [0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E])
    }

    func testMACAddressParsingHyphenFormat() {
        let macStr = "aa-bb-cc-dd-ee-ff"
        let bytes = WakeOnLANService.parseMACAddress(macStr)
        XCTAssertNotNil(bytes)
        XCTAssertEqual(bytes, [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    }

    func testInvalidMACAddress() {
        XCTAssertNil(WakeOnLANService.parseMACAddress("invalid-mac"))
        XCTAssertNil(WakeOnLANService.parseMACAddress("00:11:22:33")) // Too short
        XCTAssertNil(WakeOnLANService.parseMACAddress("GG:HH:II:JJ:KK:LL")) // Non-hex
    }

    func testMagicPacketStructure() {
        let macBytes: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]
        let packet = WakeOnLANService.createMagicPacket(macBytes: macBytes)

        // Packet size must be exactly 102 bytes
        XCTAssertEqual(packet.count, 102)

        // First 6 bytes must be 0xFF
        let prefix = Array(packet[0..<6])
        XCTAssertEqual(prefix, [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])

        // Following 96 bytes must be 16 repetitions of macBytes
        for rep in 0..<16 {
            let start = 6 + rep * 6
            let slice = Array(packet[start..<(start + 6)])
            XCTAssertEqual(slice, macBytes, "Mismatch at repetition \(rep)")
        }
    }
}
