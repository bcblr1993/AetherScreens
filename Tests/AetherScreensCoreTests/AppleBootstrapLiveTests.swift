import XCTest
import Darwin
@testable import AetherScreensCore

/// Opt-in, short-lived vendor-bootstrap probe. No desktop or clipboard data is saved.
final class AppleBootstrapLiveTests: XCTestCase {
    func testActualAppleRekeyAndFirstControlRecord() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_APPLE_BOOTSTRAP"] == "1",
              let host = env["AETHERSCREENS_LIVE_HOST"],
              let account = env["AETHERSCREENS_LIVE_USERNAME"] else {
            throw XCTSkip("Requires explicit actual Apple bootstrap QA opt-in")
        }
        let defaults = UserDefaults(suiteName: "com.aethernative.aetherscreens")
        let devices = defaults?.data(forKey: DeviceStore.storageKey)
            .flatMap { try? JSONDecoder().decode([RemoteDevice].self, from: $0) } ?? []
        let saved = DeviceStore.shared.devices.first { $0.host == host }
            ?? devices.first { $0.host == host }
        guard let password = env["AETHERSCREENS_LIVE_PASSWORD"] ?? saved.flatMap({ DeviceStore.shared.getPassword(for: $0) }),
              !password.isEmpty else { throw XCTSkip("Requires same-target Keychain credential") }
        let peer = try BootstrapSocket(host: host, port: 5900, timeout: 45)
        defer { peer.close() }
        let standardClipboard = env["AETHERSCREENS_QA_APPLE_STANDARD_CLIPBOARD_FETCH"] == "1"
        guard try peer.read(12) == Data("RFB 003.889\n".utf8) else { throw ProbeFailure.versionRejected }
        try peer.write(Data((standardClipboard ? "RFB 003.008\n" : "RFB 003.889\n").utf8))
        let count = Int(try peer.read(1).first!)
        guard count > 0 else { throw ProbeFailure.versionRejected }
        let usesVNC = env["AETHERSCREENS_LIVE_AUTH"] == "vnc"
        guard !usesVNC || standardClipboard else { throw ProbeFailure.authUnavailable }
        let authType: UInt8 = usesVNC ? 2 : 30
        guard try peer.read(count).contains(authType) else { throw ProbeFailure.authUnavailable }
        try peer.write(Data([authType]))
        var wrapKey: Data?
        if usesVNC {
            try peer.write(VNCAuthCrypto.encryptChallenge(peer.read(16), password: password))
        } else {
            let challenge = Array(try peer.read(4))
            let generator = UInt16(challenge[0]) << 8 | UInt16(challenge[1])
            let length = Int(challenge[2]) << 8 | Int(challenge[3])
            guard (16...512).contains(length) else { throw ProbeFailure.bounds }
            let values = try peer.read(length * 2)
            let exchange = try ARDAuthCrypto.exchange(generator: generator,
                prime: Data(values.prefix(length)), peer: Data(values.suffix(length)),
                username: account, password: password)
            wrapKey = exchange.wrapKey
            try peer.write(exchange.response)
        }
        guard try peer.read(4) == Data([0, 0, 0, 0]) else { throw ProbeFailure.authRejected }
        print("Apple bootstrap: type-\(authType) authentication accepted, standard profile \(standardClipboard)")
        try peer.write(Data([standardClipboard ? 1 : 0xc1]))
        let initial = Array(try peer.read(24))
        let nameLength = initial.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard nameLength <= 65_536 else { throw ProbeFailure.bounds }
        _ = try peer.read(Int(nameLength)) // discard name, never log it
        print("Apple bootstrap: ServerInit received")
        if standardClipboard {
            if env["AETHERSCREENS_QA_APPLE_STANDARD_VIEWER_INFO"] == "1" {
                try peer.write(viewerInfo())
                print("Apple bootstrap: standard-profile ViewerInfo sent")
            }
            try peer.write(AppleClipboardControl.monitoring(true))
            defer { try? peer.write(AppleClipboardControl.monitoring(false)) }
            try peer.write(AppleClipboardControl.request())
            for _ in 0..<20 {
                let type = try peer.read(1).first!
                if type == 0x1f {
                    let header = Data([type]) + (try peer.read(15))
                    let size = header.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    guard size <= AppleClipboardArchive.maximumBytes else { throw ProbeFailure.bounds }
                    var packet = header
                    var remaining = Int(size)
                    while remaining > 0 {
                        let count = min(remaining, 65_536)
                        packet.append(try peer.read(count)); remaining -= count
                    }
                    let content = try AppleClipboardArchive.decode(message: packet)
                    if case .promise = content { throw ProbeFailure.unexpectedReply }
                    print("Apple clipboard probe: standard-profile archive decoded, packet bytes \(packet.count)")
                    return
                }
                guard type == 0x14 else { throw ProbeFailure.unexpectedReply }
                _ = try peer.read(7)
            }
            throw ProbeFailure.unexpectedReply
        }
        try peer.write(viewerInfo())
        try peer.write(AppleEncryptionControl.requestReceiveEncryption)
        let update = try peer.read(4)
        guard update == Data([0, 0, 0, 1]) else { throw ProbeFailure.unexpectedReply }
        let rectangle = try peer.read(12)
        guard AppleEncryptionControl.isInitialRekey(updateHeader: update, rectangleHeader: rectangle) else {
            throw ProbeFailure.unexpectedReply
        }
        guard let wrapKey else { throw ProbeFailure.authUnavailable }
        let codec = try AppleRFBRecordLayer(wrapKey: wrapKey)
        defer { codec.close() }
        let generation = try codec.installRekey(peer.read(36))
        let stream = AppleRFBRecordStream(codec: codec)
        print("Apple bootstrap: rekey received, generation \(generation)")
        let fetchClipboard = env["AETHERSCREENS_QA_APPLE_CLIPBOARD_FETCH"] == "1"
        // Complete the outgoing encryption transition for every native probe.
        // Receiving encrypted records does not itself switch client writes.
        try peer.write(AppleEncryptionControl.observe)
        try peer.write(AppleEncryptionControl.enableSendEncryption)
        print("Apple bootstrap: cleartext Observe and encryption transition sent")
        let outer = Array(try peer.read(2))
        let encryptedLength = Int(outer[0]) << 8 | Int(outer[1])
        guard encryptedLength >= 32, encryptedLength % 16 == 0 else { throw ProbeFailure.bounds }
        let body = try receiveRecord(stream: stream, header: Data(outer), payload: peer.read(encryptedLength))
        print("Apple bootstrap: first record verified, type \(body.first.map(Int.init) ?? -1), length \(body.count)")
        XCTAssertEqual(codec.receiveSequence, 1)
        if fetchClipboard {
            try peer.write(codec.seal(AppleClipboardControl.monitoring(true)))
            defer { try? peer.write(codec.seal(AppleClipboardControl.monitoring(false))) }
            try peer.write(codec.seal(AppleClipboardControl.request()))
            let assembler = AppleClipboardAssembler()
            var assembling = false
            for _ in 0..<20 {
                let header = Array(try peer.read(2))
                let size = Int(header[0]) << 8 | Int(header[1])
                guard size >= 32, size % 16 == 0 else { throw ProbeFailure.bounds }
                let message = try receiveRecord(stream: stream, header: Data(header), payload: peer.read(size))
                print("Apple clipboard probe: verified record type \(message.first.map(Int.init) ?? -1), length \(message.count)")
                if assembling || message.first == 0x1f {
                    assembling = true
                    if let content = try assembler.append(message) {
                        switch content {
                        case .empty: print("Apple clipboard probe: archive decoded, empty")
                        case .text(let text): print("Apple clipboard probe: archive decoded, text bytes \(text.utf8.count)")
                        case .unsupported: print("Apple clipboard probe: archive decoded, unsupported flavor")
                        case .promise: throw ProbeFailure.unexpectedReply
                        }
                        return
                    }
                } else if message.first != 0x14 {
                    throw ProbeFailure.unexpectedReply
                }
            }
            throw ProbeFailure.unexpectedReply
        }
        // Change only this probe's session to Observe; no remote input is sent.
        try peer.write(codec.seal(AppleEncryptionControl.observe))
        print("Apple bootstrap: encrypted Observe command sent")
        for index in 0..<3 {
            let header = Array(try peer.read(2))
            let count = Int(header[0]) << 8 | Int(header[1])
            guard count >= 32, count % 16 == 0 else { throw ProbeFailure.bounds }
            let message = Array(try receiveRecord(stream: stream, header: Data(header), payload: peer.read(count)))
            guard message.count == 8, message[0] == 0x14,
                  message[2] == 0, message[3] == 4 else { throw ProbeFailure.unexpectedReply }
            let command = Int(message[6]) << 8 | Int(message[7])
            print("Apple bootstrap: verified status command \(command), receive sequence \(codec.receiveSequence)")
            guard command == 4 || command == 12 else { throw ProbeFailure.unexpectedReply }
            if index == 2 {
                print("Apple bootstrap: verified continuous status records after encrypted send, receive sequence \(codec.receiveSequence)")
                XCTAssertEqual(codec.sendSequence, 1)
                return
            }
        }
        throw ProbeFailure.unexpectedReply
    }
    private func receiveRecord(stream: AppleRFBRecordStream, header: Data, payload: Data) throws -> Data {
        var bodies: [Data] = []
        // Feed the header separately to exercise the actual framing boundary.
        try stream.append(header) { bodies.append($0) }
        try stream.append(payload) { bodies.append($0) }
        guard bodies.count == 1 else { throw ProbeFailure.unexpectedReply }
        return bodies[0]
    }
    private func viewerInfo() -> Data { AppleViewerInfo.encode() }
}

