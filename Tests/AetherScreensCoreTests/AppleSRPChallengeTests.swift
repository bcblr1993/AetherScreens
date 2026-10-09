import XCTest
@testable import AetherScreensCore

final class AppleSRPChallengeTests: XCTestCase {
    func testActualEnvelopeShapeAndOpaqueFieldBoundaries() throws {
        let frame = fixture()
        let challenge = try AppleSRPChallenge(frame:frame)
        XCTAssertEqual(challenge.step,2)
        XCTAssertEqual(challenge.modulus.count,512)
        XCTAssertEqual(challenge.generator,Data([5]))
        XCTAssertEqual(challenge.salt.count,32)
        XCTAssertEqual(challenge.serverPublic.count,512)
        XCTAssertEqual(challenge.iterations,131578)
        for length in 0..<frame.count {
            XCTAssertThrowsError(try AppleSRPChallenge(frame:Data(frame.prefix(length))))
        }
        for index in [3,7,9,13,14] {
            var changed=frame; changed[index]^=1
            XCTAssertThrowsError(try AppleSRPChallenge(frame:changed))
        }
        XCTAssertThrowsError(try AppleSRPChallenge(frame:frame+Data([0])))
        XCTAssertThrowsError(try AppleSRPChallenge(frame:Data(repeating:0,count:8193)))
    }
    func testCostAndVariableLengthFieldsMustBeBounded() throws {
        for cost in [UInt64(0),1_000_001,UInt64.max] {
            XCTAssertThrowsError(try AppleSRPChallenge(frame:fixture(cost:cost)))
        }
        XCTAssertThrowsError(try AppleSRPChallenge(frame:fixture(cost:11),maximumIterations:10))
        XCTAssertNoThrow(try AppleSRPChallenge(frame:fixture(cost:11),maximumIterations:11))
        XCTAssertThrowsError(try AppleSRPChallenge(frame:fixture(modulusBytes:513)))
        XCTAssertThrowsError(try AppleSRPChallenge(frame:fixture(modulusBytes:16)))
        for options in [Data(),Data([255]),Data([97,0,98]),Data(repeating:97,count:1025)] {
            XCTAssertThrowsError(try AppleSRPChallenge(frame:fixture(options:options)))
        }
    }
    // Mathematical values here are opaque parser fixtures, not trusted SRP groups.
    private func fixture(cost:UInt64=131578,modulusBytes:Int=512,options:Data=Data("mda=SHA-512".utf8))->Data {
        let n=Data(repeating:255,count:modulusBytes), b=Data(repeating:1,count:512)
        var payload=Data([0])
        for part in [word(UInt64(n.count),2),n,Data([0,1,5,32]),Data(repeating:2,count:32),
                     word(UInt64(b.count),2),b,word(cost,8),word(UInt64(options.count),2),options] {
            payload.append(part)
        }
        var frame=word(UInt64(payload.count+10),4)
        for part in [word(2,4),word(UInt64(payload.count+4),2),word(UInt64(payload.count),4),payload] {
            frame.append(part)
        }
        return frame
    }
    private func word(_ value:UInt64,_ bytes:Int)->Data {
        Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded:value >> ($0*8)) })
    }
}
