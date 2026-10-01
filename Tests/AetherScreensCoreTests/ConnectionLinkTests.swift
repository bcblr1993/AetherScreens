import XCTest
@testable import AetherScreensCore

final class ConnectionLinkTests: XCTestCase {
    private func link(_ value: String) throws -> ConnectionLink { try ConnectionLink(url: XCTUnwrap(URL(string: value))) }

    func testCopiedSavedLinkContainsOnlyIdentifierAndMode() throws {
        let device = RemoteDevice(name: "Work Mac", host: "192.0.2.10", username: "account")
        let url = ConnectionLink.savedURL(for: device.id, observeOnly: true)
        XCTAssertFalse(url.absoluteString.contains(device.host))
        XCTAssertFalse(url.absoluteString.contains("account"))
        let resolved = try ConnectionLink(url: url).resolve(devices: [device]) { _ in "stored-password" }
        XCTAssertEqual(resolved.device, device)
        XCTAssertEqual(resolved.password, "stored-password")
        XCTAssertEqual(resolved.observeOnly, true)
        XCTAssertTrue(resolved.requiresIndependentSession, "An explicit mode cannot silently reuse a different live mode")
        XCTAssertFalse(resolved.isTemporary)
    }

    func testSavedNamesAndAddressesResolveButAmbiguousNamesRequireIdentifier() throws {
        let one = RemoteDevice(name: "Studio Mac", host: "192.0.2.11")
        let two = RemoteDevice(name: "Studio Mac", host: "192.0.2.12")
        let selected = try link("aetherscreens://saved?name=studio%20mac").resolve(devices: [one]) { _ in nil }
        XCTAssertEqual(selected.device.id, one.id)
        XCTAssertFalse(selected.requiresIndependentSession)
        let address = try link("aetherscreens://saved?name=192.0.2.12").resolve(devices: [one, two]) { _ in nil }
        XCTAssertEqual(address.device.id, two.id)
        XCTAssertThrowsError(try link("aetherscreens://saved?name=Studio%20Mac").resolve(devices: [one, two]) { _ in nil }) {
            XCTAssertEqual($0 as? ConnectionLink.Failure, .ambiguousSavedComputer)
        }
    }

    func testAccountOverrideNeverUsesOtherAccountsStoredPasswordOrPersists() throws {
        let device = RemoteDevice(name: "Work", host: "192.0.2.10", authMethod: .macAccount, username: "old-account")
        var credentialReads = 0
        let resolved = try link("aetherscreens://saved/\(device.id)?username=new-account").resolve(devices: [device]) { _ in
            credentialReads += 1
            return "other-account-password"
        }
        XCTAssertEqual(credentialReads, 0)
        XCTAssertNil(resolved.password)
        XCTAssertEqual(resolved.device.username, "new-account")
        XCTAssertEqual(resolved.device.authMethod, .macAccount)
        XCTAssertTrue(resolved.isTemporary)
        XCTAssertTrue(resolved.requiresIndependentSession)
        XCTAssertEqual(device.username, "old-account")
    }

    func testExplicitPasswordOverridesStayInMemoryAndSkipCredentialLookup() throws {
        let device = RemoteDevice(name: "Work", host: "192.0.2.10")
        let resolved = try link("aetherscreens://saved/\(device.id)?password=temporary-secret").resolve(devices: [device]) { _ in
            XCTFail("An explicit password must not read or mutate Keychain")
            return nil
        }
        XCTAssertEqual(resolved.password, "temporary-secret")
        XCTAssertTrue(resolved.isTemporary)
    }

    func testVNCCredentialsAreDecodedExactlyOnceAndIPv6IsNormalized() throws {
        let resolved = try link("vnc://a%2520b:p%2540@[::1]:5901?observe=false").resolve(devices: []) { _ in nil }
        XCTAssertEqual(resolved.device.username, "a%20b")
        XCTAssertEqual(resolved.password, "p%40")
        XCTAssertEqual(resolved.device.host, "::1")
        XCTAssertEqual(resolved.device.port, 5901)
        XCTAssertEqual(resolved.observeOnly, false)
        XCTAssertTrue(resolved.isTemporary)
    }

    func testTemporaryOwnSchemeAndUnicodeLabels() throws {
        let resolved = try link("aetherscreens://connect?host=192.0.2.10&port=5990&name=%E5%B7%A5%E4%BD%9C%20Mac&username=qa&password=p%26q").resolve(devices: []) { _ in nil }
        XCTAssertEqual(resolved.device.name, "工作 Mac")
        XCTAssertEqual(resolved.device.port, 5990)
        XCTAssertEqual(resolved.password, "p&q")
        XCTAssertTrue(resolved.isTemporary)
    }

    func testInvalidAndUnimplementedParametersAreRejectedWithoutEchoingURL() throws {
        for value in ["aetherscreens://connect?host=qa.invalid&host=other.invalid", "vnc://qa.invalid:0", "vnc://qa.invalid:70000", "vnc://qa.invalid?observe=yes", "vnc://qa.invalid/path", "vnc://qa.invalid#secret", "vnc://qa.invalid?observe=true%0A", "aetherscreens://saved/not-a-uuid", "aetherscreens://connect?host=qa.invalid&username=" + String(repeating: "a", count: 2049)] {
            XCTAssertThrowsError(try link(value)) { XCTAssertEqual($0 as? ConnectionLink.Failure, .invalid) }
        }
        for option in ["guest=true", "ssh-key=key", "Observe=true"] {
            XCTAssertThrowsError(try link("vnc://qa.invalid?" + option)) { XCTAssertEqual($0 as? ConnectionLink.Failure, .unsupportedOption) }
        }
        XCTAssertThrowsError(try link("aetherscreens://saved/\(UUID())").resolve(devices: []) { _ in nil }) {
            XCTAssertEqual($0 as? ConnectionLink.Failure, .missingSavedComputer)
        }
    }
}
