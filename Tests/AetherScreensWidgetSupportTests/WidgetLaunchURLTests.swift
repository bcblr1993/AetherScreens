import Foundation
import XCTest
@testable import AetherScreensWidgetSupport

final class WidgetLaunchURLTests: XCTestCase {
    private let id = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!

    func testWidgetURLRoundTripsOnlyItsUUIDAndLibraryIsSeparate() {
        let url = WidgetLaunchURL.url(for: id)
        XCTAssertEqual(url.absoluteString, "aetherscreens://widget/" + id.uuidString)
        XCTAssertEqual(WidgetLaunchURL.parse(url), id)
        XCTAssertEqual(WidgetLaunchURL.libraryURL.absoluteString, "aetherscreens://library")
        XCTAssertNil(WidgetLaunchURL.parse(WidgetLaunchURL.libraryURL))
    }

    func testUUIDLetterCaseIsAcceptedWithoutChangingTheIdentifier() throws {
        for value in [id.uuidString.lowercased(), "AbCdEf01-2345-6789-AbCd-Ef0123456789"] {
            XCTAssertEqual(WidgetLaunchURL.parse(try XCTUnwrap(URL(string: "aetherscreens://widget/" + value))), id)
        }
    }

    func testRejectsCredentialsPortsQueriesFragmentsAndOtherRoutes() throws {
        let value = id.uuidString
        let invalid = [
            "https://widget/" + value, "aetherscreens://connect/" + value,
            "aetherscreens://library/" + value, "aetherscreens://user@widget/" + value,
            "aetherscreens://user:password@widget/" + value, "aetherscreens://@widget/" + value,
            "aetherscreens://widget:123/" + value, "aetherscreens://widget:/" + value,
            "aetherscreens://widget/" + value + "?", "aetherscreens://widget/" + value + "?host=synthetic.invalid",
            "aetherscreens://widget/" + value + "#", "aetherscreens://widget/" + value + "#fragment",
            "aetherscreens://widget/" + value + "/", "aetherscreens://widget//" + value,
            "aetherscreens://widget/extra/" + value, "aetherscreens://widget/",
            "aetherscreens://widget/not-a-uuid", "aetherscreens://widget/" + value.replacingOccurrences(of: "-", with: ""),
            "aetherscreens://widget/" + value.replacingOccurrences(of: "A", with: "%41"),
            "aetherscreens://widg%65t/" + value, "aetherscreens://widget/%2F" + value,
            "AETHERSCREENS://widget/" + value, "aetherscreens://WIDGET/" + value
        ]
        for sample in invalid {
            XCTAssertNil(URL(string: sample).flatMap(WidgetLaunchURL.parse), sample)
        }
    }

    func testRejectsRelativeURLsAndNonHexUUIDPaths() throws {
        let relative = try XCTUnwrap(URL(string: id.uuidString, relativeTo: URL(string: "aetherscreens://widget/")))
        XCTAssertNil(WidgetLaunchURL.parse(relative))
        XCTAssertNil(WidgetLaunchURL.parse(try XCTUnwrap(URL(string: "aetherscreens://widget/" + id.uuidString.replacingOccurrences(of: "A", with: "G")))))
    }
}
