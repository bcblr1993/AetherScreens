import Foundation
import Network

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
        guard let macBytes = parseMACAddress(macAddress) else {
            completion?(false)
            return
        }

        let packet = createMagicPacket(macBytes: macBytes)

        let host = NWEndpoint.Host(broadcastHost)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let udpParams = NWParameters.udp
        udpParams.allowLocalEndpointReuse = true

        let connection = NWConnection(host: host, port: nwPort, using: udpParams)
        let queue = DispatchQueue(label: "com.aethernative.aetherscreens.wol", qos: .utility)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed({ error in
                    let success = (error == nil)
                    connection.cancel()
                    completion?(success)
                }))
            case .failed:
                connection.cancel()
                completion?(false)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }
}
