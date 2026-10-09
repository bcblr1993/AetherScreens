import XCTest
import CryptoKit
@testable import AetherScreensCore

final class EncryptedPKCS8PrivateKeyTests: XCTestCase {
    func testOpenSSLInteroperabilityAcrossCurvesCiphersAndPRFs() throws {
        try withFixture { directory, openssl, passphraseFile in
            let curves = [P256.Signing.PrivateKey().pemRepresentation,
                          P384.Signing.PrivateKey().pemRepresentation,
                          P521.Signing.PrivateKey().pemRepresentation]
            let source = directory.appendingPathComponent("source.pem")
            let encrypted = directory.appendingPathComponent("encrypted.pem")
            for pem in curves {
                try Data(pem.utf8).write(to: source)
                let expected = try SSHPrivateKey.decode(Data(pem.utf8))
                for cipher in ["aes-128-cbc", "aes-192-cbc", "aes-256-cbc"] {
                    for prf in ["hmacWithSHA1", "hmacWithSHA256", "hmacWithSHA384", "hmacWithSHA512"] {
                        try run(openssl, ["pkcs8", "-topk8", "-in", source.path, "-out", encrypted.path,
                            "-v2", cipher, "-v2prf", prf, "-iter", "1000", "-passout", "file:" + passphraseFile.path])
                        let normalized = try EncryptedPKCS8PrivateKey.decrypt(Data(contentsOf: encrypted), passphrase: phrase)
                        XCTAssertTrue(try SSHPrivateKey.decode(normalized).publicKey == expected.publicKey)
                        XCTAssertThrowsError(try EncryptedPKCS8PrivateKey.decrypt(Data(contentsOf: encrypted), passphrase: "wrong QA phrase")) {
                            XCTAssertEqual($0 as? EncryptedPKCS8PrivateKey.Failure, .decryptionFailed)
                        }
                    }
                }
            }
        }
    }

    func testRejectsTruncationTrailingDataAndUnboundedIterations() throws {
        try withFixture { directory, openssl, passphraseFile in
            let source = directory.appendingPathComponent("source.pem")
            let encrypted = directory.appendingPathComponent("encrypted.pem")
            try Data(P256.Signing.PrivateKey().pemRepresentation.utf8).write(to: source)
            try run(openssl, ["pkcs8", "-topk8", "-in", source.path, "-out", encrypted.path,
                "-v2", "aes-256-cbc", "-iter", "1000", "-passout", "file:" + passphraseFile.path])
            let pem = try String(contentsOf: encrypted, encoding: .utf8)
            let lines = pem.split(whereSeparator: \.isNewline)
            let der = try XCTUnwrap(Data(base64Encoded: lines.dropFirst().dropLast().joined()))
            func wrapped(_ bytes: Data) -> Data {
                Data(("-----BEGIN ENCRYPTED PRIVATE KEY-----\n" + bytes.base64EncodedString() + "\n-----END ENCRYPTED PRIVATE KEY-----\n").utf8)
            }
            for length in stride(from: 0, to: der.count, by: 7) {
                XCTAssertThrowsError(try EncryptedPKCS8PrivateKey.decrypt(wrapped(der.prefix(length)), passphrase: phrase))
            }
            XCTAssertThrowsError(try EncryptedPKCS8PrivateKey.decrypt(wrapped(der + Data([0])), passphrase: phrase))
            // The independent OpenSSL encoder creates an over-budget KDF profile.
            try run(openssl, ["pkcs8", "-topk8", "-in", source.path, "-out", encrypted.path,
                "-v2", "aes-256-cbc", "-iter", "2000001", "-passout", "file:" + passphraseFile.path])
            XCTAssertThrowsError(try EncryptedPKCS8PrivateKey.decrypt(Data(contentsOf: encrypted), passphrase: phrase)) {
                XCTAssertEqual($0 as? EncryptedPKCS8PrivateKey.Failure, .tooExpensive)
            }
            XCTAssertThrowsError(try EncryptedPKCS8PrivateKey.decrypt(Data(repeating: 0, count: 65537), passphrase: phrase)) {
                XCTAssertEqual($0 as? SSHPrivateKey.Failure, .tooLarge)
            }
        }
    }

    private let phrase = "QA-only 加密口令 with spaces"
    private func withFixture(_ body: (URL, URL, URL) throws -> Void) throws {
        #if os(macOS)
        let openssl = URL(fileURLWithPath: "/opt/homebrew/opt/openssl@3/bin/openssl")
        guard FileManager.default.isExecutableFile(atPath: openssl.path) else { throw XCTSkip("OpenSSL 3 interoperability oracle unavailable") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-pkcs8-qa-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let passphraseFile = directory.appendingPathComponent("qa-phrase")
        try Data((phrase + "\n").utf8).write(to: passphraseFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passphraseFile.path)
        try body(directory, openssl, passphraseFile)
        #else
        throw XCTSkip("External OpenSSL interoperability oracle requires macOS")
        #endif
    }
    private func run(_ executable: URL, _ arguments: [String]) throws {
        #if os(macOS)
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "OwnedOpenSSLFixture", code: Int(process.terminationStatus)) }
        #endif
    }
}
