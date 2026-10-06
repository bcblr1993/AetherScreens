import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import AetherScreensCore

final class SystemClipboardTests: XCTestCase {
    @MainActor
    func testAsyncPromisedFlavorsPreserveDataWithoutBlockingMainActor() async throws {
        let provider = NSItemProvider()
        let text = Data("async 中文🙂".utf8)
        provider.registerDataRepresentation(forTypeIdentifier: "public.utf8-plain-text", visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { completion(text, nil) }
            return Progress(totalUnitCount: 1)
        }
        let heartbeat = expectation(description: "MainActor remains responsive while loading promised data")
        Task { @MainActor in heartbeat.fulfill() }
        let items = await SystemClipboard.read(providers: [provider])
        await fulfillment(of: [heartbeat], timeout: 1)
        XCTAssertEqual(items, [.init(type: "public.utf8-plain-text", data: text)])
        let multiple = await SystemClipboard.read(providers: [provider, provider])
        XCTAssertEqual(multiple, [], "Multiple items must not be flattened")
    }

    @MainActor
    func testUnresponsivePromisedDataTimesOutAndCancellationFinishes() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "public.utf8-plain-text", visibility: .all) { _ in
            Progress(totalUnitCount: 1)
        }
        let start = ProcessInfo.processInfo.systemUptime
        let timedOut = await SystemClipboard.read(providers: [provider], timeout: 0.05)
        XCTAssertNil(timedOut)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
        let task = Task { await SystemClipboard.read(providers: [provider], timeout: 30) }
        task.cancel()
        let cancelled = await task.value
        XCTAssertNil(cancelled)
    }

    @MainActor
    func testSupportedTypesPreserveBinaryDataAndAddTextFallbackWithoutDuplicates() {
        let image = RFBClipboardFlavor(type: "public.png", data: Data([0, 255, 128]))
        let text = RFBClipboardFlavor(type: "public.utf16-plain-text", data: Data([65, 0, 0x2D, 0x4E]))
        let result = SystemClipboard.supported([image, image, text, .init(type: "private.unsupported", data: Data([1]))])
        XCTAssertEqual(result, [image, text, .init(type: "public.utf8-plain-text", data: Data("A中".utf8))])
        XCTAssertTrue(SystemClipboard.supported([]).isEmpty)
        XCTAssertTrue(SystemClipboard.supported([.init(type: "private.unsupported", data: Data([1]))]).isEmpty)
    }

    #if canImport(AppKit)
    @MainActor
    func testNativeIsolatedPasteboardPreservesAllFlavorsAndRejectsUnsupportedReplacement() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let flavors: [RFBClipboardFlavor] = [
            .init(type: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0, 255])),
            .init(type: "public.url", data: Data("https://example.com/中文".utf8)),
            .init(type: "public.rtf", data: Data("{\\rtf1 rich}".utf8)),
            .init(type: "public.utf8-plain-text", data: Data("fallback中".utf8))
        ]
        XCTAssertTrue(SystemClipboard.write(flavors, to: board))
        let actual = Dictionary(uniqueKeysWithValues: SystemClipboard.read(from: board).map { ($0.type, $0.data) })
        for flavor in flavors { XCTAssertEqual(actual[flavor.type], flavor.data) }
        // AppKit can advertise additional synthesized text representations.
        XCTAssertTrue(Set(actual.keys).isSuperset(of: Set(flavors.map(\.type))))
        XCTAssertEqual(board.string(forType: .string), "fallback中")
        let changeCount = board.changeCount
        XCTAssertFalse(SystemClipboard.write([.init(type: "private.unsupported", data: Data([1]))], to: board))
        XCTAssertEqual(board.changeCount, changeCount)
        XCTAssertEqual(board.string(forType: .string), "fallback中")
        let other = NSPasteboardItem()
        other.setString("second", forType: .string)
        board.writeObjects([other])
        XCTAssertTrue(SystemClipboard.read(from: board).isEmpty, "Multiple local items must not be silently flattened")
        XCTAssertTrue(SystemClipboard.write([], to: board), "A valid remote empty archive must clear the local clipboard")
        XCTAssertTrue(board.pasteboardItems?.isEmpty ?? true)
    }
    #endif
}
