import XCTest
import CryptoKit
import NIOSSH
@testable import AetherScreensCore

final class SSHPrivateKeyTests: XCTestCase {
    func testPEMAllSupportedCurvesAndFingerprint() throws {
        let keys: [(String, NIOSSHPrivateKey)] = [
            { let k = P256.Signing.PrivateKey(); return (k.pemRepresentation, .init(p256Key: k)) }(),
            { let k = P384.Signing.PrivateKey(); return (k.pemRepresentation, .init(p384Key: k)) }(),
            { let k = P521.Signing.PrivateKey(); return (k.pemRepresentation, .init(p521Key: k)) }()
        ]
        for (pem, expected) in keys {
            let decoded = try SSHPrivateKey.decode(Data(pem.utf8))
            XCTAssertEqual(decoded.publicKey, expected.publicKey)
            XCTAssertEqual(try SSHPrivateKey.fingerprint(decoded), try SSHPrivateKey.fingerprint(expected))
        }
    }
    func testRejectsOversizedDamagedEncryptedAndUnsupportedFiles() throws {
        for (data, error) in [(Data(repeating: 0, count: 65537), SSHPrivateKey.Failure.tooLarge),
            (Data("-----BEGIN ENCRYPTED PRIVATE KEY-----".utf8), .encrypted),
            (Data("-----BEGIN RSA PRIVATE KEY-----".utf8), .unsupported),
            (Data("not a private key".utf8), .invalid)] {
            XCTAssertThrowsError(try SSHPrivateKey.decode(data)) { XCTAssertEqual($0 as? SSHPrivateKey.Failure, error) }
        }
    }
    func testEncryptionDetectionRequiresAFormatHeader() throws {
        for text in ["ENCRYPTED", "This is not an ENCRYPTED private key", "-----BEGIN NOT ENCRYPTED PRIVATE KEY-----"] {
            XCTAssertThrowsError(try SSHPrivateKey.decode(Data(text.utf8))) {
                XCTAssertEqual($0 as? SSHPrivateKey.Failure, .invalid)
            }
        }
        for header in ["Proc-Type: 4,ENCRYPTED", "  Proc-Type:\t4,ENCRYPTED  "] {
            let text = "-----BEGIN EC PRIVATE KEY-----\n" + header + "\n-----END EC PRIVATE KEY-----\n"
            XCTAssertThrowsError(try SSHPrivateKey.decode(Data(text.utf8))) {
                XCTAssertEqual($0 as? SSHPrivateKey.Failure, .encrypted)
            }
        }
    }
    func testOpenSSHFilesAgainstSystemSSHKeygen() throws {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-key-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        func run(_ arguments: [String]) throws -> String {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = arguments
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            return String(data: data, encoding: .utf8) ?? ""
        }
        for (type, bits) in [("ed25519", "256"), ("ecdsa", "256"), ("ecdsa", "384"), ("ecdsa", "521")] {
            let file = directory.appendingPathComponent(type + bits)
            _ = try run(["-q", "-t", type, "-b", bits, "-N", "", "-C", "QA-only", "-f", file.path])
            let original = try Data(contentsOf: file)
            let key = try SSHPrivateKey.decode(original)
            let publicLine = try String(contentsOf: file.appendingPathExtension("pub"), encoding: .utf8)
            XCTAssertTrue(publicLine.hasPrefix(String(openSSHPublicKey: key.publicKey)))
            let fingerprint = try run(["-l", "-E", "sha256", "-f", file.path]).split(separator: " ")[1]
            XCTAssertEqual(try SSHPrivateKey.fingerprint(key), String(fingerprint))
            // Truncation and excessive length prefixes must be errors, not traps.
            for size in stride(from: 0, to: original.count, by: 11) {
                XCTAssertThrowsError(try SSHPrivateKey.decode(original.prefix(size)))
            }
            let lines = String(data: original, encoding: .utf8)!.split(whereSeparator: \.isNewline)
            let binary = Data(base64Encoded: lines.dropFirst().dropLast().joined())!
            for index in [15, 16, 17, 18] {
                var damaged = binary; damaged[index] ^= 0xFF
                let wrapped = "-----BEGIN OPENSSH PRIVATE KEY-----\n" + damaged.base64EncodedString() + "\n-----END OPENSSH PRIVATE KEY-----\n"
                XCTAssertThrowsError(try SSHPrivateKey.decode(Data(wrapped.utf8)))
            }
        }
        let encrypted = directory.appendingPathComponent("encrypted")
        _ = try run(["-q", "-t", "ed25519", "-N", "QA-only-passphrase", "-f", encrypted.path])
        XCTAssertThrowsError(try SSHPrivateKey.decode(Data(contentsOf: encrypted))) { XCTAssertEqual($0 as? SSHPrivateKey.Failure, .encrypted) }
        #else
        throw XCTSkip("External ssh-keygen oracle requires macOS")
        #endif
    }
}
