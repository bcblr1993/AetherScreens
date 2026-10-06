import Foundation
import Testing
@testable import AetherScreensCore

@Suite(.serialized)
struct InputDiagnosticsTests {
    @Test func developmentBundleEnablesBoundedEvidenceWithoutLaunchEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(InputDiagnostics.makeEnabled(environment: [:], caches: directory, bundleOptIn: false) == nil)
        #expect(InputDiagnostics.makeEnabled(environment: [:], caches: nil, bundleOptIn: true) == nil)
        let recorder = try #require(InputDiagnostics.makeEnabled(environment: [:], caches: directory, bundleOptIn: true))
        #expect(recorder.snapshot.records.map(\.stage) == [.collectorStarted])
        recorder.record(.returnProcessed, session: UUID(), down: true)
        await recorder.flush()
        let data = try Data(contentsOf: directory.appendingPathComponent("AetherScreensInputDiagnostics/input-v1.json"))
        let snapshot = try JSONDecoder().decode(InputDiagnostics.Snapshot.self, from: data)
        #expect(snapshot.records.last?.stage == .returnProcessed)
        #expect(snapshot.records.last?.down == true)
        #expect(data.count < 32_768)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schema", "records"])
        let records = try #require(object["records"] as? [[String: Any]])
        #expect(records.allSatisfy { Set($0.keys).isSubset(of: ["sequence", "uptime", "session", "stage", "flags", "down"]) })
    }
    @Test func collectionRequiresExplicitLaunchOptIn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(InputDiagnostics.makeEnabled(environment: [:], caches: directory) == nil)
        #expect(InputDiagnostics.makeEnabled(environment: ["AETHERSCREENS_INPUT_DIAGNOSTICS": "0"], caches: directory) == nil)
        #expect(InputDiagnostics.makeEnabled(environment: ["AETHERSCREENS_INPUT_DIAGNOSTICS": "1"], caches: nil) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let recorder = try #require(InputDiagnostics.makeEnabled(environment: ["AETHERSCREENS_INPUT_DIAGNOSTICS": "1"], caches: directory))
        #expect(recorder.snapshot.records.map(\.stage) == [.collectorStarted])
        recorder.record(.tapRecognized, session: UUID(), flags: [.foreground, .trackpad], buttons: 1)
        await recorder.flush()
        let file = directory.appendingPathComponent("AetherScreensInputDiagnostics/input-v1.json")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func retainedEvidenceIsBoundedAndConcurrentWritesKeepLatestEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.json")
        let recorder = InputDiagnostics(fileURL: file)
        let session = UUID()
        DispatchQueue.concurrentPerform(iterations: 1024) { _ in
            recorder.record(.pointerQueued, session: session, buttons: 255)
        }
        recorder.record(.returnProcessed, session: session, down: false)
        await recorder.flush()
        let bytes = try Data(contentsOf: file)
        let snapshot = try JSONDecoder().decode(InputDiagnostics.Snapshot.self, from: bytes)
        #expect(snapshot.schema == 1)
        #expect(snapshot.records.count == 128)
        #expect(snapshot.records.last?.stage == .returnProcessed)
        #expect(snapshot.records.last?.sequence == 1025)
        #expect(snapshot.records.map(\.sequence) == Array(898...1025).map(UInt64.init))
        #expect(snapshot.records.dropLast().allSatisfy { $0.buttons == 7 })
        #expect(bytes.count < 32_768)
    }

    @Test func storageFailureDoesNotThrowOrDiscardInMemoryEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("regular-file")
        try Data([1]).write(to: blocker)
        let recorder = InputDiagnostics(fileURL: blocker.appendingPathComponent("input.json"))
        recorder.record(.pointerProcessed, session: UUID(), buttons: 1)
        await recorder.flush()
        #expect(recorder.snapshot.records.count == 1)
        #expect(!FileManager.default.fileExists(atPath: blocker.appendingPathComponent("input.json").path))
        #expect(try Data(contentsOf: blocker) == Data([1]))
    }
}
