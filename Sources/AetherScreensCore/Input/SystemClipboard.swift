import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Converts supported remote content; unsupported archives preserve the local
/// clipboard, while a valid empty remote archive clears it. Apple archives describe flavors of
/// one clipboard item; multiple local items are not flattened into one item.
@MainActor
enum SystemClipboard {
    static let supportedTypes: Set<String> = [
        "public.utf8-plain-text", "public.utf16-plain-text", "public.utf16-external-plain-text",
        "com.apple.traditional-mac-plain-text", "public.png", "public.jpeg", "public.tiff",
        "public.url", "public.rtf", "public.html"
    ]

    static func supported(_ items: [RFBClipboardFlavor]) -> [RFBClipboardFlavor] {
        var seen = Set<String>()
        var result = items.filter { supportedTypes.contains($0.type) && seen.insert($0.type).inserted }
        if !seen.contains("public.utf8-plain-text"), let text = ApplePasteboard.text(in: items), !items.isEmpty {
            result.append(.init(type: "public.utf8-plain-text", data: Data(text.utf8)))
        }
        return result
    }

    static var changeCount: Int {
        #if canImport(UIKit)
        return UIPasteboard.general.changeCount
        #elseif canImport(AppKit)
        return NSPasteboard.general.changeCount
        #else
        return 0
        #endif
    }

    static func read() -> [RFBClipboardFlavor] {
        #if canImport(UIKit)
        let board = UIPasteboard.general
        guard board.numberOfItems == 1 else { return [] }
        return board.types.filter { supportedTypes.contains($0) }.compactMap { type in
            board.data(forPasteboardType: type).map { .init(type: type, data: $0) }
        }
        #elseif canImport(AppKit)
        return read(from: .general)
        #else
        return []
        #endif
    }

    static func readAsync() async -> [RFBClipboardFlavor]? {
        #if canImport(UIKit)
        return await read(providers: UIPasteboard.general.itemProviders)
        #else
        return read()
        #endif
    }

    /// Promised data belongs to another process; never wait for it on the UI thread.
    static func read(providers: [NSItemProvider], timeout: TimeInterval = 3) async -> [RFBClipboardFlavor]? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        guard providers.count == 1 else { return [] }
        let provider = providers[0], deadline = ProcessInfo.processInfo.systemUptime + timeout
        var items: [RFBClipboardFlavor] = []
        var bytes = 0
        for type in provider.registeredTypeIdentifiers where supportedTypes.contains(type) {
            guard !Task.isCancelled else { return nil }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, let data = await load(provider: provider, type: type, timeout: remaining),
                  data.count <= ApplePasteboard.maximumArchiveBytes - bytes else { return nil }
            bytes += data.count
            items.append(.init(type: type, data: data))
        }
        return items
    }

    private static func load(provider: NSItemProvider, type: String, timeout: TimeInterval) async -> Data? {
        let load = ClipboardProviderLoad()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard load.install(continuation) else { return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { load.finish(nil) }
                let progress = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    load.finish(error == nil && (data?.count ?? 0) <= ApplePasteboard.maximumArchiveBytes ? data : nil)
                }
                load.install(progress)
            }
        } onCancel: { load.finish(nil) }
    }

    @discardableResult
    static func write(_ items: [RFBClipboardFlavor]) -> Bool {
        #if canImport(UIKit)
        if items.isEmpty { UIPasteboard.general.items = []; return true }
        let flavors = supported(items)
        guard !flavors.isEmpty else { return false }
        UIPasteboard.general.items = [Dictionary(uniqueKeysWithValues: flavors.map { ($0.type, $0.data as Any) })]
        return true
        #elseif canImport(AppKit)
        return write(items, to: .general)
        #else
        return false
        #endif
    }

    #if canImport(AppKit) && !canImport(UIKit)
    static func read(from board: NSPasteboard) -> [RFBClipboardFlavor] {
        guard let items = board.pasteboardItems, items.count == 1, let item = items.first else { return [] }
        return item.types.filter { supportedTypes.contains($0.rawValue) }.compactMap { type in
            item.data(forType: type).map { .init(type: type.rawValue, data: $0) }
        }
    }

    @discardableResult
    static func write(_ items: [RFBClipboardFlavor], to board: NSPasteboard) -> Bool {
        if items.isEmpty { board.clearContents(); return true }
        let flavors = supported(items)
        guard !flavors.isEmpty else { return false }
        let item = NSPasteboardItem()
        for flavor in flavors {
            guard item.setData(flavor.data, forType: .init(flavor.type)) else { return false }
        }
        board.clearContents()
        return board.writeObjects([item])
    }
    #endif
}

private final class ClipboardProviderLoad: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var cancelled = false
    private var continuation: CheckedContinuation<Data?, Never>?
    private var progress: Progress?

    func install(_ continuation: CheckedContinuation<Data?, Never>) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(returning: nil); return false }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(_ progress: Progress) {
        lock.lock()
        let cancelled = self.cancelled
        if !finished { self.progress = progress }
        lock.unlock()
        if cancelled { progress.cancel() }
    }

    func finish(_ data: Data?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        cancelled = data == nil
        let continuation = self.continuation, progress = self.progress
        self.continuation = nil; self.progress = nil
        lock.unlock()
        if data == nil { progress?.cancel() }
        continuation?.resume(returning: data)
    }
}