private enum ProbeFailure: Error { case bounds, network(Int32), timedOut, closed, versionRejected, authUnavailable, authRejected, unexpectedReply }

private final class BootstrapSocket {
    private var descriptor: Int32 = -1
    private let deadline: TimeInterval
    init(host: String, port: UInt16, timeout: TimeInterval) throws {
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { throw ProbeFailure.bounds }
        descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ProbeFailure.network(errno) }
        do {
            guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else { throw ProbeFailure.network(errno) }
            var yes: Int32 = 1
            guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else { throw ProbeFailure.network(errno) }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if result != 0 {
                guard errno == EINPROGRESS else { throw ProbeFailure.network(errno) }
                try wait(Int16(POLLOUT))
                var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw ProbeFailure.network(error) }
            }
        } catch { close(); throw error }
    }
    deinit { close() }
    func close() { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } }
    private func wait(_ event: Int16) throws {
        guard descriptor >= 0 else { throw ProbeFailure.closed }
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ProbeFailure.timedOut }
            var fd = pollfd(fd: descriptor, events: event, revents: 0)
            let result = poll(&fd, 1, Int32(min(remaining * 1000, Double(Int32.max)).rounded(.up)))
            if result > 0 { return }
            if result == 0 { throw ProbeFailure.timedOut }
            if errno != EINTR { throw ProbeFailure.network(errno) }
        }
    }
    func read(_ count: Int) throws -> Data {
        guard (0...65_536).contains(count) else { throw ProbeFailure.bounds }
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            try wait(Int16(POLLIN))
            let received = bytes.withUnsafeMutableBytes { Darwin.recv(descriptor, $0.baseAddress!.advanced(by: offset), count - offset, 0) }
            if received > 0 { offset += received }
            else if received == 0 { throw ProbeFailure.closed }
            else if errno != EAGAIN && errno != EINTR { throw ProbeFailure.network(errno) }
        }
        return Data(bytes)
    }
    func write(_ data: Data) throws {
        guard data.count <= 65_536 else { throw ProbeFailure.bounds }
        var offset = 0
        while offset < data.count {
            try wait(Int16(POLLOUT))
            let sent = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress!.advanced(by: offset), data.count - offset, 0) }
            if sent > 0 { offset += sent }
            else if sent == 0 { throw ProbeFailure.closed }
            else if errno != EAGAIN && errno != EINTR { throw ProbeFailure.network(errno) }
        }
    }
}

private extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}
