import XCTest
@testable import AetherScreensCore

final class FramebufferDamageTests: XCTestCase {
    private func snapshot(_ fb: Framebuffer, since revision: UInt64? = nil) -> (regions: [CGRect], revision: UInt64, pixels: [UInt8]) {
        var result: (regions: [CGRect], revision: UInt64, pixels: [UInt8]) = ([], 0, [])
        fb.withPixelChanges(since: revision) { bytes, _, _, regions, current in
            result = (regions, current, Array(bytes))
        }
        return result
    }

    func testIndependentReadersSeeDisjointChangesAndImageSnapshotsDoNotConsumeThem() {
        let fb = Framebuffer(width: 32, height: 32)
        let first = snapshot(fb)
        XCTAssertEqual(first.regions, [CGRect(x: 0, y: 0, width: 32, height: 32)])
        XCTAssertTrue(snapshot(fb, since: first.revision).regions.isEmpty)
        fb.updateRect(x: 1, y: 2, width: 1, height: 1, rawData: Data([1, 2, 3, 255]))
        fb.updateRect(x: 20, y: 21, width: 1, height: 1, rawData: Data([4, 5, 6, 255]))
        _ = fb.makeCGImage()
        let fast = snapshot(fb, since: first.revision)
        let slow = snapshot(fb, since: first.revision)
        XCTAssertEqual(fast.regions, [CGRect(x: 1, y: 2, width: 1, height: 1), CGRect(x: 20, y: 21, width: 1, height: 1)])
        XCTAssertEqual(fast.regions, slow.regions)
        XCTAssertEqual(fast.pixels, slow.pixels)
        XCTAssertTrue(snapshot(fb, since: fast.revision).regions.isEmpty)
    }

    func testLaggingReadersGetFullImageAfterHistoryOverflowAndResize() {
        let fb = Framebuffer(width: 32, height: 32)
        let initial = snapshot(fb)
        for index in 0..<80 {
            fb.updateRect(x: index % 32, y: index / 32, width: 1, height: 1, rawData: Data([UInt8(index), 1, 2, 255]))
        }
        let late = snapshot(fb, since: initial.revision)
        XCTAssertEqual(late.regions, initial.regions)
        XCTAssertEqual(Array(late.pixels[(2 * 32 + 15) * 4..<(2 * 32 + 16) * 4]), [79, 1, 2, 255])
        fb.resize(newWidth: 4, newHeight: 3)
        let resized = snapshot(fb, since: late.revision)
        XCTAssertEqual(resized.regions, [CGRect(x: 0, y: 0, width: 4, height: 3)])
        XCTAssertEqual(resized.pixels, Array(repeating: 0, count: 48))
    }

    func testCopyRectOverlapsAndClippedCoordinatesMatchOriginalImage() {
        for (srcX, srcY, dstX, dstY, requestedWidth, requestedHeight) in [
            (1, 0, 2, 1, 5, 4), (2, 1, 1, 0, 5, 4), (1, 1, 2, 1, 5, 3),
            (2, 1, 1, 1, 5, 3), (5, 4, 6, 3, 5, 5)
        ] {
            let fb = Framebuffer(width: 8, height: 6)
            let original: [UInt8] = (0..<48).flatMap { value -> [UInt8] in [UInt8(value), 0, 0, 255] }
            fb.updateRect(x: 0, y: 0, width: 8, height: 6, rawData: Data(original))
            let before = snapshot(fb)
            fb.copyRect(srcX: srcX, srcY: srcY, dstX: dstX, dstY: dstY, width: requestedWidth, height: requestedHeight)
            let width = min(requestedWidth, 8 - max(srcX, dstX))
            let height = min(requestedHeight, 6 - max(srcY, dstY))
            var expected = original
            for row in 0..<height {
                for column in 0..<width {
                    let source = ((srcY + row) * 8 + srcX + column) * 4
                    let destination = ((dstY + row) * 8 + dstX + column) * 4
                    expected.replaceSubrange(destination..<(destination + 4), with: original[source..<(source + 4)])
                }
            }
            let copied = snapshot(fb, since: before.revision)
            XCTAssertEqual(copied.pixels, expected)
            XCTAssertEqual(copied.regions, [CGRect(x: dstX, y: dstY, width: width, height: height)])
        }
    }

    func testRawClippingKeepsSourceRowStrideAndInvalidRequestsDoNotModifyState() {
        let fb = Framebuffer(width: 4, height: 3)
        let before = snapshot(fb)
        let payload: [UInt8] = (1...6).flatMap { value -> [UInt8] in [UInt8(value), 0, 0, 255] }
        fb.updateRect(x: 3, y: 1, width: 3, height: 2, rawData: Data(payload))
        let clipped = snapshot(fb, since: before.revision)
        XCTAssertEqual(clipped.regions, [CGRect(x: 3, y: 1, width: 1, height: 2)])
        XCTAssertEqual(Array(clipped.pixels[28..<32]), [1, 0, 0, 255])
        XCTAssertEqual(Array(clipped.pixels[44..<48]), [4, 0, 0, 255])
        fb.updateRect(x: -1, y: 0, width: 1, height: 1, rawData: Data([99, 0, 0, 255]))
        fb.updateRect(x: 0, y: 0, width: 1, height: 1, rawData: Data([99]))
        fb.copyRect(srcX: -1, srcY: 0, dstX: 0, dstY: 0, width: 1, height: 1)
        fb.copyRect(srcX: 0, srcY: 0, dstX: 4, dstY: 0, width: 1, height: 1)
        let unchanged = snapshot(fb, since: clipped.revision)
        XCTAssertTrue(unchanged.regions.isEmpty)
        XCTAssertEqual(unchanged.pixels, clipped.pixels)
    }
}
