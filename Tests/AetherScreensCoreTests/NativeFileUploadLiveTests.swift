#if os(macOS)
import Foundation
import XCTest
import Combine
import Darwin
@testable import AetherScreensCore

/// Opt-in owned-fixture probe. A server result alone never proves remote receipt;
/// the caller independently compares the remote file over the authorized SSH path.
final class NativeFileUploadLiveTests: XCTestCase {
    func testOwnedNativeUpload() throws { try runOwnedUpload(nested: false) }

    func testOwnedNativeFolderUpload() throws { try runOwnedUpload(nested: true) }

    func testOwnedNativeDownload() throws { try runOwnedDownload(resourceFork: false) }

    func testOwnedNativeResourceForkDownload() throws { try runOwnedDownload(resourceFork: true) }

    func testOwnedNativeFolderDownload() throws { try runOwnedDownload(resourceFork: false, folder: true) }

    @MainActor
    func testOwnedNativeCoordinatedUpload() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_NATIVE_UPLOAD"] == "1",
              let path = env["AETHERSCREENS_QA_UPLOAD_DESTINATION"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Requires explicit coordinated upload opt-in and owned destination")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[1] == "tmp", parts[3] == "destination",
              parts[2].hasPrefix("aetherscreens-native-upload-"),
              UUID(uuidString: String(parts[2].dropFirst("aetherscreens-native-upload-".count))) != nil,
              path.utf8.count < 200 else { XCTFail("Invalid coordinated upload destination"); return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coordinated-upload-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = env["AETHERSCREENS_QA_UPLOAD_FOLDER"] == "1"
        let name = folder ? "fixture-folder" : "fixture.bin"
        let url = root.appendingPathComponent(name)
        if folder {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try Data().write(to: url.appendingPathComponent("empty.bin"))
            try Data([0,255,42]).write(to: url.appendingPathComponent("sibling.bin"))
        }
        let file = folder ? url.appendingPathComponent("nested/fixture.bin") : url
        let dataCount = env["AETHERSCREENS_QA_UPLOAD_LARGE"] == "1" ? 8 * 1_048_576 : (folder ? 131_073 : 512)
        let data = Data((0..<dataCount).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: file, options: .withoutOverwriting)
        let resource = Data((0..<257).map { UInt8(truncatingIfNeeded: 255 - $0) })
        if folder { try resource.write(to: file.appendingPathComponent("..namedfork/rsrc")) }
        let snapshot = try await Task.detached(priority: .utility) {
            try AppleFileCopyUploadSnapshot.prepare(url: url)
        }.value
        defer { snapshot.remove() }
        let prepared = snapshot.prepared
        let expectedBytes = UInt64(data.count + (folder ? resource.count + 3 : 0))
        XCTAssertEqual(prepared.logicalBytes, expectedBytes)
        let changedData = Data(repeating: 9, count: data.count)
        try changedData.write(to: file) // The upload must read the stable copy.

        let portableSources = try prepared.sources.map { source in
            let metadata = try AppleFileCopyCatalogMetadata.decode(source.item.catalogHeader)
            let header = try metadata.encode(dataForkBytes: source.item.dataForkByteCount,
                resourceForkBytes: source.item.resourceForkByteCount, level: source.item.level)
            let item = AppleFileCopyItem(catalogHeader: header, level: source.item.level,
                wireName: source.item.wireName, symbolicLinkTarget: source.item.symbolicLinkTarget,
                extensions: source.item.extensions)
            let normalized = try XCTUnwrap(AppleFileCopyItem.decode(item.message(sessionID: 0), expectedSessionID: 0))
            XCTAssertEqual(normalized, source.item) // Compare against the native Carbon catalog, not itself.
            if source.item.kind == .directory {
                return AppleFileCopySendSession.Source(item: normalized, dataURL: source.dataURL, resourceURL: source.resourceURL)
            }
            let sourceURL = try XCTUnwrap(source.dataURL)
            let portable = try AppleFileCopyPortableSourceCollector.collect(url: sourceURL, level: source.item.level)
            let actualMetadata = try AppleFileCopyCatalogMetadata.decode(portable.item.catalogHeader)
            XCTAssertEqual(actualMetadata.wireFinderInfo, metadata.wireFinderInfo)
            XCTAssertEqual(actualMetadata.permissionMode, metadata.permissionMode)
            XCTAssertEqual(portable.item.dataForkByteCount, source.item.dataForkByteCount)
            XCTAssertEqual(portable.item.resourceForkByteCount, source.item.resourceForkByteCount)
            return AppleFileCopySendSession.Source(item: normalized, dataURL: source.dataURL, resourceURL: source.resourceURL)
        }
        let connected = expectation(description: "Coordinated upload authentication")
        connected.assertForOverFulfill = false
        let client = RFBClient(host: "192.168.50.226", port: 5900, password: password, username: "chenxu")
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed = state { connected.fulfill() }
        }
        client.connect()
        await fulfillment(of: [connected], timeout: 30)
        guard client.state == .connected else { XCTFail("Coordinated upload authentication failed"); return }
        let store = FileTransferTaskStore()
        let coordinator = AppleFileCopyUploadCoordinator(store: store, client: client)
        defer { store.cancelAll() }
        let job = FileTransferJob(direction: .upload, filename: url.lastPathComponent, totalBytes: prepared.logicalBytes)
        let terminal = expectation(description: "Task store receives authoritative upload result")
        terminal.assertForOverFulfill = true
        let observation = store.$jobs.sink { jobs in
            guard let current = jobs.first(where: { $0.id == job.id }) else { return }
            switch current.state {
            case .completed: terminal.fulfill()
            case .failed, .cancelled: XCTFail("Coordinated upload did not complete"); terminal.fulfill()
            default: break
            }
        }
        defer { observation.cancel() }
        let sessionID = UInt32.random(in: 1...UInt32.max)
        let start = try AppleFileCopyStart(direction: .serverReceives, flags: 0,
            reserved: Data(repeating: 0, count: 4), path: Data(path.utf8), trailingBytes: Data()).message(sessionID: sessionID)
        let totals = try AppleFileCopyItemInfo(rawHeaderValue: 0, reserved: Data(repeating: 0, count: 4),
            logicalBytes: prepared.logicalBytes, physicalBytes: prepared.physicalBytes, fileCount: prepared.fileCount,
            forkCount: prepared.forkCount, folderCount: prepared.folderCount, allocationSize: 4096,
            trailing: Data()).message(sessionID: sessionID)
        XCTAssertTrue(try coordinator.start(job: job, sources: portableSources, start: start, totals: totals,
            destinationEncoding: .utf8, writeTimeout: 10, resultTimeout: 15))
        XCTAssertEqual(store.jobs.first?.state, .transferring)
        XCTAssertEqual(store.jobs.first?.transferredBytes, 0)
        await fulfillment(of: [terminal], timeout: 25)
        XCTAssertEqual(store.jobs.first?.state, .completed)
        XCTAssertEqual(store.jobs.first?.transferredBytes, expectedBytes)
        XCTAssertEqual(store.displayFilename(for: try XCTUnwrap(store.jobs.first)), name)
        XCTAssertEqual(try Data(contentsOf: file), changedData)
        let stableURL = try XCTUnwrap(prepared.sources.first { $0.item.wireName == "fixture.bin" }?.dataURL)
        XCTAssertEqual(try Data(contentsOf: stableURL), data)
        if folder {
            XCTAssertEqual(try Data(contentsOf: stableURL.appendingPathComponent("..namedfork/rsrc")), resource)
        }
        snapshot.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stableURL.path))
        XCTAssertEqual(client.state, .connected)
    }

    @MainActor
    func testOwnedNativeCoordinatedDownload() async throws {
        try await runOwnedCoordinatedDownload(folder: false, resourceFork: false)
    }

    @MainActor
    func testOwnedNativeCoordinatedDirectoryWithResourceForkDownload() async throws {
        try await runOwnedCoordinatedDownload(folder: true, resourceFork: true)
    }

    @MainActor
    private func runOwnedCoordinatedDownload(folder: Bool, resourceFork: Bool) async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_NATIVE_DOWNLOAD"] == "1",
              let path = env["AETHERSCREENS_QA_DOWNLOAD_SOURCE"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Requires explicit owned coordinated download opt-in")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[1] == "tmp", parts[3] == (folder ? "fixture-folder" : "fixture.bin"),
              parts[2].hasPrefix("aetherscreens-native-download-"),
              UUID(uuidString: String(parts[2].dropFirst("aetherscreens-native-download-".count))) != nil,
              path.utf8.count < 200 else { XCTFail("Invalid owned coordinated download source"); return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coordinated-download-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = RFBClient(host: "192.168.50.226", port: 5900, password: password, username: "chenxu")
        defer { client.disconnect() }
        let connected = expectation(description: "Coordinated download authenticated")
        connected.assertForOverFulfill = false
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed = state { connected.fulfill() }
        }
        if env["AETHERSCREENS_QA_DOWNLOAD_XATTR"] == "1" || env["AETHERSCREENS_QA_DOWNLOAD_WHEREFROMS"] == "1" {
            client.onAppleFileCopyReceived = { message in
                if let item = try? AppleFileCopyItem.decode(message, expectedSessionID: message.sessionID) {
                    print("Owned native item extension bytes: \(item.extensions.count)")
                    if let block = try? AppleFileCopyAttributeBlock.decode(item.extensions),
                       let entries = try? block.entries() {
                        print("Owned QA attribute present in wire: \(entries.contains { $0.name == Data("com.aethernative.qa".utf8) })")
                    }
                }
            }
        }
        client.connect()
        await fulfillment(of: [connected], timeout: 30)
        guard client.state == .connected else { XCTFail("Coordinated download authentication failed"); return }
        let store = FileTransferTaskStore()
        defer { store.cancelAll() }
        let coordinator = AppleFileCopyDownloadCoordinator(store: store, client: client)
        let sessionID = UInt32.random(in: 1...UInt32.max)
        let request = try AppleFileCopyStart(direction: .serverSends, flags: 1,
            reserved: Data(repeating: 0, count: 4), path: Data(path.utf8), trailingBytes: Data()).message(sessionID: sessionID)
        let expected = Data((0..<131_073).map { UInt8(truncatingIfNeeded: $0) })
        let expectedResource = Data((0..<257).map { UInt8(truncatingIfNeeded: 255 - $0) })
        let totalBytes: UInt64 = 131_073 + (folder ? 3 : 0) + (resourceFork ? 257 : 0)
        let name = folder ? "fixture-folder" : "fixture.bin"
        let sentinel = Data([9,9])
        var releases = 0
        // Same native ID/desktop connection: two successful commits, then a
        // destination conflict that must preserve the existing local content.
        for attempt in 0..<3 {
            let destination = root.appendingPathComponent("attempt-\(attempt)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            let saved = destination.appendingPathComponent(name)
            if attempt == 2 {
                if folder { try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: false) }
                try sentinel.write(to: folder ? saved.appendingPathComponent("sentinel") : saved, options: .withoutOverwriting)
            }
            let index = store.jobs.count
            let terminal = expectation(description: "Coordinated download result \(attempt)")
            let observation = store.$jobs.sink { jobs in
                guard jobs.count > index else { return }
                switch jobs[index].state {
                case .completed, .failed, .cancelled: terminal.fulfill()
                default: break
                }
            }
            defer { observation.cancel() }
            XCTAssertTrue(try coordinator.start(filename: "requested", request: request, destination: destination,
                maximumBytes: totalBytes, maximumItems: folder ? 5 : 1, writeTimeout: 10, inactivityTimeout: 15,
                onReleased: { releases += 1 }))
            XCTAssertFalse(store.jobs[index].isSizeKnown)
            await fulfillment(of: [terminal], timeout: 25)
            if attempt == 2 {
                guard case .failed = store.jobs[index].state else { return XCTFail("Local conflict must fail") }
                XCTAssertEqual(try Data(contentsOf: folder ? saved.appendingPathComponent("sentinel") : saved), sentinel)
                if folder { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: saved.path), ["sentinel"]) }
            } else {
                XCTAssertEqual(store.jobs[index].state, .completed)
                XCTAssertEqual(store.jobs[index].totalBytes, totalBytes)
                XCTAssertEqual(store.jobs[index].transferredBytes, totalBytes)
                XCTAssertEqual(store.displayFilename(for: store.jobs[index]), name)
                let file = folder ? saved.appendingPathComponent("nested/fixture.bin") : saved
                XCTAssertEqual(try Data(contentsOf: file), expected)
                if resourceFork { XCTAssertEqual(try Data(contentsOf: file.appendingPathComponent("..namedfork/rsrc")), expectedResource) }
                if env["AETHERSCREENS_QA_DOWNLOAD_METADATA"] == "1" {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
                    XCTAssertEqual(try XCTUnwrap(attributes[.modificationDate] as? Date).timeIntervalSince1970,
                                   1_700_000_100, accuracy: 1.0 / 65_536)
                }
                if env["AETHERSCREENS_QA_DOWNLOAD_XATTR"] == "1" {
                    let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
                    guard descriptor >= 0 else { return XCTFail("Cannot inspect saved attribute") }
                    defer { close(descriptor) }
                    var attribute = Data(count: 3)
                    XCTAssertEqual(attribute.withUnsafeMutableBytes {
                        fgetxattr(descriptor, "com.aethernative.qa", $0.baseAddress, $0.count, 0, 0)
                    }, 3)
                    XCTAssertEqual(attribute, Data([4,5,6]))
                }
                // Separate from arbitrary xattrs: the inspected native sender
                // explicitly serializes WhereFroms and quarantine only.
                if env["AETHERSCREENS_QA_DOWNLOAD_WHEREFROMS"] == "1" {
                    let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
                    guard descriptor >= 0 else { return XCTFail("Cannot inspect saved WhereFroms") }
                    defer { close(descriptor) }
                    let key = "com.apple.metadata:kMDItemWhereFroms"
                    let count = fgetxattr(descriptor, key, nil, 0, 0, 0)
                    guard count > 0, count <= 4096 else { return XCTFail("Missing or oversized saved WhereFroms") }
                    var value = Data(count: count)
                    XCTAssertEqual(value.withUnsafeMutableBytes {
                        fgetxattr(descriptor, key, $0.baseAddress, $0.count, 0, 0)
                    }, count)
                    let urls = try PropertyListSerialization.propertyList(from: value, options: [], format: nil) as? [String]
                    XCTAssertEqual(urls, ["https://aethernative.com/qa"])
                }
                if folder {
                    XCTAssertEqual(Set(try FileManager.default.subpathsOfDirectory(atPath: saved.path)),
                                   Set(["empty.bin", "nested", "nested/fixture.bin", "sibling.bin"]))
                    XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("empty.bin")), Data())
                    XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("sibling.bin")), Data([0,255,42]))
                }
            }
            XCTAssertFalse(coordinator.isBusy)
            XCTAssertEqual(releases, attempt + 1)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [name])
            XCTAssertEqual(client.state, .connected)
            observation.cancel()
        }
    }

    private func runOwnedDownload(resourceFork: Bool, folder: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_NATIVE_DOWNLOAD"] == "1",
              let path = env["AETHERSCREENS_QA_DOWNLOAD_SOURCE"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Requires explicit owned native download opt-in")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0].isEmpty, parts[1] == "tmp", parts[3] == (folder ? "fixture-folder" : "fixture.bin"),
              parts[2].hasPrefix("aetherscreens-native-download-"),
              UUID(uuidString: String(parts[2].dropFirst("aetherscreens-native-download-".count))) != nil,
              path.utf8.count < 200 else { XCTFail("Invalid owned download path"); return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-download-local-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let connected = expectation(description: "Download connected")
        connected.assertForOverFulfill = false
        let client = RFBClient(host: "192.168.50.226", port: 5900, password: password, username: "chenxu")
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed = state { connected.fulfill() }
        }
        client.onAppleFileCopyReceived = { message in
            print("Native download command: \(message.command), version \(message.version), body bytes \(message.body.count)")
        }
        client.connect()
        guard XCTWaiter.wait(for: [connected], timeout: 30) == .completed, client.state == .connected else {
            XCTFail("Download authentication failed"); return
        }
        let sessionID = UInt32.random(in: 1...UInt32.max)
        // Reuse the same ID on the same desktop connection. Each local commit
        // has a separate owned destination so success cannot reuse stale output.
        for attempt in 0..<2 {
            let attemptRoot = root.appendingPathComponent("attempt-\(attempt)")
            try FileManager.default.createDirectory(at: attemptRoot, withIntermediateDirectories: false)
            let finished = expectation(description: "Native download committed and verified")
            finished.assertForOverFulfill = false
            let receiver = try AppleFileCopyReceiveWorker(sessionID: sessionID, parentDirectory: attemptRoot,
                maximumBytes: folder ? 131_076 : (resourceFork ? 769 : 131_073), maximumItems: folder ? 5 : 1, inactivityTimeout: 15,
                onEvent: { _ in }, onFailure: { XCTFail("Native download failed"); finished.fulfill() },
                onPrepared: { files in
                    defer { files.forEach { $0.cancel() }; finished.fulfill() }
                    do {
                        guard files.count == 1 else { XCTFail("Unexpected download item count"); return }
                        let url = try files[0].commitPreparedFile(to: attemptRoot)
                        XCTAssertEqual(url.lastPathComponent, folder ? "fixture-folder" : "fixture.bin")
                        let expected = Data((0..<(resourceFork ? 512 : 131_073)).map { UInt8(truncatingIfNeeded: $0) })
                        if folder {
                            let entries = try FileManager.default.subpathsOfDirectory(atPath: url.path)
                            XCTAssertEqual(Set(entries), Set(["empty.bin", "nested", "nested/fixture.bin", "sibling.bin"]))
                            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("empty.bin")), Data())
                            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("sibling.bin")), Data([0, 255, 42]))
                            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("nested/fixture.bin")), expected)
                        } else {
                            XCTAssertEqual(try Data(contentsOf: url), expected)
                        }
                        if resourceFork {
                            let expectedResource = Data((0..<257).map { UInt8(truncatingIfNeeded: 255 - $0) })
                            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("..namedfork/rsrc")), expectedResource)
                            print("Native download resource verified bytes: \(expectedResource.count)")
                        }
                        print("Native download verified bytes: \(expected.count)")
                    } catch { XCTFail("Native download commit or verification failed: \(error)") }
                })
            guard client.installAppleFileCopyReceiver(receiver) else { XCTFail("Download receiver not installed"); return }
            let start = try AppleFileCopyStart(direction: .serverSends, flags: 1,
                reserved: Data(repeating: 0, count: 4), path: Data(path.utf8), trailingBytes: Data()).message(sessionID: sessionID)
            XCTAssertTrue(client.sendAppleFileCopy(start))
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 25), .completed)
            client.removeAppleFileCopyReceiver(receiver)
            XCTAssertEqual(client.state, .connected)
        }
    }

    func testOwnedUploadAfterStoppingEmptyTransfer() throws {
        try runOwnedUpload(nested: false, stopFirst: true)
    }

    func testOwnedUploadAfterStoppingPartialTransfer() throws {
        try runOwnedUpload(nested: false, stopFirst: true, partialFirst: true)
    }

    func testOwnedNativeResourceForkUpload() throws {
        try runOwnedUpload(nested: false, resourceFork: true)
    }

    func testOwnedNativeUnicodeNameUpload() throws {
        try runOwnedUpload(nested: false, unicodeName: true)
    }

    private func runOwnedUpload(nested: Bool, stopFirst: Bool = false, partialFirst: Bool = false,
                                resourceFork: Bool = false, unicodeName: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["AETHERSCREENS_QA_NATIVE_UPLOAD"] == "1",
              let path = env["AETHERSCREENS_QA_UPLOAD_DESTINATION"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Requires explicit native upload opt-in and owned destination")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 4, components[0].isEmpty, components[1] == "tmp",
              components[3] == "destination",
              components[2].hasPrefix("aetherscreens-native-upload-"),
              UUID(uuidString: String(components[2].dropFirst("aetherscreens-native-upload-".count))) != nil,
              path.utf8.count < 200 else {
            XCTFail("Destination must be a short uniquely owned QA directory"); return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-upload-source-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("fixture-folder")
        let child = folder.appendingPathComponent("nested")
        if nested {
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("empty.bin"), options: .withoutOverwriting)
            try Data([0, 255, 42]).write(to: folder.appendingPathComponent("sibling.bin"), options: .withoutOverwriting)
        }
        let filename = unicodeName ? "测试-屏幕😀.bin" : "fixture.bin"
        let url = (nested ? child : root).appendingPathComponent(filename)
        let data = Data((0..<(nested ? 131_073 : 512)).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: url, options: .withoutOverwriting)
        let resourceData = Data((0..<257).map { UInt8(truncatingIfNeeded: 255 - $0) })
        if resourceFork {
            try resourceData.write(to: url.appendingPathComponent("..namedfork/rsrc"))
        }
        let entries: [(URL, UInt16)] = nested ? [
            (folder, UInt16(0)), (folder.appendingPathComponent("empty.bin"), UInt16(1)),
            (child, UInt16(1)), (url, UInt16(2)), (folder.appendingPathComponent("sibling.bin"), UInt16(1))
        ] : [(url, UInt16(0))]
        let sources = try entries.map { try AppleFileCopySourceCollector.collect(url: $0.0, level: $0.1) }
        let logicalBytes = UInt64(data.count + (nested ? 3 : 0) + (resourceFork ? resourceData.count : 0))
        let connected = expectation(description: "Native upload authentication")
        connected.assertForOverFulfill = false
        let client = RFBClient(host: "192.168.50.226", port: 5900,
                               password: password, username: "chenxu")
        defer { client.disconnect() }
        client.onStateChanged = { state in
            if state == .connected { connected.fulfill() }
            if case .failed = state { connected.fulfill() }
        }
        client.onAppleFileCopyReceived = { message in
            print("Native upload status: command \(message.command), version \(message.version), body bytes \(message.body.count)")
        }
        client.connect()
        guard XCTWaiter.wait(for: [connected], timeout: 30) == .completed,
              client.state == .connected else { XCTFail("Upload authentication failed"); return }
        let sessionID = UInt32.random(in: 1...UInt32.max)
        func send(_ message: AppleFileCopyMessage) -> Bool {
            let written = expectation(description: "Local file-copy command \(message.command)")
            written.assertForOverFulfill = false
            let result = LocalWriteResult()
            guard client.sendAppleFileCopy(message, processed: { success in
                result.set(success); written.fulfill()
            }) else { XCTFail("File-copy command was not admitted"); return false }
            guard XCTWaiter.wait(for: [written], timeout: 10) == .completed, result.success else {
                XCTFail("Local file-copy write did not complete"); return false
            }
            return true
        }
        if stopFirst {
            let stoppedID = sessionID == UInt32.max ? 1 : sessionID + 1
            let emptyStart = try AppleFileCopyStart(direction: .serverReceives, flags: 0,
                reserved: Data(repeating: 0, count: 4), path: Data(path.utf8),
                trailingBytes: Data()).message(sessionID: stoppedID)
            guard send(emptyStart) else { return }
            if partialFirst {
                let partialURL = root.appendingPathComponent("partial.bin")
                try data.write(to: partialURL, options: .withoutOverwriting)
                let partial = try AppleFileCopySourceCollector.collect(url: partialURL, level: 0)
                let totals = try AppleFileCopyItemInfo(rawHeaderValue: 0, reserved: Data(repeating: 0, count: 4),
                    logicalBytes: UInt64(data.count), physicalBytes: 4096, fileCount: 1, forkCount: 1,
                    folderCount: 0, allocationSize: 4096, trailing: Data()).message(sessionID: stoppedID)
                var body = Data([0, 0, 0, 128])
                body.append(data.prefix(128))
                guard send(totals), send(try partial.item.message(sessionID: stoppedID)),
                      send(.init(version: 1, command: 102, sessionID: stoppedID, body: body)) else { return }
                XCTAssertEqual(try Data(contentsOf: partialURL), data)
            }
            guard send(AppleFileCopyControl.stop.message(sessionID: stoppedID)) else { return }
        }
        let start = try AppleFileCopyStart(direction: .serverReceives, flags: 0,
            reserved: Data(repeating: 0, count: 4), path: Data(path.utf8), trailingBytes: Data()).message(sessionID: sessionID)
        let totals = try AppleFileCopyItemInfo(rawHeaderValue: 0, reserved: Data(repeating: 0, count: 4),
            logicalBytes: logicalBytes, physicalBytes: nested ? 139_264 : 4096, fileCount: nested ? 3 : 1, forkCount: nested || resourceFork ? 2 : 1,
            folderCount: nested ? 2 : 0, allocationSize: 4096, trailing: Data()).message(sessionID: sessionID)
        guard let generation = client.fileCopyTransportGeneration else {
            XCTFail("Upload connection generation was unavailable"); return
        }
        let startup = try AppleFileCopyStartupTransport(start: start, totals: totals,
            transport: { [weak client] message, done in
                client?.sendAppleFileCopy(message, expectedGeneration: generation, processed: done) ?? false
            })
        defer { startup.cancel() }
        let terminal = expectation(description: "Native upload final result")
        terminal.assertForOverFulfill = false
        let sender = try AppleFileCopySendWorker(sessionID: sessionID, sources: sources, maximumBytes: logicalBytes,
            writeTimeout: 10, resultTimeout: 15, transport: { message, done in
                startup.send(message, processed: done)
            }, onCompleted: { name in
                if unicodeName { XCTAssertEqual(name, Data(filename.utf8)) }
                terminal.fulfill()
            }, onFailure: {
                XCTFail("Native upload rejected or timed out"); terminal.fulfill()
            })
        guard client.installAppleFileCopySender(sender) else { XCTFail("Upload owner was not installed"); return }
        defer { client.removeAppleFileCopySender(sender) }
        XCTAssertTrue(sender.start())
        XCTAssertEqual(XCTWaiter.wait(for: [terminal], timeout: 25), .completed)
        XCTAssertEqual(try Data(contentsOf: url), data)
        if resourceFork {
            XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("..namedfork/rsrc")), resourceData)
        }
        if nested {
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("empty.bin")), Data())
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("sibling.bin")), Data([0, 255, 42]))
        }
        XCTAssertEqual(client.state, .connected)
    }
}

private final class LocalWriteResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ success: Bool) { lock.lock(); value = success; lock.unlock() }
    var success: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
#endif
