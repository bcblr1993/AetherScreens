import XCTest
@testable import AetherScreensCore

final class AppleRFBRecordLayerTests: XCTestCase {
    // Public synthetic fixtures generated independently with OpenSSL AES + Python SHA-1.
    private let rekey = "00000001db7ce67af13de57a95d922e5325abf13771098a6b78cb45c029cf1c0ddee0f1b"
    private let records = [
        "0020c2c84a51efbfeb9a84e3b9e83dd11c2686fb5d7dca66028cf06c37df39959249",
        "00308707948a4806564c70fcab26775730b388fe93a33eae5f992f88c7dedaff7b4a97bb0fb75c1ce32476076a3fcaf0b406",
        "00200d3c0b8208180d9de7b05db71eba1d784f490992a1ad3423937c0aff1a03025e"
    ]
    private let bodies = [Data("hello".utf8), Data("next record".utf8), Data()]

    private func hex(_ string: String) -> Data {
        let chars = Array(string)
        return Data(stride(from: 0, to: chars.count, by: 2).map {
            UInt8(String(chars[$0...($0 + 1)]), radix: 16)!
        })
    }
    private func layer() throws -> AppleRFBRecordLayer {
        let layer = try AppleRFBRecordLayer(wrapKey: Data(32..<48))
        XCTAssertEqual(try layer.installRekey(hex(rekey)), 1)
        return layer
    }

    func testStreamReassemblesEveryFragmentBoundaryAndCoalescedRecords() throws {
        let wire = records.reduce(Data()) { $0 + hex($1) }
        for boundary in 0...wire.count {
            let stream = AppleRFBRecordStream(codec: try layer())
            var received: [Data] = []
            try stream.append(Data(wire.prefix(boundary))) { received.append($0) }
            XCTAssertLessThanOrEqual(stream.bufferedByteCount, 65_522)
            try stream.append(Data(wire.dropFirst(boundary))) { received.append($0) }
            XCTAssertEqual(received, bodies)
            XCTAssertEqual(stream.bufferedByteCount, 0)
            try stream.finish()
        }
    }

