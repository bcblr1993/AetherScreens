#if os(macOS)
import XCTest
import Darwin
@testable import AetherScreensCore

final class AppleFileCopySourceCollectorTests: XCTestCase {
    func testRecursiveTreeRestoresEachCatalogAndRejectsIntermediateSymlink() throws {
        try withRoot { root in
            let folder = root.appendingPathComponent("original")
            let nested = folder.appendingPathComponent("nested")
            let file = nested.appendingPathComponent("child")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data([1, 2]).write(to: file)
            for (index, url) in [file, nested, folder].enumerated() {
                let finder = Data([UInt8(65 + index),66,67,68,69,70,71,72] + [UInt8](repeating: 0, count: 24))
                try setAttribute("com.apple.FinderInfo", value: finder, url: url)
                try FileManager.default.setAttributes([.modificationDate:
                    Date(timeIntervalSince1970: 1_600_000_000 + Double(index * 100))], ofItemAtPath: url.path)
            }
            let sources = try [folder, nested, file].enumerated().map {
                try AppleFileCopySourceCollector.collect(url: $0.element, level: UInt16($0.offset))
            }
            func receiveTree() throws -> AppleFileCopyStagingFile {
                let sender = try AppleFileCopySendSession(sessionID: 42, sources: sources, maximumBytes: 2, blockSize: 1)
                let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                    maximumBytes: 2, maximumItems: 3)
                while sender.state == .sending {
                    var packet: AppleFileCopyMessage?
                    XCTAssertTrue(try sender.pump { packet = $0; return true })
                    _ = try receiver.receive(XCTUnwrap(packet))
                }
                let trees = try receiver.takePreparedTrees()
                receiver.cancel() // Ownership and all descendant catalog records moved.
                return try XCTUnwrap(trees.first)
            }
            let tree = try receiveTree()
            try tree.restoreCatalogMetadata()
            let target = root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let destination = try tree.commitPreparedFile(to: target)
            for (index, url) in [destination, destination.appendingPathComponent("nested"),
                                destination.appendingPathComponent("nested/child")].enumerated() {
                let collected = try AppleFileCopySourceCollector.collect(url: url, level: UInt16(index))
                let actual = try AppleFileCopyCatalogMetadata.decode(collected.item.catalogHeader)
                let expected = try AppleFileCopyCatalogMetadata.decode(sources[index].item.catalogHeader)
                XCTAssertEqual(actual.finderInfoAttribute, expected.finderInfoAttribute)
                XCTAssertEqual(actual.contentModified.date.timeIntervalSince1970,
                    expected.contentModified.date.timeIntervalSince1970, accuracy: 0.001)
                XCTAssertEqual(actual.created.date.timeIntervalSince1970,
                    expected.created.date.timeIntervalSince1970, accuracy: 0.001)
            }
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("nested/child")), Data([1, 2]))
            let unsafeTree = try receiveTree()
            defer { unsafeTree.cancel() }
            let receivedNested = unsafeTree.dataForkURL.appendingPathComponent("nested")
            try FileManager.default.removeItem(at: receivedNested)
            try FileManager.default.createSymbolicLink(at: receivedNested, withDestinationURL: nested)
            XCTAssertThrowsError(try unsafeTree.restoreCatalogMetadata())
            let untouched = try AppleFileCopySourceCollector.collect(url: file, level: 2)
            // Source reads may update access time; content and Finder must remain unchanged.
            let after = try AppleFileCopyCatalogMetadata.decode(untouched.item.catalogHeader)
            let before = try AppleFileCopyCatalogMetadata.decode(sources[2].item.catalogHeader)
            XCTAssertEqual(after.finderInfoAttribute, before.finderInfoAttribute)
            XCTAssertEqual(after.contentModified, before.contentModified)
            unsafeTree.cancel()
            XCTAssertEqual(try Data(contentsOf: file), Data([1, 2]))
        }
    }

    func testCatalogRestoreRejectsReplacedSymlinkPayloadWithoutTouchingItsTarget() throws {
        try withRoot { root in
            let source = root.appendingPathComponent("source")
            try Data([1]).write(to: source)
            let original = try AppleFileCopySourceCollector.collect(url: source, level: 0)
            let staging = try AppleFileCopyStagingFile(item: original.item, sessionID: 42,
                parentDirectory: root, maximumFileBytes: 1)
            defer { staging.cancel() }
            _ = try staging.append(.init(version: 1, command: 102, sessionID: 42,
                body: Data([0,0,0,1,1])), inflater: AppleFileCopyInflater())
            try staging.finish()
            try FileManager.default.removeItem(at: staging.dataForkURL)
            try FileManager.default.createSymbolicLink(at: staging.dataForkURL, withDestinationURL: source)
            XCTAssertThrowsError(try staging.restoreCatalogMetadata())
            let afterSymlink = try AppleFileCopySourceCollector.collect(url: source, level: 0)
            XCTAssertEqual(afterSymlink.item.catalogHeader, original.item.catalogHeader)
            try FileManager.default.removeItem(at: staging.dataForkURL)
            try FileManager.default.linkItem(at: source, to: staging.dataForkURL)
            let beforeHardlinkRestore = try AppleFileCopySourceCollector.collect(url: source, level: 0)
            XCTAssertThrowsError(try staging.restoreCatalogMetadata())
            let after = try AppleFileCopySourceCollector.collect(url: source, level: 0)
            XCTAssertEqual(after.item.catalogHeader, beforeHardlinkRestore.item.catalogHeader)
            staging.cancel()
            XCTAssertEqual(try Data(contentsOf: source), Data([1]))
        }
    }

    func testPreparedFileRestoresCatalogDatesAndOverridesConflictingFinderAttribute() throws {
        try withRoot { root in
            let file = root.appendingPathComponent("source")
            try Data([1]).write(to: file)
            let finder = Data([65,66,67,68,69,70,71,72] + [UInt8](repeating: 0, count: 24))
            try setAttribute("com.apple.FinderInfo", value: finder, url: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000.5)], ofItemAtPath: file.path)
            let collected = try AppleFileCopySourceCollector.collect(url: file, level: 0)
            var attributes = try XCTUnwrap(AppleFileCopyAttributeBlock.decode(collected.item.extensions)?.entries())
            attributes = attributes.filter { $0.name != Data("com.apple.FinderInfo".utf8) }
            attributes.append(.init(name: Data("com.apple.FinderInfo".utf8),
                value: Data([87,88,89,90,65,66,67,68] + [UInt8](repeating: 0, count: 24))))
            let item = AppleFileCopyItem(catalogHeader: collected.item.catalogHeader, level: 0,
                wireName: "copy", symbolicLinkTarget: nil,
                extensions: try AppleFileCopyAttributeBlock.encode(entries: attributes))
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [
                .init(item: item, dataURL: file, resourceURL: nil)], maximumBytes: 1)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 1, maximumItems: 1)
            defer { receiver.cancel() }
            while sender.state == .sending {
                var packet: AppleFileCopyMessage?
                XCTAssertTrue(try sender.pump { packet = $0; return true })
                _ = try receiver.receive(XCTUnwrap(packet))
            }
            let prepared = try receiver.takePreparedTrees()
            try prepared[0].restoreCatalogMetadata()
            let destination = try prepared[0].commitPreparedFile(to: root)
            let actual = try AppleFileCopySourceCollector.collect(url: destination, level: 0)
            let originalMetadata = try AppleFileCopyCatalogMetadata.decode(collected.item.catalogHeader)
            let restoredMetadata = try AppleFileCopyCatalogMetadata.decode(actual.item.catalogHeader)
            XCTAssertEqual(restoredMetadata.finderInfoAttribute, finder)
            XCTAssertEqual(restoredMetadata.contentModified.date.timeIntervalSince1970,
                originalMetadata.contentModified.date.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(restoredMetadata.created.date.timeIntervalSince1970,
                originalMetadata.created.date.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertThrowsError(try prepared[0].restoreCatalogMetadata())
            XCTAssertEqual(try Data(contentsOf: destination), Data([1]))
        }
    }

    func testDirectoryCatalogRestorationRunsAfterChildAssembly() throws {
        try withRoot { root in
            let folder = root.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let file = folder.appendingPathComponent("child")
            try Data([1]).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: folder.path)
            let directorySource = try AppleFileCopySourceCollector.collect(url: folder, level: 0)
            let childSource = try AppleFileCopySourceCollector.collect(url: file, level: 1)
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [directorySource, childSource], maximumBytes: 1)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 1, maximumItems: 2)
            defer { receiver.cancel() }
            while sender.state == .sending {
                var packet: AppleFileCopyMessage?
                XCTAssertTrue(try sender.pump { packet = $0; return true })
                _ = try receiver.receive(XCTUnwrap(packet))
            }
            let prepared = try receiver.takePreparedTrees()
            let before = try AppleFileCopySourceCollector.collect(url: prepared[0].dataForkURL, level: 0)
            XCTAssertNotEqual(try AppleFileCopyCatalogMetadata.decode(before.item.catalogHeader).contentModified.wholeSeconds,
                try AppleFileCopyCatalogMetadata.decode(directorySource.item.catalogHeader).contentModified.wholeSeconds)
            try prepared[0].restoreCatalogMetadata()
            let target = root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let destination = try prepared[0].commitPreparedFile(to: target)
            let after = try AppleFileCopySourceCollector.collect(url: destination, level: 0)
            XCTAssertEqual(try AppleFileCopyCatalogMetadata.decode(after.item.catalogHeader).contentModified.wholeSeconds,
                try AppleFileCopyCatalogMetadata.decode(directorySource.item.catalogHeader).contentModified.wholeSeconds)
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("child")), Data([1]))
        }
    }

    func testCollectedSourceSendsAndCommitsResourceAndBinaryAttribute() throws {
        try withRoot { root in
            let file = root.appendingPathComponent("input:name")
            try Data([1, 2, 3]).write(to: file)
            try Data([8, 9]).write(to: file.appendingPathComponent("..namedfork/rsrc"))
            try setAttribute("com.aethernative.qa.binary", value: Data([0, 255, 7]), url: file)
            let source = try AppleFileCopySourceCollector.collect(url: file, level: 0)
            let sender = try AppleFileCopySendSession(sessionID: 42, sources: [source], maximumBytes: 5, blockSize: 2)
            let receiver = try AppleFileCopyReceiveSession(sessionID: 42, parentDirectory: root,
                maximumBytes: 5, maximumItems: 1)
            defer { receiver.cancel() }
            while sender.state == .sending {
                var message: AppleFileCopyMessage?
                XCTAssertTrue(try sender.pump { message = $0; return true })
                _ = try receiver.receive(XCTUnwrap(message))
            }
            let trees = try receiver.takePreparedTrees()
            let target = root.appendingPathComponent("target")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let destination = try trees[0].commitPreparedFile(to: target)
            XCTAssertEqual(destination.lastPathComponent, "input:name")
            XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
            XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("..namedfork/rsrc")), Data([8, 9]))
            var attribute = Data(count: 3)
            let count = destination.withUnsafeFileSystemRepresentation { path in
                attribute.withUnsafeMutableBytes { getxattr(path!, "com.aethernative.qa.binary", $0.baseAddress, 3, 0, 0) }
            }
            XCTAssertEqual(count, 3); XCTAssertEqual(attribute, Data([0, 255, 7]))
            XCTAssertEqual(sender.state, .awaitingResult)
            XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
        }
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aetherscreens-catalog-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func setAttribute(_ name: String, value: Data, url: URL) throws {
        let status = url.withUnsafeFileSystemRepresentation { path in
            name.withCString { name in value.withUnsafeBytes { setxattr(path!, name, $0.baseAddress, value.count, 0, 0) } }
        }
        XCTAssertEqual(status, 0)
    }

    func testRealFileCatalogCollectsDatesPermissionsFinderAttributesAndBothForks() throws {
        try withRoot { root in
            let file = root.appendingPathComponent("QA:报告😀")
            try Data([1, 2, 3]).write(to: file)
            let modified = Date(timeIntervalSince1970: 1_700_000_000.5)
            try FileManager.default.setAttributes([.posixPermissions: 0o640, .modificationDate: modified], ofItemAtPath: file.path)
            let finder = Data([65,66,67,68,69,70,71,72,0x12,0x34,0x56,0x78,0,0,0,0,
                               0x11,0x22,0,0,0,0,0,0,0,0,0x33,0x44,0x55,0x66,0x77,0x88])
            try setAttribute("com.apple.FinderInfo", value: finder, url: file)
            try setAttribute("com.aethernative.qa.binary", value: Data([0,255,7]), url: file)
            try Data([8,9]).write(to: file.appendingPathComponent("..namedfork/rsrc"))
            let source = try AppleFileCopySourceCollector.collect(url: file, level: 2)
            let catalog = try AppleFileCopyCatalogMetadata.decode(source.item.catalogHeader)
            XCTAssertEqual(source.item.wireName, "QA/报告😀")
            XCTAssertEqual(source.item.kind, .file)
            XCTAssertEqual(source.item.level, 2)
            XCTAssertEqual(source.item.dataForkByteCount, 3)
            XCTAssertEqual(source.item.resourceForkByteCount, 2)
            XCTAssertEqual(catalog.rawItemKind, 1)
            XCTAssertEqual(catalog.permissionMode & 0o777, 0o640)
            XCTAssertEqual(catalog.finderInfoAttribute, finder)
            let actualDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
            XCTAssertEqual(catalog.contentModified.date.timeIntervalSince1970, actualDate.timeIntervalSince1970, accuracy: 0.001)
            let entries = try XCTUnwrap(AppleFileCopyAttributeBlock.decode(source.item.extensions)?.entries())
            XCTAssertTrue(entries.contains(.init(name: Data("com.aethernative.qa.binary".utf8), value: Data([0,255,7]))))
            XCTAssertFalse(entries.contains { $0.name == Data("com.apple.ResourceFork".utf8) })
            let reader = try AppleFileCopyForkReader(item: source.item, sessionID: 42,
                dataURL: try XCTUnwrap(source.dataURL), resourceURL: source.resourceURL, blockSize: 4)
            XCTAssertEqual(try reader.nextMessage()?.body, Data([0,0,0,3,1,2,3]))
            XCTAssertEqual(try reader.nextMessage()?.body, Data([0,0,0,2,8,9]))
            XCTAssertNil(try reader.nextMessage())
        }
    }

    func testDirectoryCatalogUsesNativeFolderFinderWordOrder() throws {
        try withRoot { root in
            let folder = root.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let finder = Data([65,66,67,68,69,70,71,72,0x12,0x34,0x56,0x78,0,0,0,0,
                               0x11,0x22,0,0,0,0,0,0,0,0,0x33,0x44,0x55,0x66,0x77,0x88])
            try setAttribute("com.apple.FinderInfo", value: finder, url: folder)
            let source = try AppleFileCopySourceCollector.collect(url: folder, level: 0)
            XCTAssertTrue(source.item.isDirectory)
            XCTAssertEqual(source.item.kind, .directory)
            XCTAssertNil(source.dataURL); XCTAssertNil(source.resourceURL)
            XCTAssertEqual(source.item.dataForkByteCount, 0)
            XCTAssertEqual(try AppleFileCopyCatalogMetadata.decode(source.item.catalogHeader).finderInfoAttribute, finder)
        }
    }

    func testSymbolicLinkAndOversizedAttributesAreRejectedWithoutChangingSource() throws {
        try withRoot { root in
            let file = root.appendingPathComponent("file"), link = root.appendingPathComponent("link")
            try Data([1]).write(to: file)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            XCTAssertThrowsError(try AppleFileCopySourceCollector.collect(url: link, level: 0))
            try setAttribute("com.aethernative.qa.large", value: Data(repeating: 1, count: 65_535), url: file)
            XCTAssertThrowsError(try AppleFileCopySourceCollector.collect(url: file, level: 0))
            XCTAssertEqual(try Data(contentsOf: file), Data([1]))
        }
    }
}
#endif
