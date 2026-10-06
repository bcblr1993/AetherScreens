import Foundation
import Darwin

/// Sends Wake-on-LAN (WOL) Magic Packets to wake up sleeping Macs on the local network.
public enum WakeOnLANService {

    /// Parses a MAC address string (e.g. "AA:BB:CC:DD:EE:FF" or "aa-bb-cc-dd-ee-ff") into 6 bytes.
    public static func parseMACAddress(_ macString: String) -> [UInt8]? {
        let cleaned = macString
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard cleaned.count == 12 else { return nil }

        var bytes = [UInt8]()
        var index = cleaned.startIndex
        for _ in 0..<6 {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    /// Creates a 102-byte Wake-on-LAN Magic Packet for the given MAC address.
    public static func createMagicPacket(macBytes: [UInt8]) -> Data {
        precondition(macBytes.count == 6, "MAC address must be exactly 6 bytes")
        var packet = Data(capacity: 102)

        // 6 bytes of 0xFF
        for _ in 0..<6 {
            packet.append(0xFF)
        }

        // 16 repetitions of the target MAC address
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }

        return packet
    }

    /// Broadcasts a Wake-on-LAN packet to wake the specified MAC address.
    public static func wakeDevice(
        macAddress: String,
        broadcastHost: String = "255.255.255.255",
        port: UInt16 = 9,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        guard let macBytes = parseMACAddress(macAddress), port > 0,
              !broadcastHost.isEmpty, !broadcastHost.contains(where: { $0.isWhitespace }),
              !broadcastHost.utf8.contains(0) else {
            completion?(false)
            return
        }

        let packet = createMagicPacket(macBytes: macBytes)

        let result = WakePacketCompletion(completion)
        let queue = DispatchQueue(label: "com.aethernative.aetherscreens.wol", qos: .utility)
        // Resolution must not hold up the UI or leave the completion pending.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            result.finish(false)
        }
        queue.async {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            hints.ai_protocol = IPPROTO_UDP
            var addresses: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(broadcastHost, String(port), &hints, &addresses) == 0,
                  let address = addresses else {
                result.finish(false); return
            }
            defer { freeaddrinfo(addresses) }
            guard result.isPending else { return }
            let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard socket >= 0 else { result.finish(false); return }
            defer { Darwin.close(socket) }
            var enabled: Int32 = 1
            let flags = fcntl(socket, F_GETFL)
            // Network framework does not support UDP broadcast. Use a bounded
            // datagram socket; iOS still enforces its multicast entitlement.
            guard setsockopt(socket, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0,
                  flags >= 0, fcntl(socket, F_SETFL, flags | O_NONBLOCK) == 0,
                  result.isPending else { result.finish(false); return }
            // Local socket acceptance is not evidence that the Mac woke up.
            result.finish {
                packet.withUnsafeBytes {
                    Darwin.sendto(socket, $0.baseAddress, $0.count, 0, address.pointee.ai_addr, address.pointee.ai_addrlen) == packet.count
                }
            }
        }
    }
}

private final class WakePacketCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var completion: (@Sendable (Bool) -> Void)?

    init(_ completion: (@Sendable (Bool) -> Void)?) { self.completion = completion }

    var isPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return !finished
    }

    func finish(_ success: Bool) {
        finish { success }
    }

    /// The bounded nonblocking send and its deadline share this lock, so a
    /// resolver that returns after expiration cannot send a late wake packet.
    func finish(_ operation: () -> Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        let success = operation()
        finished = true
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(success)
    }
}
