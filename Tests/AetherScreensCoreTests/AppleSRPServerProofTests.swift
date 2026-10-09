import XCTest
@testable import AetherScreensCore

final class AppleSRPServerProofTests: XCTestCase {
    private var fixture: Data {
        var value = Data([0,0,0,98,0,0,0,3,0,92,0,0,0,88,64])
        value.append(Data(0..<64))
        value.append(16)
        value.append(Data(64..<80))
        value.append(Data(repeating: 0, count: 6))
        return value
    }

    func testExactProfileAndEveryTruncation() throws {
        let frame = fixture
        let decoded = try AppleSRPServerProof(frame: frame, expectedStep: 3)
        XCTAssertEqual(decoded.proof, Data(0..<64))
        XCTAssertEqual(decoded.random, Data(64..<80))
        var actualStageShape = frame
        actualStageShape[7] = 2
        XCTAssertNoThrow(try AppleSRPServerProof(frame: actualStageShape, expectedStep: 2))
        XCTAssertThrowsError(try AppleSRPServerProof(frame: actualStageShape, expectedStep: 3))
        for length in 0..<frame.count {
            XCTAssertThrowsError(try AppleSRPServerProof(frame: Data(frame.prefix(length)), expectedStep: 3))
        }
        XCTAssertThrowsError(try AppleSRPServerProof(frame: frame + Data([0]), expectedStep: 3))
        XCTAssertThrowsError(try AppleSRPServerProof(frame: Data(count: 8193), expectedStep: 3))
        XCTAssertThrowsError(try AppleSRPServerProof(frame: frame, expectedStep: 2))
    }

    func testRejectsEveryEnvelopeLengthAndReservedByteMutation() {
        for index in Array(0..<15) + [79] + Array(96..<102) {
            var frame = fixture
            frame[index] ^= 1
            XCTAssertThrowsError(try AppleSRPServerProof(frame: frame, expectedStep: 3))
        }
    }
}
