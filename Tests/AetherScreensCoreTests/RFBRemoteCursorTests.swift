import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import AetherScreensCore

final class RFBRemoteCursorTests: XCTestCase {
    #if canImport(AppKit)
    @MainActor
    func testNonhiddenCursorWithoutRenderableBitmapFallsBackToArrow() {
        let view = MacNativeInputView()
        let malformed = RFBRemoteCursor(width: 16, height: 16, hotspotX: 0, hotspotY: 0,
            pixels: Data())
        XCTAssertFalse(malformed.isHidden)
        XCTAssertNil(malformed.makeCGImage())
        view.setRemoteCursor(malformed)
        XCTAssertTrue(view.remoteCursor === NSCursor.arrow)
    }

    @MainActor
    func testNativeMacCursorCachesShapeHotspotAndResetsToArrow() throws {
        let view = MacNativeInputView()
        let shape = try XCTUnwrap(RFBRemoteCursor.decode(width: 3, height: 1, hotspotX: 2, hotspotY: 0,
            depth: .fullColor, payload: Data([1,2,3,0, 4,5,6,0, 7,8,9,0, 0xe0])))
        view.setRemoteCursor(shape)
        XCTAssertEqual(view.remoteCursor.hotSpot, NSPoint(x: 2, y: 0))
        XCTAssertEqual(view.remoteCursor.image.size, NSSize(width: 3, height: 1))
        let cached = view.remoteCursor
        view.remoteSize = NSSize(width: 3840, height: 2160)
        XCTAssertTrue(view.remoteCursor === cached)
        let hidden = try XCTUnwrap(RFBRemoteCursor.decode(width: 0, height: 0, hotspotX: 0, hotspotY: 0,
            depth: .fullColor, payload: Data()))
        view.setRemoteCursor(hidden)
        XCTAssertFalse(view.remoteCursor === NSCursor.arrow)
        view.setRemoteCursor(nil)
        XCTAssertTrue(view.remoteCursor === NSCursor.arrow)
    }
    #endif

    func testImmutableImageIsReusedWithoutChangingValueEquality() throws {
        let payload = Data([10,20,30,0,0x80])
        let first = try XCTUnwrap(RFBRemoteCursor.decode(width: 1, height: 1, hotspotX: 0, hotspotY: 0,
            depth: .fullColor, payload: payload))
        let second = try XCTUnwrap(RFBRemoteCursor.decode(width: 1, height: 1, hotspotX: 0, hotspotY: 0,
            depth: .fullColor, payload: payload))
        let image = try XCTUnwrap(first.makeCGImage())
        XCTAssertTrue(image === first.makeCGImage())
        XCTAssertTrue(image === first.makeCGImage())
        XCTAssertEqual(first, second)
        XCTAssertFalse(image === second.makeCGImage())
    }

    func testMaskMSBAndPaddedRowsOverrideUnusedPixelAlpha() throws {
        let raw = Data((0..<18).flatMap { _ in [UInt8(10), 20, 30, 0] }) + Data([0x80, 0x80, 0x40, 0])
        let cursor = try XCTUnwrap(RFBRemoteCursor.decode(width: 9, height: 2, hotspotX: 8, hotspotY: 1, depth: .fullColor, payload: raw))
        XCTAssertEqual(cursor.pixels.prefix(8), Data([10, 20, 30, 255, 0, 0, 0, 0]))
        XCTAssertEqual(cursor.pixels[32..<36], Data([10, 20, 30, 255]))
        XCTAssertEqual(cursor.pixels[36..<44], Data([0, 0, 0, 0, 10, 20, 30, 255]))
        XCTAssertEqual(cursor.hotspotX, 8); XCTAssertEqual(cursor.hotspotY, 1)
        let image = try XCTUnwrap(cursor.makeCGImage())
        XCTAssertEqual(image.width, 9); XCTAssertEqual(image.height, 2)
    }

    func testRGB565UsesTwoWireBytesAndCorrectColors() throws {
        XCTAssertEqual(RFBRemoteCursor.payloadSize(width: 3, height: 1, depth: .rgb565), 7)
        let cursor = try XCTUnwrap(RFBRemoteCursor.decode(width: 3, height: 1, hotspotX: 1, hotspotY: 0,
            depth: .rgb565, payload: Data([0, 248, 224, 7, 31, 0, 0xe0])))
        XCTAssertEqual(cursor.pixels, Data([0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255]))
    }

    func testHiddenCursorAndUntrustedBounds() throws {
        let hidden = try XCTUnwrap(RFBRemoteCursor.decode(width: 0, height: 0, hotspotX: 0, hotspotY: 0, depth: .fullColor, payload: Data()))
        XCTAssertTrue(hidden.isHidden); XCTAssertNil(hidden.makeCGImage())
        XCTAssertEqual(RFBRemoteCursor.payloadSize(width: 0, height: 65_535, depth: .rgb565), 0)
        XCTAssertTrue(try XCTUnwrap(RFBRemoteCursor.decode(width: 65_535, height: 0, hotspotX: 99, hotspotY: 99, depth: .fullColor, payload: Data())).isHidden)
        XCTAssertNil(RFBRemoteCursor.payloadSize(width: 513, height: 1, depth: .fullColor))
        XCTAssertNil(RFBRemoteCursor.decode(width: 1, height: 1, hotspotX: 1, hotspotY: 0, depth: .fullColor, payload: Data(repeating: 0, count: 5)))
        for size in [0, 4, 6] {
            XCTAssertNil(RFBRemoteCursor.decode(width: 1, height: 1, hotspotX: 0, hotspotY: 0, depth: .fullColor, payload: Data(repeating: 0, count: size)))
        }
    }
}
