import XCTest
import CoreGraphics
@testable import AetherScreensCore

final class ThumbnailStoreTests: XCTestCase {

    func testThumbnailSaveAndRetrieve() {
        let store = ThumbnailStore.shared
        let testId = UUID()

        // Create a 100x100 dummy test CGImage
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 200, count: width * height * 4)
        let provider = CGDataProvider(data: Data(rawData) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        store.saveThumbnail(cgImage, for: testId)
        let retrieved = store.getThumbnail(for: testId)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.width, width)
        XCTAssertEqual(retrieved?.height, height)
    }

    func testLargeDesktopIsStoredAsCompactPreview() {
        let width = 1920
        let height = 1080
        let bytes = Data(repeating: 120, count: width * height * 4)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let id = UUID()

        ThumbnailStore.shared.saveThumbnail(image, for: id)
        let preview = ThumbnailStore.shared.getThumbnail(for: id)
        XCTAssertEqual(preview?.width, 480)
        XCTAssertEqual(preview?.height, 270)
    }
}
