import XCTest
@testable import AetherScreensCore

final class RemoteImageCompressionTests: XCTestCase {
    func testLegacyDeviceKeepsFullResolutionAndPoliciesRequireKnownRemoteRoute() throws {
        let legacy = try JSONDecoder().decode(RemoteDevice.self, from: JSONEncoder().encode(
            RemoteDevice(name: "Legacy QA", host: "qa.invalid")))
        XCTAssertNil(legacy.imageCompression)
        XCTAssertEqual(legacy.effectiveImageCompression, .never)
        XCTAssertEqual(RemoteImageCompressionPolicy.remoteOnly.factor(isLocalConnection: nil), 1)
        XCTAssertEqual(RemoteImageCompressionPolicy.remoteOnly.factor(isLocalConnection: true), 1)
        XCTAssertEqual(RemoteImageCompressionPolicy.remoteOnly.factor(isLocalConnection: false), 0.5)
        XCTAssertEqual(RemoteImageCompressionPolicy.always.factor(isLocalConnection: nil), 0.5)
        XCTAssertEqual(RemoteImageCompressionPolicy.never.factor(isLocalConnection: false), 1)
    }

    func testSubnetMembershipUsesActualMaskAndAddressFamily() {
        let subnet = LocalConnectionRoute.Subnet(address: Data([192, 0, 2, 35]), mask: Data([255, 255, 255, 240]))
        XCTAssertTrue(subnet.contains(Data([192, 0, 2, 46])))
        XCTAssertFalse(subnet.contains(Data([192, 0, 2, 49])))
        XCTAssertFalse(subnet.contains(Data(repeating: 0, count: 16)))
        let invalid = LocalConnectionRoute.Subnet(address: Data([192, 0, 2, 35]), mask: Data(repeating: 0, count: 4))
        XCTAssertFalse(invalid.contains(Data([192, 0, 2, 46])))
        let ipv6 = LocalConnectionRoute.Subnet(address: Data([0x20, 1, 0x0d, 0xb8] + Array(repeating: 0, count: 12)),
            mask: Data(Array(repeating: 255, count: 8) + Array(repeating: 0, count: 8)))
        XCTAssertTrue(ipv6.contains(Data([0x20, 1, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [3])))
        XCTAssertFalse(ipv6.contains(Data([0x20, 1, 0x0d, 0xb9] + Array(repeating: 0, count: 12))))
    }

    func testAuthenticatedSocketLocalityUsesSourceInterfaceAndMaskInsteadOfPrivateRange() {
        let source = Data([192, 0, 2, 35])
        let physical = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data([255, 255, 255, 240])), kind: .physical)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 46]), local: source,
            interfaces: [physical]), true)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 49]), local: source,
            interfaces: [physical]), false)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([10, 0, 0, 5]), local: source,
            interfaces: [physical]), false, "A private address beyond the source subnet is still remote")
        let vpn = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data([255, 255, 255, 0])), kind: .other)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 46]), local: source,
            interfaces: [vpn]), false, "A tunnel source must not inherit the physical LAN classification")
        XCTAssertNil(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 46]), local: source,
            interfaces: [physical, vpn]))
    }

    func testUnknownOrAmbiguousSourceRouteKeepsFullCompressionPolicy() {
        let source = Data([192, 0, 2, 35]), peer = Data([192, 0, 2, 46])
        let kinds: [LocalConnectionRoute.InterfaceKind] = [.unknown, .physical]
        for kind in kinds {
            let invalid = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
                mask: Data(repeating: 0, count: 4)), kind: kind)
            XCTAssertNil(LocalConnectionRoute.isLocal(peer: peer, local: source, interfaces: [invalid]))
        }
        let unknown = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data([255, 255, 255, 0])), kind: .unknown)
        XCTAssertNil(LocalConnectionRoute.isLocal(peer: peer, local: source, interfaces: [unknown]))
        XCTAssertNil(LocalConnectionRoute.isLocal(peer: peer, local: source, interfaces: []))
        let narrow = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data([255, 255, 255, 248])), kind: .physical)
        let wide = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data([255, 255, 255, 0])), kind: .physical)
        let ambiguous = LocalConnectionRoute.isLocal(peer: peer, local: source, interfaces: [narrow, wide])
        XCTAssertNil(ambiguous)
        XCTAssertEqual(RemoteImageCompressionPolicy.remoteOnly.factor(isLocalConnection: ambiguous), 1)
    }

    func testAuthenticatedIPv6AndLoopbackLocalityRejectCrossFamilyAndRemoteSubnet() {
        let source = Data([0x20, 1, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [3])
        let local = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: source,
            mask: Data(Array(repeating: 255, count: 8) + Array(repeating: 0, count: 8))), kind: .physical)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([0x20, 1, 0x0d, 0xb8] + Array(repeating: 0, count: 11) + [4]),
            local: source, interfaces: [local]), true)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([0x20, 1, 0x0d, 0xb9] + Array(repeating: 0, count: 11) + [4]),
            local: source, interfaces: [local]), false)
        XCTAssertNil(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 46]), local: source, interfaces: [local]))
        let loopback = LocalConnectionRoute.InterfaceSubnet(subnet: .init(address: Data([127, 0, 0, 1]),
            mask: Data([255, 0, 0, 0])), kind: .loopback)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([127, 0, 0, 1]), local: loopback.subnet.address,
            interfaces: [loopback]), true)
        XCTAssertEqual(LocalConnectionRoute.isLocal(peer: Data([192, 0, 2, 46]), local: loopback.subnet.address,
            interfaces: [loopback]), false)
    }

    func testLegacySyncBytesRemainStableAndCompressionMergesWithIndependentEdits() throws {
        let device = RemoteDevice(name: "Sync QA", host: "qa.invalid")
        var a = DeviceSyncDocument(replicaID: UUID())
        try a.recordLocalDevices([device])
        let bytes = try a.encoded()
        XCTAssertEqual(try DeviceSyncDocument(data: bytes, replicaID: UUID()).encoded(), bytes)
        var b = try DeviceSyncDocument(data: bytes, replicaID: UUID())
        var left = device, right = device
        left.name = "Renamed QA"
        right.imageCompression = .remoteOnly
        try a.recordLocalDevices([left]); try b.recordLocalDevices([right])
        let before = a; try a.merge(b); try b.merge(before)
        XCTAssertEqual(try a.encoded(), try b.encoded())
        let merged = try XCTUnwrap(a.devices().first)
        XCTAssertEqual(merged.name, left.name)
        XCTAssertEqual(merged.imageCompression, .remoteOnly)
    }

    func testExplicitFullResolutionWinsWithoutOlderReplicaRestoringCompression() throws {
        var device = RemoteDevice(name: "Sync QA", host: "qa.invalid", imageCompression: .always)
        var a = DeviceSyncDocument(replicaID: UUID()); try a.recordLocalDevices([device])
        var older = try DeviceSyncDocument(data: a.encoded(), replicaID: UUID())
        device.imageCompression = nil
        try a.recordLocalDevices([device])
        let full = a; try a.merge(older); try older.merge(full)
        XCTAssertEqual(try a.encoded(), try older.encoded())
        XCTAssertNil(a.devices().first?.imageCompression)
        XCTAssertEqual(a.devices().first?.effectiveImageCompression, .never)
    }

    func testInvalidCompressionSyncValueAndZeroRevisionAreRejected() throws {
        var document = DeviceSyncDocument(replicaID: UUID())
        try document.recordLocalDevices([RemoteDevice(name: "Sync QA", host: "qa.invalid", imageCompression: .always)])
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
        for badValue in ["unsupported-policy", "Always"] {
            var object = original
            var records = object["records"] as! [[String: Any]]
            var preference = records[0]["imageCompression"] as! [String: Any]
            preference["value"] = badValue
            if badValue == "Always" {
                var revision = preference["revision"] as! [String: Any]
                revision["counter"] = 0; preference["revision"] = revision
            }
            records[0]["imageCompression"] = preference; object["records"] = records
            let bytes = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try DeviceSyncDocument(data: bytes, replicaID: UUID()))
        }
    }
}
