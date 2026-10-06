import Foundation
import Network
import Darwin
import AetherScreensSSH

/// Classify the established socket, including resolved DNS addresses. Private
/// address ranges alone do not prove that a computer is on the same LAN.
enum LocalConnectionRoute {
    enum InterfaceKind: Equatable { case physical, loopback, other, unknown }
    struct InterfaceSubnet {
        let subnet: Subnet
        let kind: InterfaceKind
    }
    struct Subnet {
        let address: Data
        let mask: Data

        func contains(_ peer: Data) -> Bool {
            guard peer.count == address.count, mask.count == address.count,
                  mask.contains(where: { $0 != 0 }) else { return false }
            return zip(zip(peer, address), mask).allSatisfy { pair, mask in
                pair.0 & mask == pair.1 & mask
            }
        }
    }

    static func isLocal(_ path: NWPath?) -> Bool? {
        guard let path, case let .hostPort(host, _) = path.remoteEndpoint else { return nil }
        if path.usesInterfaceType(.loopback) { return true }
        let address: Data
        switch host {
        case .ipv4(let ip): address = ip.rawValue
        case .ipv6(let ip): address = ip.rawValue
        default: return nil
        }
        let interfaces = Set(path.availableInterfaces.filter {
            $0.type == .wifi || $0.type == .wiredEthernet
        }.map(\.name))
        guard path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) else { return false }
        let localSubnets = subnets(on: interfaces)
        guard !localSubnets.isEmpty else { return nil }
        return localSubnets.contains { $0.contains(address) }
    }

    static func isLocal(_ endpoints: SSHTransportEndpoints?) -> Bool? {
        guard let endpoints, endpoints.destinationIsSSHHost else { return nil }
        return isLocal(peer: endpoints.remoteAddress, local: endpoints.localAddress,
                       interfaces: interfaceSubnets())
    }

    static func isLocal(peer: Data, local: Data, interfaces: [InterfaceSubnet]) -> Bool? {
        guard (local.count == 4 || local.count == 16), peer.count == local.count else { return nil }
        let matching = interfaces.filter {
            $0.subnet.address == local && $0.subnet.mask.count == local.count &&
            $0.subnet.mask.contains(where: { $0 != 0 })
        }
        guard let kind = matching.first?.kind, kind != .unknown,
              matching.allSatisfy({ $0.kind == kind }) else { return nil }
        switch kind {
        case .physical:
            let localPeers = matching.map { $0.subnet.contains(peer) }
            guard let first = localPeers.first, localPeers.allSatisfy({ $0 == first }) else { return nil }
            return first
        case .loopback:
            return peer.count == 4 ? peer.first == 127
                : peer == Data(Array(repeating: 0, count: 15) + [1])
        case .other: return false
        case .unknown: return nil
        }
    }

    private static func interfaceSubnets() -> [InterfaceSubnet] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var kinds: [String: InterfaceKind] = [:], current = head
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let item = entry.pointee
            guard item.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: item.ifa_name)
            if item.ifa_flags & UInt32(IFF_LOOPBACK) != 0 { kinds[name] = .loopback }
            else if let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK {
                kinds[name] = address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) {
                    $0.pointee.sdl_type == IFT_ETHER ? .physical : .other
                }
            }
        }
        var result: [InterfaceSubnet] = []
        current = head
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let item = entry.pointee
            guard item.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = bytes(item.ifa_addr), let mask = bytes(item.ifa_netmask) else { continue }
            result.append(InterfaceSubnet(subnet: Subnet(address: address, mask: mask),
                kind: kinds[String(cString: item.ifa_name)] ?? .unknown))
        }
        return result
    }

    private static func subnets(on interfaces: Set<String>) -> [Subnet] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var result: [Subnet] = [], current = head
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            let item = entry.pointee
            guard item.ifa_flags & UInt32(IFF_UP) != 0,
                  interfaces.contains(String(cString: item.ifa_name)),
                  let address = bytes(item.ifa_addr), let mask = bytes(item.ifa_netmask) else { continue }
            result.append(Subnet(address: address, mask: mask))
        }
        return result
    }

    private static func bytes(_ pointer: UnsafeMutablePointer<sockaddr>?) -> Data? {
        guard let pointer else { return nil }
        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin_addr) { Data($0) }
            }
        case AF_INET6:
            return pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Data($0) }
            }
        default: return nil
        }
    }
}
