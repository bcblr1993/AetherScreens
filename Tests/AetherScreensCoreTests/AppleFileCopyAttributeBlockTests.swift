import XCTest
@testable import AetherScreensCore

final class AppleFileCopyAttributeBlockTests: XCTestCase {
    func testOutgoingTableMatchesIndependentNativeFramingFixture() throws {
        let entries: [AppleFileCopyAttributeBlock.Entry] = [
            .init(name: Data([0x61]), value: Data([0, 0xff, 0x80])),
            .init(name: Data([0x62, 0x63]), value: Data())
        ]
        let wire = try AppleFileCopyAttributeBlock.encode(entries: entries)
        XCTAssertEqual(wire, Data([
            0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1, 0, 42,
            0, 0, 0, 32, 0, 0, 0, 2,
            0, 0, 0, 2, 0, 0, 0, 3,
            0, 0, 0, 3, 0, 0, 0, 0,
            0x61, 0, 0, 0xff, 0x80, 0x62, 0x63, 0]))
        XCTAssertEqual(try AppleFileCopyAttributeBlock.decode(wire)?.entries(), entries)
    }

    func testOutgoingEnvelopeAcceptsExactLimitAndRejectsOverflowOrInvalidNames() throws {
        let maximumValue = Data(repeating: 0xa5, count: 65_507)
        let wire = try AppleFileCopyAttributeBlock.encode(entries: [
            .init(name: Data([0x61]), value: maximumValue)])
        XCTAssertEqual(wire.count, 65_535)
        XCTAssertEqual(try AppleFileCopyAttributeBlock.decode(wire)?.entries()?.first?.value, maximumValue)
        XCTAssertThrowsError(try AppleFileCopyAttributeBlock.encode(entries: [
            .init(name: Data([0x61]), value: maximumValue + Data([0]))]))
        for name in [Data(), Data([0]), Data([0x61, 0, 0x62])] {
            XCTAssertThrowsError(try AppleFileCopyAttributeBlock.encode(entries: [.init(name: name, value: Data())]))
        }
        XCTAssertThrowsError(try AppleFileCopyAttributeBlock.encode(entries:
            Array(repeating: .init(name: Data([0x61]), value: Data()), count: 8190)))
        XCTAssertEqual(try AppleFileCopyAttributeBlock.decode(
            AppleFileCopyAttributeBlock.encode(entries: []))?.entries(), [])
    }

    func testAttributeTableSeparatesTerminatedNamesFromBinaryValues() throws {
        // Two length records followed by key/value pairs; declared size 32.
        let payload = Data([0, 0, 0, 32, 0, 0, 0, 2,
                            0, 0, 0, 2, 0, 0, 0, 3,
                            0, 0, 0, 3, 0, 0, 0, 0,
                            0x61, 0, 0, 0xff, 0x80, 0x62, 0x63, 0])
        let block = AppleFileCopyAttributeBlock(flags: 0, version: 1,
                                              payload: payload, trailingBytes: Data())
        XCTAssertEqual(try block.entries(), [
            .init(name: Data([0x61]), value: Data([0, 0xff, 0x80])),
            .init(name: Data([0x62, 0x63]), value: Data())])
        for count in 0..<payload.count {
            let truncated = AppleFileCopyAttributeBlock(flags: 0, version: 1,
                                                       payload: payload.prefix(count), trailingBytes: Data())
            XCTAssertThrowsError(try truncated.entries())
        }
        for index in [8, 12, 16, 20] {
            var malformed = payload
            malformed[index] = 0xff
            XCTAssertThrowsError(try AppleFileCopyAttributeBlock(
                flags: 0, version: 1, payload: malformed, trailingBytes: Data()).entries())
        }
        var malformed = payload; malformed[25] = 1
        XCTAssertThrowsError(try AppleFileCopyAttributeBlock(
            flags: 0, version: 1, payload: malformed, trailingBytes: Data()).entries())
        XCTAssertNil(try AppleFileCopyAttributeBlock(
            flags: 1, version: 1, payload: payload, trailingBytes: Data()).entries())
        XCTAssertNil(try AppleFileCopyAttributeBlock(
            flags: 0, version: 2, payload: payload, trailingBytes: Data()).entries())
    }
    func testNativeEnvelopeSeparatesOpaquePayloadAndTrailingBytes() throws {
        // ext1, flags 0x8001, version 1, total block length 14.
        let wire = Data([0x65, 0x78, 0x74, 0x31, 0x80, 1, 0, 1, 0, 14,
                         0, 0xff, 0, 4, 0xab, 0xcd])
        let block = try XCTUnwrap(AppleFileCopyAttributeBlock.decode(wire))
        XCTAssertEqual(block.flags, 0x8001)
        XCTAssertEqual(block.version, 1)
        XCTAssertEqual(block.payload, Data([0, 0xff, 0, 4]))
        XCTAssertEqual(block.trailingBytes, Data([0xab, 0xcd]))
        let prefixed = Data([0xee]) + wire
        XCTAssertEqual(try AppleFileCopyAttributeBlock.decode(prefixed.dropFirst()), block)
    }

    func testKnownMagicWithTruncatedOrImpossibleLengthsIsRejected() throws {
        let header = Data([0x65, 0x78, 0x74, 0x31, 0, 0, 0, 1, 0, 10])
        for count in 4..<10 {
            XCTAssertThrowsError(try AppleFileCopyAttributeBlock.decode(header.prefix(count)))
        }
        for length: UInt16 in [0, 9, 11, UInt16.max] {
            var malformed = header
            malformed[8] = UInt8(length >> 8)
            malformed[9] = UInt8(length & 255)
            XCTAssertThrowsError(try AppleFileCopyAttributeBlock.decode(malformed))
        }
        XCTAssertEqual(try AppleFileCopyAttributeBlock.decode(header)?.payload, Data())
    }

    func testUnknownMetadataAndVersionsArePreservedWithoutInterpretation() throws {
        XCTAssertNil(try AppleFileCopyAttributeBlock.decode(Data()))
        XCTAssertNil(try AppleFileCopyAttributeBlock.decode(Data([0xaa, 0, 0xff, 0])))
        let block = try XCTUnwrap(AppleFileCopyAttributeBlock.decode(
            Data([0x65, 0x78, 0x74, 0x31, 0xff, 0xff, 0xff, 0xff, 0, 10])))
        XCTAssertEqual(block.flags, UInt16.max)
        XCTAssertEqual(block.version, UInt16.max)
    }
}
