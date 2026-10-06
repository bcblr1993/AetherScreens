import XCTest
import Darwin
@testable import AetherScreensCore

final class WakeOnLANTests: XCTestCase {

    func testBroadcastWakeDatagramReachesRealUDPSocket() async throws {
        let broadcast = try WakeDatagramReceiver.isolatedVMBroadcast()
        let receiver = try WakeDatagramReceiver()
        defer { receiver.close() }
        let probe = Data("owned-wake-qa".utf8)
        XCTAssertTrue(receiver.sendProbe(probe, to: broadcast))
        guard await receiver.receive() == probe else {
            XCTFail("The independent broadcast probe must reach the fixture before testing production")
            return
        }
        let sent = expectation(description: "A broadcast send completes")
        sent.assertForOverFulfill = true
        let receive = Task { await receiver.receive() }
        WakeOnLANService.wakeDevice(macAddress: "02:12:34:56:78:9A", broadcastHost: broadcast, port: receiver.port) { success in
            XCTAssertTrue(success)
            sent.fulfill()
        }
        await fulfillment(of: [sent], timeout: 3)
        let datagram = await receive.value
        let expected = Data(repeating: 255, count: 6) + Data(Array(repeating: [UInt8](arrayLiteral: 2, 0x12, 0x34, 0x56, 0x78, 0x9A), count: 16).flatMap { $0 })
        XCTAssertEqual(datagram, expected, "The actual receiver must get one complete 102-byte magic packet")
    }

    func testHostnameUnicastSendsExactlyOnceIncludingAfterCompletionDeadline() async throws {
        let receiver = try WakeDatagramReceiver()
        defer { receiver.close() }
        let sent = expectation(description: "The hostname send completes once")
        sent.assertForOverFulfill = true
        let receive = Task { await receiver.receive() }
        WakeOnLANService.wakeDevice(macAddress: "02:12:34:56:78:9A", broadcastHost: "localhost", port: receiver.port) { success in
            XCTAssertTrue(success)
            sent.fulfill()
        }
        await fulfillment(of: [sent], timeout: 3)
        let datagram = await receive.value
        XCTAssertEqual(datagram, WakeOnLANService.createMagicPacket(macBytes: [2, 0x12, 0x34, 0x56, 0x78, 0x9A]))
        // A completed request must not deliver a second failure at its deadline.
        try await Task.sleep(nanoseconds: 5_200_000_000)
    }

    func testZeroDestinationPortCompletesWithFailure() async {
        let completed = expectation(description: "An unusable destination terminates")
        completed.assertForOverFulfill = true
        WakeOnLANService.wakeDevice(macAddress: "02:12:34:56:78:9A", broadcastHost: "127.0.0.1", port: 0) { success in
            XCTAssertFalse(success)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
    }

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

/// An owned socket on an ephemeral port. Unicast uses loopback; broadcast is
/// restricted to the existing Tart bridge and a synthetic target MAC address.
private final class WakeDatagramReceiver: @unchecked Sendable {
    private let descriptor: Int32
    let port: UInt16

    static func isolatedVMBroadcast() throws -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { throw POSIXError(.EIO) }
        defer { freeifaddrs(interfaces) }
        var entry = interfaces
        while let current = entry {
            defer { entry = current.pointee.ifa_next }
            guard String(cString: current.pointee.ifa_name) == "bridge100",
                  current.pointee.ifa_flags & UInt32(IFF_BROADCAST) != 0,
                  let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = current.pointee.ifa_netmask else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            // Never turn this integration test into a broadcast on the user's LAN.
            guard UInt32(bigEndian: ip) & 0xFFFFFF00 == 0xC0A84000 else { continue }
            var broadcast = in_addr(s_addr: ip | ~mask)
            var bytes = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &broadcast, &bytes, socklen_t(bytes.count)) != nil else { throw POSIXError(.EIO) }
            return String(cString: bytes)
        }
        throw XCTSkip("Actual broadcast requires the existing isolated Tart bridge; no LAN fallback")
    }

    func sendProbe(_ data: Data, to host: String) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { return false }
        defer { Darwin.close(socket) }
        var enabled: Int32 = 1
        guard setsockopt(socket, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                data.withUnsafeBytes { Darwin.sendto(socket, $0.baseAddress, $0.count, 0, address, socklen_t(MemoryLayout<sockaddr_in>.size)) == data.count }
            }
        }
    }

    init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            Darwin.close(fd); throw POSIXError(.EIO)
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard bound == 0, named == 0, address.sin_port != 0 else {
            Darwin.close(fd); throw POSIXError(.EIO)
        }
        descriptor = fd
        port = UInt16(bigEndian: address.sin_port)
    }

    func receive() async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var bytes = [UInt8](repeating: 0, count: 103)
                let count = Darwin.recv(self.descriptor, &bytes, bytes.count, 0)
                continuation.resume(returning: count >= 0 ? Data(bytes.prefix(count)) : nil)
            }
        }
    }

    func close() { Darwin.close(descriptor) }
}