    func testStreamStopsWhenDeliveryDisconnectsSession() throws {
        let stream = AppleRFBRecordStream(codec: try layer())
        var count = 0
        XCTAssertThrowsError(try stream.append(records.reduce(Data()) { $0 + hex($1) }) { _ in
            count += 1
            stream.close()
        }) { XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed) }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(stream.bufferedByteCount, 0)
    }

    func testStreamRejectsCorruptionAndTruncationWithoutDeliveringBadBody() throws {
        for length in [0, 16, 33, 65_535] {
            let stream = AppleRFBRecordStream(codec: try layer())
            XCTAssertThrowsError(try stream.append(Data([UInt8(length >> 8), UInt8(length & 255)])) { _ in XCTFail("Invalid header delivered") })
            XCTAssertEqual(stream.bufferedByteCount, 0)
        }
        let wire = hex(records[0])
        for count in 1..<wire.count {
            let stream = AppleRFBRecordStream(codec: try layer())
            try stream.append(Data(wire.prefix(count))) { _ in XCTFail("Truncated record delivered") }
            XCTAssertThrowsError(try stream.finish())
        }
        let stream = AppleRFBRecordStream(codec: try layer())
        var corrupt = hex(records[1]); corrupt[corrupt.count - 1] ^= 1
        var received: [Data] = []
        XCTAssertThrowsError(try stream.append(wire + corrupt + hex(records[2])) { received.append($0) })
        XCTAssertEqual(received, [bodies[0]])
        XCTAssertThrowsError(try stream.append(wire) { _ in XCTFail("Closed stream delivered") })
    }

    func testDesktopSizedRecordStreamKeepsIntegrityAcrossManyFragments() throws {
        let sender = try layer()
        let receiver = AppleRFBRecordStream(codec: try layer())
        let body = Data((0..<32_768).map { UInt8(truncatingIfNeeded: $0) })
        let packets = try (0..<128).map { _ in try sender.seal(body) }
        var delivered = 0
        let start = ProcessInfo.processInfo.systemUptime
        for packet in packets {
            try receiver.append(packet) { decoded in
                XCTAssertEqual(decoded, body)
                delivered += 1
            }
            XCTAssertEqual(receiver.bufferedByteCount, 0)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("Synthetic encrypted receive: 4194304 bytes in \(elapsed) seconds, excludes socket and rendering")
        XCTAssertEqual(delivered, 128)
        try receiver.finish()
    }

    func testDesktopReceiveWithSplitHeadersAndCoalescedRecords() throws {
        let sender = try layer()
        let body = Data((0..<32_768).map { UInt8(truncatingIfNeeded: $0 * 37) })
        var wire = Data()
        for _ in 0..<128 { wire.append(try sender.seal(body)) }
        let receiver = AppleRFBRecordStream(codec: try layer())
        var offset = 0, fragment = 0, delivered = 0
        let sizes = [1, 2, 113, 8192, 65536]
        let start = ProcessInfo.processInfo.systemUptime
        while offset < wire.count {
            let end = min(wire.count, offset + sizes[fragment % sizes.count])
            try receiver.append(wire.subdata(in: offset..<end)) { decoded in
                XCTAssertEqual(decoded, body)
                delivered += 1
            }
            XCTAssertLessThanOrEqual(receiver.bufferedByteCount, 65_522)
            offset = end
            fragment += 1
        }
        try receiver.finish()
        XCTAssertEqual(delivered, 128)
        XCTAssertEqual(receiver.bufferedByteCount, 0)
        print("Synthetic fragmented encrypted receive: 4194304 bytes, \(fragment) fragments in \(ProcessInfo.processInfo.systemUptime - start) seconds; excludes socket and presentation")
    }

    func testOpenSSLVectorsAndIndependentDirectionalStreams() throws {
        let codec = try layer()
        for index in records.indices {
            XCTAssertEqual(try codec.seal(bodies[index]), hex(records[index]))
            XCTAssertEqual(try codec.open(hex(records[index])), bodies[index])
        }
        XCTAssertEqual(codec.sendSequence, 3)
        XCTAssertEqual(codec.receiveSequence, 3)
    }

    func testSecondRekeyRotatesWrapKeyWithoutResettingSequence() throws {
        let codec = try layer()
        for index in records.indices {
            _ = try codec.seal(bodies[index])
            _ = try codec.open(hex(records[index]))
        }
        let next = hex("0000000903f2c3bdca826bf082d7cfb035cdb8c1d533e59b45a153ed7e5e9c5dfcfd4aaa")
        XCTAssertEqual(try codec.installRekey(next), 9)
        let packet = hex("0020e9ba41112accf9a224f07e481e7b5e8ef14300b5d91a19f4756a0d8d6b5698b7")
        XCTAssertEqual(try codec.seal(Data("again".utf8)), packet)
        XCTAssertEqual(try codec.open(packet), Data("again".utf8))
        XCTAssertEqual(codec.sendSequence, 4)
        XCTAssertEqual(codec.receiveSequence, 4)
    }

    func testTamperAndReplayCloseWithoutDeliveringFurtherRecords() throws {
        let replay = try layer()
        _ = try replay.open(hex(records[0]))
        XCTAssertThrowsError(try replay.open(hex(records[0])))
        XCTAssertThrowsError(try replay.open(hex(records[1]))) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed)
        }
        let corrupt = try layer()
        var packet = hex(records[0])
        packet[packet.count - 1] ^= 1
        XCTAssertThrowsError(try corrupt.open(packet))
        XCTAssertThrowsError(try corrupt.seal(Data())) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed)
        }
    }

    func testMalformedOuterLengthsAndTrailingBytesCloseCodec() throws {
        for packet in [Data(), Data([0, 0]), Data([0, 16]) + Data(repeating: 0, count: 16),
                       hex(records[0]).dropLast(), hex(records[0]) + Data([0])] {
            let codec = try layer()
            XCTAssertThrowsError(try codec.open(Data(packet)))
            XCTAssertThrowsError(try codec.installRekey(hex(rekey))) {
                XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed)
            }
        }
    }

    func testNonzeroFillerIsAcceptedWithoutExposingIt() throws {
        let packet = hex("00209cfeb01d8f9c7c44b8f9e324f5ca206eaed167fd8c8629514f19cf441ad23eb3")
        XCTAssertEqual(try layer().open(packet), Data("hello".utf8))
    }

    func testValidIntegrityDoesNotPermitInvalidInnerBounds() throws {
        for packet in [
            "0020dee382234fbc7a218a2857da6a94fb9951465d25699ff15f0edf20e969c497b7",
            "003007feef74e1d5036e900eee118e94929373df10edd391e598dfa187865862eb1a916ab9b82b73a0729d49eb2f09b543a3"
        ] {
            let codec = try layer()
            XCTAssertThrowsError(try codec.open(hex(packet))) {
                XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .invalidRecord)
            }
            XCTAssertEqual(codec.receiveSequence, 0)
            XCTAssertThrowsError(try codec.open(hex(records[0]))) {
                XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed)
            }
        }
    }

    func testBodyLimitRejectsWithoutConsumingSendSequence() throws {
        let codec = try layer()
        XCTAssertThrowsError(try codec.seal(Data(repeating: 1, count: AppleRFBRecordLayer.maximumBodySize + 1))) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .bodyTooLarge)
        }
        XCTAssertEqual(codec.sendSequence, 0)
        let body = Data(repeating: 42, count: AppleRFBRecordLayer.maximumBodySize)
        let packet = try codec.seal(body)
        XCTAssertEqual(packet.count, 65_522)
        XCTAssertEqual(try codec.open(packet), body)
    }

    func testInitializationAndRekeyBounds() throws {
        XCTAssertThrowsError(try AppleRFBRecordLayer(wrapKey: Data(repeating: 0, count: 15)))
        let codec = try AppleRFBRecordLayer(wrapKey: Data(32..<48))
        XCTAssertThrowsError(try codec.seal(Data())) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .rekeyRequired)
        }
        XCTAssertThrowsError(try codec.open(hex(records[0]))) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .rekeyRequired)
        }
        XCTAssertThrowsError(try codec.installRekey(hex(rekey).dropLast()))
        XCTAssertThrowsError(try codec.installRekey(hex(rekey))) {
            XCTAssertEqual($0 as? AppleRFBRecordLayer.Failure, .closed)
        }
    }
}
