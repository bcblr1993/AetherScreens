import XCTest
import RDPKit
@testable import AetherScreensCore

final class RDPClipboardFileDownloaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPClipboardFileDownloaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSanitizedRelativeComponentsRejectsTraversal() {
        XCTAssertEqual(RDPClipboardFileDownloader.sanitizedRelativeComponents("Folder\\Sub\\a.txt"), ["Folder", "Sub", "a.txt"])
        XCTAssertEqual(RDPClipboardFileDownloader.sanitizedRelativeComponents("\\.\\a.txt"), ["a.txt"])
        XCTAssertEqual(RDPClipboardFileDownloader.sanitizedRelativeComponents("C:\\a.txt"), ["C", "a.txt"])
        XCTAssertNil(RDPClipboardFileDownloader.sanitizedRelativeComponents("..\\..\\Library\\evil.plist"))
        XCTAssertNil(RDPClipboardFileDownloader.sanitizedRelativeComponents("Folder/../../evil"))
        XCTAssertNil(RDPClipboardFileDownloader.sanitizedRelativeComponents("\\\\"))
    }

    func testTraversalDescriptorIsNeverWrittenOutsideDownloadDirectory() async throws {
        let downloader = RDPClipboardFileDownloader(temporaryRoot: root)
        let session = SliceSession(payload: Data("x".utf8))
        session.downloader = downloader

        let escape = descriptor("..\\escaped.txt", size: 1)
        let safe = descriptor("safe.txt", size: 1)
        let urls = try await download([escape, safe], with: downloader, session: session)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["safe.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
    }

    func testMissingResponseTimesOutAndRemainingFilesStillComplete() async throws {
        let downloader = RDPClipboardFileDownloader(chunkTimeout: 0.2, temporaryRoot: root)
        final class SilentSession: RDPClipboardFileRangeRequester, @unchecked Sendable {
            func requestRemoteFileRange(streamID: UInt32, fileIndex: Int32, position: UInt64, requestedByteCount: UInt32) throws {}
        }

        let lost = descriptor("lost.bin", size: 10)
        let empty = descriptor("empty.txt", size: 0)
        let started = Date()
        let urls = try await download([lost, empty], with: downloader, session: SilentSession())

        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["empty.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].deletingLastPathComponent().appendingPathComponent("lost.bin").path))
    }

    func testMultiChunkFileIsStreamedInOrder() async throws {
        let payload = Data((0..<(150 * 1024)).map { UInt8($0 % 251) })
        let downloader = RDPClipboardFileDownloader(temporaryRoot: root)
        let session = SliceSession(payload: payload)
        session.downloader = downloader

        let urls = try await download([descriptor("big.bin", size: UInt64(payload.count))], with: downloader, session: session)

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(try Data(contentsOf: urls[0]), payload)
        XCTAssertEqual(session.requestCount, 3)
    }

    func testCancelResumesPendingRequestWithoutCompletion() async throws {
        let downloader = RDPClipboardFileDownloader(chunkTimeout: 30, temporaryRoot: root)
        final class RecordingSession: RDPClipboardFileRangeRequester, @unchecked Sendable {
            let requested: XCTestExpectation
            init(requested: XCTestExpectation) { self.requested = requested }
            func requestRemoteFileRange(streamID: UInt32, fileIndex: Int32, position: UInt64, requestedByteCount: UInt32) throws {
                requested.fulfill()
            }
        }
        let requested = expectation(description: "chunk requested")
        let completed = expectation(description: "not completed")
        completed.isInverted = true

        downloader.downloadFiles(descriptors: [descriptor("a.bin", size: 4)], session: RecordingSession(requested: requested)) { _ in
            completed.fulfill()
        }
        await fulfillment(of: [requested], timeout: 2)
        downloader.cancel()
        await fulfillment(of: [completed], timeout: 0.5)
    }

    func testStaleDownloadDirectoriesAreRemoved() async throws {
        let stale = root.appendingPathComponent(RDPClipboardFileDownloader.temporaryDirectoryPrefix + "old", isDirectory: true)
        let unrelated = root.appendingPathComponent("keep-me", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3 * 24 * 3600)], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3 * 24 * 3600)], ofItemAtPath: unrelated.path)

        let downloader = RDPClipboardFileDownloader(temporaryRoot: root)
        _ = try await download([descriptor("new.txt", size: 0)], with: downloader, session: SliceSession(payload: Data()))

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testDisplayControlSizeIsEvenAndWithinProtocolBounds() {
        XCTAssertTrue(RDPClient.displayControlSize(width: 1281, height: 721) == (1280, 721))
        XCTAssertTrue(RDPClient.displayControlSize(width: 100, height: 50) == (200, 200))
        XCTAssertTrue(RDPClient.displayControlSize(width: 9001, height: 9000) == (8192, 8192))
    }

    // MARK: - Helpers

    private func descriptor(_ name: String, size: UInt64) -> RDPClipboardFileDescriptorW {
        RDPClipboardFileDescriptorW(
            flags: RDPClipboardFileDescriptorFlags.attributes | RDPClipboardFileDescriptorFlags.fileSize | RDPClipboardFileDescriptorFlags.unicode,
            fileAttributes: RDPClipboardFileAttributes.archive,
            fileSize: size,
            fileName: name
        )
    }

    private func download(
        _ descriptors: [RDPClipboardFileDescriptorW],
        with downloader: RDPClipboardFileDownloader,
        session: any RDPClipboardFileRangeRequester
    ) async throws -> [URL] {
        let done = expectation(description: "download completed")
        let box = URLBox()
        downloader.downloadFiles(descriptors: descriptors, session: session) { urls in
            box.urls = urls
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        return box.urls
    }
}

