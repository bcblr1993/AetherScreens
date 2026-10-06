import XCTest
import NIO
@testable import AetherScreensSSH

final class SSHTransportEndpointsTests: XCTestCase {
    func testOnlyKnownSameSSHHostDestinationUsesEstablishedEndpoints() throws {
        let local = try SocketAddress(ipAddress: "192.0.2.35", port: 42000)
        let remote = try SocketAddress(ipAddress: "198.51.100.25", port: 22)
        for destination in ["127.0.0.1", "127.9.8.7", "::1", "198.51.100.25"] {
            let endpoints = try XCTUnwrap(SSHTransportEndpoints(local: local, remote: remote, destinationHost: destination))
            XCTAssertTrue(endpoints.destinationIsSSHHost)
            XCTAssertEqual(endpoints.localAddress, Data([192, 0, 2, 35]))
            XCTAssertEqual(endpoints.remoteAddress, Data([198, 51, 100, 25]))
        }
        for destination in ["192.0.2.40", "another-computer.invalid", "localhost"] {
            XCTAssertFalse(try XCTUnwrap(SSHTransportEndpoints(local: local, remote: remote,
                destinationHost: destination)).destinationIsSSHHost)
        }
    }

    func testIPv6AndMappedIPv4PreserveResolvedAddressFamily() throws {
        let local = try SocketAddress(ipAddress: "2001:db8:1::3", port: 42000)
        let remote = try SocketAddress(ipAddress: "2001:db8:2::4", port: 22)
        let v6 = try XCTUnwrap(SSHTransportEndpoints(local: local, remote: remote, destinationHost: "::1"))
        XCTAssertEqual(v6.localAddress.count, 16)
        XCTAssertEqual(v6.remoteAddress.count, 16)
        XCTAssertTrue(v6.destinationIsSSHHost)
        let mapped = try XCTUnwrap(SSHTransportEndpoints(
            local: SocketAddress(ipAddress: "::ffff:192.0.2.35", port: 42000),
            remote: SocketAddress(ipAddress: "::ffff:198.51.100.25", port: 22),
            destinationHost: "::ffff:127.0.0.1"))
        XCTAssertEqual(mapped.localAddress, Data([192, 0, 2, 35]))
        XCTAssertEqual(mapped.remoteAddress, Data([198, 51, 100, 25]))
        XCTAssertTrue(mapped.destinationIsSSHHost)
    }

    func testMissingUnixAndMixedFamilyEndpointsStayUnknown() throws {
        let v4 = try SocketAddress(ipAddress: "192.0.2.35", port: 42000)
        let v6 = try SocketAddress(ipAddress: "2001:db8::4", port: 22)
        XCTAssertNil(SSHTransportEndpoints(local: nil, remote: v4, destinationHost: "127.0.0.1"))
        XCTAssertNil(SSHTransportEndpoints(local: v4, remote: nil, destinationHost: "127.0.0.1"))
        XCTAssertNil(SSHTransportEndpoints(local: v4, remote: v6, destinationHost: "::1"))
        XCTAssertNil(SSHTransportEndpoints(local: try SocketAddress(unixDomainSocketPath: "/synthetic-fixture"),
            remote: v4, destinationHost: "127.0.0.1"))
    }
}
