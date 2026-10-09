import XCTest
import Darwin
@testable import AetherScreensCore

final class ComputerSyncCheckpointTests: XCTestCase {
    func testStaleCommitCannotOverwriteNewerRuntimeStateEvenWithSameJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ComputerSyncCheckpointFile(url: directory.appendingPathComponent("checkpoint.json"))
        var device = RemoteDevice(name: "Local", host: "local.invalid")
        var journal = ComputerSyncJournal()
        try journal.captureLocalComputers([device])
        let first = try ComputerSyncCheckpoint(journal: journal, devices: [device], credentialBindings: [:])
        try file.save(first, replacing: nil)
        let base = try XCTUnwrap(file.load())
        device.lastConnected = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = try ComputerSyncCheckpoint(journal: journal, devices: [device], credentialBindings: [:])
        try file.save(newer, replacing: base)
        let bytes = try Data(contentsOf: file.url)
        XCTAssertThrowsError(try file.save(first, replacing: base)) { error in
            guard case ComputerSyncCheckpointFile.Failure.conflict = error else { return XCTFail("Expected stale commit conflict") }
        }
        XCTAssertEqual(try Data(contentsOf: file.url), bytes)
        XCTAssertEqual(try file.load(), newer)
    }

    func testContendingWriterFailsPromptlyWithoutReplacingCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ComputerSyncCheckpointFile(url: directory.appendingPathComponent("checkpoint.json"))
        let checkpoint = try ComputerSyncCheckpoint(journal: ComputerSyncJournal(), devices: [], credentialBindings: [:])
        try file.save(checkpoint)
        let original = try Data(contentsOf: file.url)
        let lock = Darwin.open(file.lockURL.path, O_RDWR | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(lock, 0)
        guard lock >= 0 else { return }
        defer { Darwin.close(lock) }
        XCTAssertEqual(checkpointFlock(lock, LOCK_EX | LOCK_NB), 0)
        defer { _ = checkpointFlock(lock, LOCK_UN) }
        XCTAssertThrowsError(try file.save(checkpoint)) { error in
            guard case ComputerSyncCheckpointFile.Failure.busy = error else {
                return XCTFail("Expected writer contention")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file.url), original)
        XCTAssertEqual(checkpointFlock(lock, LOCK_UN), 0)
        XCTAssertNoThrow(try file.save(checkpoint))
        XCTAssertEqual(try file.load(), checkpoint)
    }

    func testAccountMismatchCannotReadOrOverwriteExistingCheckpoint() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scopeA = try ComputerSyncAccountScope(accountIdentifier: "generated-account-A")
        let scopeB = try ComputerSyncAccountScope(accountIdentifier: "generated-account-B")
        XCTAssertEqual(scopeA, try ComputerSyncAccountScope(accountIdentifier: "generated-account-A"))
        XCTAssertNotEqual(scopeA, scopeB)
        let url = directory.appendingPathComponent("checkpoint.json")
        let checkpoint = try ComputerSyncCheckpoint(journal: ComputerSyncJournal(), devices: [], credentialBindings: [:])
        let first = ComputerSyncCheckpointFile(url: url, accountScope: scopeA)
        try first.save(checkpoint)
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("generated-account-A"))
        XCTAssertEqual(try first.load()?.accountScopeDigest, scopeA.digest)
        let wrong = ComputerSyncCheckpointFile(url: url, accountScope: scopeB)
        XCTAssertThrowsError(try wrong.load())
        XCTAssertThrowsError(try wrong.save(checkpoint))
        XCTAssertThrowsError(try ComputerSyncCheckpointFile(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testCredentialBindingWhitelistRejectsUnknownSecretFields() throws {
        let device = RemoteDevice(name: "Local", host: "local.invalid")
        var journal = ComputerSyncJournal()
        try journal.captureLocalComputers([device])
        let key = "vnc:\(device.id.uuidString)"
        let target = ComputerCredentialTarget(host: device.host, port: device.port,
            authMethod: device.authMethod, username: device.username, ssh: device.ssh)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(target)
        XCTAssertNoThrow(try ComputerSyncCheckpoint(journal: journal, devices: [device],
            credentialBindings: [key: data.base64EncodedString()]))
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["password"] = "generated-test-value"
        let secret = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        XCTAssertThrowsError(try ComputerSyncCheckpoint(journal: journal, devices: [device],
            credentialBindings: [key: secret.base64EncodedString()]))
        XCTAssertThrowsError(try ComputerSyncCheckpoint(journal: journal, devices: [device],
            credentialBindings: [key: "unparseable"]))
    }

    func testFailedReplacementLeavesExistingDirectoryAndNoTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("checkpoint.json")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let marker = target.appendingPathComponent("keep")
        try Data([42]).write(to: marker)
        let checkpoint = try ComputerSyncCheckpoint(journal: ComputerSyncJournal(), devices: [], credentialBindings: [:])
        XCTAssertThrowsError(try ComputerSyncCheckpointFile(url: target).save(checkpoint))
        XCTAssertEqual(try Data(contentsOf: marker), Data([42]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".sync-lock-") }, ["checkpoint.json"])
    }

    func testWholeCheckpointSurvivesReplacementAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ComputerSyncCheckpointFile(url: directory.appendingPathComponent("checkpoint.json"))
        XCTAssertNil(try file.load())
        var journal = ComputerSyncJournal()
        var device = RemoteDevice(name: "Local", host: "local.invalid")
        try journal.captureLocalComputers([device])
        let first = try ComputerSyncCheckpoint(journal: journal, devices: [device], credentialBindings: [:])
        try file.save(first)
        device.host = "replacement.invalid"
        try journal.captureLocalComputers([device])
        let second = try ComputerSyncCheckpoint(journal: journal, devices: [device],
            credentialBindings: ["ssh:\(device.id.uuidString)": "unbound"])
        try file.save(second)
        XCTAssertEqual(try ComputerSyncCheckpointFile(url: file.url).load(), second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".sync-lock-") }, ["checkpoint.json"])
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertThrowsError(try ComputerSyncCheckpoint(journal: journal, devices: first.devices, credentialBindings: [:]))
        XCTAssertEqual(try file.load(), second)
    }

    func testCorruptCheckpointIsReportedAndNeverReplacedOnRead() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = ComputerSyncCheckpointFile(url: directory.appendingPathComponent("checkpoint.json"))
        let corrupt = Data([1, 2, 3])
        try corrupt.write(to: file.url)
        XCTAssertThrowsError(try file.load())
        XCTAssertEqual(try Data(contentsOf: file.url), corrupt)
    }
}
