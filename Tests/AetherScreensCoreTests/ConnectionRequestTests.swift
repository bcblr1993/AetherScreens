import XCTest
@testable import AetherScreensCore

final class ConnectionRequestTests: XCTestCase {
    func testAccountAddressNormalizationPreservesPassword() throws {
        let request = try XCTUnwrap(ConnectionRequest(host: "  studio.local\n", port: " 5901 ",
                                                      name: " Desk ", username: " qa-user ", password: " secret "))
        XCTAssertEqual(request.device.host, "studio.local")
        XCTAssertEqual(request.device.port, 5901)
        XCTAssertEqual(request.device.name, "Desk")
        XCTAssertEqual(request.device.username, "qa-user")
        XCTAssertEqual(request.device.authMethod, .macAccount)
        XCTAssertEqual(request.password, " secret ", "Password whitespace is significant")
    }

    func testInvalidAddressAndPortCannotConnect() {
        for host in ["", " \n", "two hosts", "vnc://studio.local", "user@studio.local", "studio.local:5900", "[broken"] {
            XCTAssertNil(ConnectionRequest(host: host))
        }
        for port in ["0", "65536", "-1", "5900x", ""] {
            XCTAssertNil(ConnectionRequest(host: "studio.local", port: port))
        }
        XCTAssertNotNil(ConnectionRequest(host: "2001:db8::1"))
        XCTAssertEqual(ConnectionRequest(host: "[2001:db8::1]")?.device.host, "2001:db8::1")
    }

    func testEmptyAccountSelectsVNCOrUnauthenticatedConnection() throws {
        let vnc = try XCTUnwrap(ConnectionRequest(host: "127.0.0.1", username: " ", password: "qa-only"))
        XCTAssertEqual(vnc.device.name, "127.0.0.1")
        XCTAssertNil(vnc.device.username)
        XCTAssertEqual(vnc.device.authMethod, .vncPassword)
        let noPassword = try XCTUnwrap(ConnectionRequest(host: "127.0.0.1"))
        XCTAssertEqual(noPassword.device.authMethod, .none)
        XCTAssertNil(noPassword.password)
    }
}