/// Answers each range request with the matching slice of `payload`.
private final class SliceSession: RDPClipboardFileRangeRequester, @unchecked Sendable {
    weak var downloader: RDPClipboardFileDownloader?
    let payload: Data
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    init(payload: Data) { self.payload = payload }

    func requestRemoteFileRange(streamID: UInt32, fileIndex: Int32, position: UInt64, requestedByteCount: UInt32) throws {
        lock.lock(); count += 1; lock.unlock()
        let start = Int(position)
        let end = min(payload.count, start + Int(requestedByteCount))
        let slice = payload.subdata(in: start..<end)
        DispatchQueue.global().async { [weak self] in
            self?.downloader?.handleFileContentsResponse(
                RDPClipboardFileContentsResponse(streamID: streamID, ok: true, data: slice)
            )
        }
    }
}

private final class URLBox: @unchecked Sendable {
    var urls: [URL] = []
}

final class RDPClipboardFilePathTests: XCTestCase {
    func testSameFileURLsIgnoresTrailingSlashAndPrivatePrefix() throws {
        let name = "RDPSame-\(UUID().uuidString)"
        let folder = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let plain = [folder]
        let slashed = [URL(string: "file:///private/tmp/\(name)/")!]
        XCTAssertTrue(SessionViewModel.sameFileURLs(plain, slashed))
        XCTAssertFalse(SessionViewModel.sameFileURLs(plain, [folder.appendingPathComponent("Other")]))
    }

    func testRelativeComponentsHandlesSymlinkedRoot() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("RDPRelative-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        fileManager.createFile(atPath: root.appendingPathComponent("Sub/a.txt").path, contents: Data("a".utf8))

        let enumerated = (fileManager.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        let relative = enumerated.compactMap { SessionViewModel.relativeComponents(of: $0, under: root) }
        XCTAssertEqual(Set(relative.map { $0.joined(separator: "\\") }), ["Sub", "Sub\\a.txt"])
        XCTAssertNil(SessionViewModel.relativeComponents(of: URL(fileURLWithPath: "/etc/hosts"), under: root))
    }
}
