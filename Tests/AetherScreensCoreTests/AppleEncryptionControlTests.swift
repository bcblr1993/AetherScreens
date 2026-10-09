import XCTest
@testable import AetherScreensCore

final class AppleEncryptionControlTests: XCTestCase {
    func testIndependentPreludeWireBytes() {
        XCTAssertEqual(Array(AppleEncryptionControl.requestReceiveEncryption),
                       [18, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1])
        XCTAssertEqual(Array(AppleEncryptionControl.enableSendEncryption), [18, 0, 0, 2, 0, 1, 0, 0])
        XCTAssertEqual(Array(AppleEncryptionControl.observe), [10, 0, 0, 0])
        XCTAssertEqual(Array(AppleEncryptionControl.normalControl), [10, 0, 0, 1])
    }

    func testRekeyEnvelopeRejectsEveryModifiedByteAndWrongLengths() {
        let update = Data([0, 0, 0, 1])
        let rectangle = Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 79])
        XCTAssertTrue(AppleEncryptionControl.isInitialRekey(updateHeader: update, rectangleHeader: rectangle))
        for index in update.indices {
            var changed = update; changed[index] ^= 1
            XCTAssertFalse(AppleEncryptionControl.isInitialRekey(updateHeader: changed, rectangleHeader: rectangle))
        }
        for index in rectangle.indices {
            var changed = rectangle; changed[index] ^= 1
            XCTAssertFalse(AppleEncryptionControl.isInitialRekey(updateHeader: update, rectangleHeader: changed))
        }
        for changed in [Data(), Data(rectangle.dropLast()), rectangle + Data([0])] {
            XCTAssertFalse(AppleEncryptionControl.isInitialRekey(updateHeader: update, rectangleHeader: changed))
        }
    }
}
