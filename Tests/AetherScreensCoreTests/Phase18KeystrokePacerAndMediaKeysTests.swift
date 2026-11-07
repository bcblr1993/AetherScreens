import XCTest
@testable import AetherScreensCore

final class Phase18KeystrokePacerAndMediaKeysTests: XCTestCase {

    func testChunkAndNormalizeSplitsLongTextAndNormalizesLineEndings() {
        let input = "line1\r\nline2\rline3\n0123456789ABCDEF"
        let chunks = KeystrokePacer.chunkAndNormalize(input, chunkSize: 8)
        XCTAssertEqual(chunks.joined(), "line1\nline2\nline3\n0123456789ABCDEF")
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 8 })
        XCTAssertEqual(chunks.count, 5)
    }

    func testKeystrokeSequenceMapsNewlineAndTabToSpecialKeySyms() {
        let seq = KeystrokePacer.keystrokeSequence(for: "A\tB\n", appendReturn: false)
        // 'A' requires Shift (4 events), '\t' is tab (2 events), 'B' requires Shift (4 events), '\n' is return (2 events)
        XCTAssertEqual(seq.count, 12)
        XCTAssertTrue(seq.contains(where: { $0.key == MacKeyMap.tab && $0.down }))
        XCTAssertTrue(seq.contains(where: { $0.key == MacKeyMap.return && $0.down }))
    }

    func testRemoteSystemKeysProvideDistinctKeySymsAndMacFallbacks() {
        let allKeys = MacKeyMap.RemoteSystemKey.allCases
        XCTAssertEqual(allKeys.count, 8)

        let xf86Syms = Set(allKeys.map(\.keySym))
        XCTAssertEqual(xf86Syms.count, 8)

        let brightnessUpMac = MacKeyMap.RemoteSystemKey.brightnessUp.keySequence(forMac: true)
        XCTAssertEqual(brightnessUpMac.count, 2)
        XCTAssertEqual(brightnessUpMac.first?.key, MacKeyMap.f15)
        XCTAssertEqual(brightnessUpMac.first?.down, true)
        XCTAssertEqual(brightnessUpMac.last?.down, false)

        let volumeUpStandard = MacKeyMap.RemoteSystemKey.volumeUp.keySequence(forMac: false)
        XCTAssertEqual(volumeUpStandard.count, 2)
        XCTAssertEqual(volumeUpStandard.first?.key, 0x1008FF13)
    }
}
