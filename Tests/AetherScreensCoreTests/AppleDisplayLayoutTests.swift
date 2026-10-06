import XCTest
import CoreGraphics
@testable import AetherScreensCore

/// Independent wire builder: byte offsets/edge order come from the documented
/// Apple layout, not the production decoder. Small artificial screens only.
enum AppleDisplayTestPayload {
    struct Screen {
        var id: UInt32
        var logical: CGRect
        var backing: CGRect
        var density: Double = 1
        var scale: Double = 1
        var flags: UInt32 = 0
    }
    static let screens: [Screen] = [
        .init(id: 0, logical: CGRect(x: -8, y: 0, width: 8, height: 8),
              backing: CGRect(x: -8, y: 0, width: 8, height: 8), flags: 1),
        .init(id: 22, logical: CGRect(x: 0, y: 0, width: 8, height: 8),
              backing: CGRect(x: 0, y: 0, width: 8, height: 8))
    ]
    static func be16(_ value: UInt16) -> Data { Data([UInt8(value >> 8), UInt8(value & 255)]) }
    static func be32(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    static func double(_ value: Double) -> Data {
        let bits = value.bitPattern
        return Data((0..<8).map { UInt8((bits >> (56 - 8 * $0)) & 255) })
    }
    static func edges(_ rect: CGRect) -> Data {
        [rect.minY, rect.minX, rect.maxY, rect.maxX].reduce(Data()) {
            $0 + be16(UInt16(bitPattern: Int16($1)))
        }
    }
    static func body(selected: UInt32? = nil, screens: [Screen] = screens, width: UInt16? = nil, height: UInt16 = 8) -> Data {
        var data = be16(5) + be16(16) + be16(8) + be16(width ?? (selected == nil ? 16 : 8)) + be16(height)
        data += be32(selected ?? UInt32.max) + be32(0x1234) + be16(UInt16(screens.count))
        for screen in screens {
            data += double(screen.density) + double(screen.scale) + be32(screen.id)
            data += edges(screen.logical) + edges(screen.backing) + be32(screen.flags)
            data += RFBPixelFormat.standardBGRA32.serializedData
        }
        return data
    }
}

final class AppleDisplayLayoutTests: XCTestCase {
    func testSignedEdgesWireZeroIDAndMainFlagArePreserved() throws {
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body()))
        XCTAssertNil(layout.selectedDisplayID)
        XCTAssertEqual(layout.width, 16)
        XCTAssertEqual(layout.sessionFlags, 0x1234)
        XCTAssertEqual(layout.screens.map(\.id), [0, 22])
        XCTAssertEqual(layout.screens[0].backingBounds, CGRect(x: -8, y: 0, width: 8, height: 8))
        XCTAssertTrue(layout.screens[0].isMain)
        XCTAssertFalse(layout.screens[1].isMain)
        XCTAssertEqual(layout.serverCoordinates(x: 4, y: 3)?.0, 4)
        XCTAssertEqual(layout.serverCoordinates(x: 12, y: 3)?.0, 12)
    }
    func testSelectedScreenUsesLocalOriginAndUndoesConfirmedScale() throws {
        var screens = AppleDisplayTestPayload.screens
        screens[1].density = 2
        screens[1].scale = 0.5
        screens[1].logical = CGRect(x: 40, y: -20, width: 8, height: 8)
        screens[1].backing = CGRect(x: 100, y: -40, width: 8, height: 8)
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22, screens: screens)))
        XCTAssertEqual(layout.serverCoordinates(x: 4, y: 3)?.0, 8)
        XCTAssertEqual(layout.serverCoordinates(x: 4, y: 3)?.1, 6)
        XCTAssertEqual(layout.serverCoordinates(x: 999, y: 999)?.0, 14)
    }
    func testCombinedGapsRejectNewPosition() throws {
        var screens = AppleDisplayTestPayload.screens
        screens[1].backing.origin.x = 4
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens, width: 20)))
        XCTAssertNotNil(layout.serverCoordinates(x: 4, y: 3))
        XCTAssertNil(layout.serverCoordinates(x: 9, y: 3))
        XCTAssertNotNil(layout.serverCoordinates(x: 12, y: 3))
    }
    func testZeroDensityDerivesScaleAndInvalidScaleFallsBack() throws {
        var screens = AppleDisplayTestPayload.screens
        screens[0].density = 0
        screens[0].scale = 0.5
        screens[1].scale = .nan
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens)))
        XCTAssertEqual(layout.screens[0].nativeDensity, 2)
        XCTAssertEqual(layout.screens[0].serverScale, 0.5)
        XCTAssertEqual(layout.screens[1].serverScale, 1)
    }
    func testMalformedVersionCountLengthIDsAndSelectionAreRejected() {
        let body = AppleDisplayTestPayload.body()
        XCTAssertNil(RFBAppleDisplayLayout.parse(Data(body.prefix(19))))
        XCTAssertNil(RFBAppleDisplayLayout.parse(Data(body.dropLast())))
        XCTAssertNil(RFBAppleDisplayLayout.parse(Data(repeating: 0, count: 4097)))
        for (offset, value): (Int, UInt8) in [(1, 4), (19, 26), (19, 0)] {
            var malformed = body; malformed[offset] = value
            XCTAssertNil(RFBAppleDisplayLayout.parse(malformed))
        }
        var screens = AppleDisplayTestPayload.screens
        screens[1].id = 0
        XCTAssertNil(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens)))
        screens[1].id = UInt32.max
        XCTAssertNil(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens)))
        XCTAssertNil(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 99)))
    }
    func testUnusableRecordIsDroppedButCannotBeSelected() throws {
        var screens = AppleDisplayTestPayload.screens
        screens[1].logical.size.width = 0
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens)))
        XCTAssertEqual(layout.screens.count, 1)
        XCTAssertNil(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(selected: 22, screens: screens)))
    }
    func testMirroredFlagsUnknownBitsAndTrailingBytesStayAligned() throws {
        var screens = AppleDisplayTestPayload.screens
        screens[1].flags = 0x80000002
        let layout = try XCTUnwrap(RFBAppleDisplayLayout.parse(AppleDisplayTestPayload.body(screens: screens) + Data([1, 2, 3])))
        XCTAssertTrue(layout.screens[1].isMirrored)
        XCTAssertEqual(layout.screens[1].flags, 0x80000002)
    }
    func testNativeSetDisplayFramingKeepsWireZeroDistinctFromAll() {
        XCTAssertEqual(RFBEncoder.encodeAppleSetDisplay(nil), Data([13, 1, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(RFBEncoder.encodeAppleSetDisplay(0), Data([13, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(RFBEncoder.encodeAppleSetDisplay(0x12345678), Data([13, 0, 0, 0, 0x12, 0x34, 0x56, 0x78]))
    }
}
