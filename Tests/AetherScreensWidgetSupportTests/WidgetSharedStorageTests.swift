import Foundation
import XCTest
@testable import AetherScreensWidgetSupport

final class WidgetSharedStorageTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!

    func testConfiguredGroupIdentifierUsesExactAllowlistWithoutFallback() {
        XCTAssertEqual(WidgetSharedStorage.configuredGroupIdentifier(WidgetSharedStorage.groupIdentifier), WidgetSharedStorage.groupIdentifier)
        XCTAssertEqual(WidgetSharedStorage.configuredGroupIdentifier(WidgetSharedStorage.qaGroupIdentifier), WidgetSharedStorage.qaGroupIdentifier)
        let invalid: [Any?] = [nil, 31, "", "com.aethernative.aetherscreens", "group.other", " group.com.aethernative.aetherscreens",
                               "group.com.aethernative.aetherscreens ", "group.com.aethernative.aetherscreens.extra",
                               "GROUP.com.aethernative.aetherscreens", "group.com.aethernative.aetherscreens\n"]
        for value in invalid { XCTAssertNil(WidgetSharedStorage.configuredGroupIdentifier(value)) }
        XCTAssertEqual(WidgetSharedStorage.kind, "com.aethernative.aetherscreens.quickconnect")
        XCTAssertFalse(WidgetSharedStorage.catalogFileName.contains("/"))
    }

    func testInjectedFileRoundTripsAndFreshReaderObservesReplacements() throws {
        try withOwnedFile { file in
            XCTAssertNil(WidgetSharedStorage.read(fileURL: file))
            try WidgetSharedStorage.write(catalog("QA One"), fileURL: file)
            let reader = WidgetCatalogReader(readData: { WidgetSharedStorage.read(fileURL: file) })
            XCTAssertEqual(reader.read().entries.first?.alias, "QA One")
            try WidgetSharedStorage.write(catalog("QA Two"), fileURL: file)
            XCTAssertEqual(reader.read().entries.first?.alias, "QA Two")
            try WidgetSharedStorage.write(try XCTUnwrap(WidgetCatalog().validatedData()), fileURL: file)
            XCTAssertTrue(reader.read().entries.isEmpty)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path), [file.lastPathComponent])
        }
    }

    func testBoundedReadReturnsAtMostLimitPlusOneAndOversizedFileCannotBeClobbered() throws {
        try withOwnedFile { file in
            let original = Data(repeating: 32, count: WidgetCatalog.maximumDataBytes + 8192)
            try original.write(to: file)
            let bounded = try XCTUnwrap(WidgetSharedStorage.read(fileURL: file))
            XCTAssertEqual(bounded.count, WidgetCatalog.maximumDataBytes + 1)
            XCTAssertEqual(try WidgetSharedStorage.readForEditing(fileURL: file), bounded)
            XCTAssertNil(WidgetCatalog.decode(bounded))
            XCTAssertThrowsError(try WidgetSharedStorage.write(catalog("QA Replacement"), fileURL: file)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableExistingCatalog)
            }
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    func testCorruptUnknownAndDuplicateExistingCatalogsCannotBeClobbered() throws {
        let invalid = [Data(), Data("broken".utf8), Data(#"{"schemaVersion":1,"entries":[],"host":"synthetic.invalid"}"#.utf8),
                       Data(#"{"schemaVersion":1,"entries":[],"entries":[]}"#.utf8)]
        for original in invalid {
            try withOwnedFile { file in
                try original.write(to: file)
                XCTAssertEqual(WidgetSharedStorage.read(fileURL: file), original)
                XCTAssertEqual(try WidgetSharedStorage.readForEditing(fileURL: file), original)
                let reader = WidgetCatalogReader(readData: { WidgetSharedStorage.read(fileURL: file) })
                XCTAssertTrue(reader.read().entries.isEmpty)
                XCTAssertThrowsError(try WidgetSharedStorage.write(catalog("QA Replacement"), fileURL: file)) {
                    XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableExistingCatalog)
                }
                XCTAssertEqual(try Data(contentsOf: file), original)
            }
        }
    }

    func testInvalidIncomingDataPreservesAnExistingValidCatalogAndCannotCreateAFile() throws {
        try withOwnedFile { file in
            XCTAssertThrowsError(try WidgetSharedStorage.write(Data("broken".utf8), fileURL: file))
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            let original = try catalog("QA Original")
            try WidgetSharedStorage.write(original, fileURL: file)
            XCTAssertThrowsError(try WidgetSharedStorage.write(Data(repeating: 32, count: WidgetCatalog.maximumDataBytes + 1), fileURL: file)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .invalidCatalog)
            }
            XCTAssertEqual(WidgetSharedStorage.read(fileURL: file), original)
        }
    }

    func testStorageDoesNotCreateMissingParentsOrReplaceANonRegularFile() throws {
        try withOwnedFile { file in
            let missingParent = file.deletingLastPathComponent().appendingPathComponent("uncreated", isDirectory: true)
            let missingFile = missingParent.appendingPathComponent(WidgetSharedStorage.catalogFileName)
            XCTAssertThrowsError(try WidgetSharedStorage.write(catalog("QA"), fileURL: missingFile)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableContainer)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            XCTAssertNil(WidgetSharedStorage.read(fileURL: file))
            XCTAssertThrowsError(try WidgetSharedStorage.readForEditing(fileURL: file)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableExistingCatalog)
            }
            XCTAssertThrowsError(try WidgetSharedStorage.write(catalog("QA"), fileURL: file)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableExistingCatalog)
            }
            var isDirectory = ObjCBool(false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testSymlinkCatalogIsUnavailableWithoutReadingOrReplacingItsTarget() throws {
        try withOwnedFile { file in
            let target = file.deletingLastPathComponent().appendingPathComponent("synthetic-target.json")
            let original = try catalog("QA Target")
            try original.write(to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertNil(WidgetSharedStorage.read(fileURL: file))
            XCTAssertThrowsError(try WidgetSharedStorage.readForEditing(fileURL: file))
            XCTAssertThrowsError(try WidgetSharedStorage.write(catalog("QA Replacement"), fileURL: file))
            XCTAssertEqual(try Data(contentsOf: target), original)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path), target.path)
        }
    }

    func testEditingReadDistinguishesAMissingFileFromAnUnreadableExistingItem() throws {
        try withOwnedFile { file in
            XCTAssertNil(try WidgetSharedStorage.readForEditing(fileURL: file))
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            XCTAssertThrowsError(try WidgetSharedStorage.readForEditing(fileURL: file))
            XCTAssertNil(WidgetSharedStorage.read(fileURL: file), "A timeline may fail closed, but an editor must receive the failure")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testMissingParentEditingReadThrowsInsteadOfReturningAnEmptyCatalog() throws {
        try withOwnedFile { file in
            let missingParent = file.deletingLastPathComponent().appendingPathComponent("missing-parent", isDirectory: true)
            let missingFile = missingParent.appendingPathComponent(WidgetSharedStorage.catalogFileName)
            XCTAssertThrowsError(try WidgetSharedStorage.readForEditing(fileURL: missingFile)) {
                XCTAssertEqual($0 as? WidgetSharedStorage.Failure, .unavailableContainer)
            }
            XCTAssertNil(WidgetSharedStorage.read(fileURL: missingFile))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missingParent.path))
            XCTAssertNil(try WidgetSharedStorage.readForEditing(fileURL: file), "Only a missing leaf inside an available parent is empty")
        }
    }

    #if os(macOS)
    func testSyntheticChildProcessAndInjectedStorageReadTheSameAtomicFile() throws {
        // Prepared only for a controlled test run. This never uses standard() or an App Group.
        try withOwnedFile { file in
            let first = try catalog("QA Parent")
            try WidgetSharedStorage.write(first, fileURL: file)
            let childRead = try python("import pathlib,sys; sys.stdout.buffer.write(pathlib.Path(sys.argv[1]).read_bytes())", arguments: [file.path])
            XCTAssertEqual(childRead, first)
            let replacement = try catalog("QA Child")
            let hex = replacement.map { String(format: "%02x", $0) }.joined()
            _ = try python("import os,pathlib,sys; p=pathlib.Path(sys.argv[1]); t=p.with_name(p.name+'.child-tmp'); t.write_bytes(bytes.fromhex(sys.argv[2])); os.replace(t,p)", arguments: [file.path, hex])
            XCTAssertEqual(WidgetSharedStorage.read(fileURL: file), replacement)
            XCTAssertEqual(WidgetCatalogReader(readData: { WidgetSharedStorage.read(fileURL: file) }).read().entries.first?.alias, "QA Child")
        }
    }

    private func python(_ source: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", source] + arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostics = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
        return data
    }
    #endif

    private func catalog(_ alias: String) throws -> Data {
        try XCTUnwrap(WidgetCatalog(entries: [.init(id: id, alias: alias)]).validatedData())
    }

    private func withOwnedFile(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AetherScreensWidgetSupportTests." + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent(WidgetSharedStorage.catalogFileName))
    }
}
