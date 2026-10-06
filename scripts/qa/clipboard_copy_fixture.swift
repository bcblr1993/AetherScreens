import AppKit
import Foundation

final class CommandMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [String] = []
    func append(_ command: String) {
        lock.lock(); defer { lock.unlock() }
        commands.append(command)
    }
    func next() -> String? {
        lock.lock(); defer { lock.unlock() }
        return commands.isEmpty ? nil : commands.removeFirst()
    }
}

// Run in the target Mac's logged-in account through SSH. Only status tokens
// leave this process. Original clipboard flavors remain in memory and are
// restored on EOF/END unless another application has since changed them.
let board = NSPasteboard.general
if CommandLine.arguments.contains("--verify-restored") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let saved = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Data]] else {
        exit(2)
    }
    let current = board.pasteboardItems ?? []
    let matches = current.count == saved.count && zip(saved, current).allSatisfy { expected, item in
        expected.allSatisfy { item.data(forType: .init($0.key)) == $0.value }
    }
    print(matches ? "RESTORE_VERIFIED" : "RESTORE_MISMATCH")
    exit(matches ? 0 : 2)
}

func verifyRestorationFromAnotherProcess(_ saved: [NSPasteboardItem]) -> Bool {
    // Original data stays on this Mac in anonymous pipes, never in files, SSH
    // output, command arguments or environment variables. An independent reader
    // also materializes any promised representations before this owner exits.
    let snapshot = saved.map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
            item.data(forType: type).map { (type.rawValue, $0) }
        })
    }
    guard let data = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0) else {
        return false
    }
    let process = Process(), input = Pipe(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = [CommandLine.arguments[0], "--verify-restored"]
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: data)
        try input.fileHandleForWriting.close()
        let deadline = Date(timeIntervalSinceNow: 15)
        while process.isRunning, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        if process.isRunning { process.terminate(); return false }
        let status = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return process.terminationStatus == 0 && status.trimmingCharacters(in: .whitespacesAndNewlines) == "RESTORE_VERIFIED"
    } catch {
        if process.isRunning { process.terminate() }
        return false
    }
}

func richFlavors(_ marker: String) -> [(NSPasteboard.PasteboardType, Data)] {
    [
        (.png, Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMIqDjxHwAFPAKQ8H9qXAAAAABJRU5ErkJggg==")!),
        (.init("public.url"), Data("https://example.com/\(marker)".utf8)),
        (.rtf, Data("{\\rtf1\\ansi \(marker)}".utf8)),
        (.html, Data("<p>\(marker)</p>".utf8)),
        (.string, Data(marker.utf8))
    ]
}
let initialCount = board.changeCount
var original: [NSPasteboardItem] = []
var totalBytes = 0
for item in board.pasteboardItems ?? [] {
    let saved = NSPasteboardItem()
    for type in item.types {
        guard let data = item.data(forType: type) else {
            print("SNAPSHOT_UNAVAILABLE"); fflush(stdout); exit(2)
        }
        totalBytes += data.count
        guard totalBytes <= 16_777_216, saved.setData(data, forType: type) else {
            print("SNAPSHOT_UNAVAILABLE"); fflush(stdout); exit(2)
        }
    }
    original.append(saved)
}
guard board.changeCount == initialCount else {
    print("SNAPSHOT_CHANGED"); fflush(stdout); exit(2)
}
var ownedCount: Int?
var changes = 0
defer {
    if let ownedCount, board.changeCount == ownedCount {
        board.clearContents()
        let written = original.isEmpty || board.writeObjects(original)
        let restored = board.pasteboardItems ?? []
        let matches = restored.count == original.count && zip(original, restored).allSatisfy { saved, current in
            saved.types.allSatisfy { current.data(forType: $0) == saved.data(forType: $0) }
        }
        let success = written && matches && verifyRestorationFromAnotherProcess(original)
        print(success ? "RESTORED" : "RESTORE_FAILED")
    } else {
        print(ownedCount == nil ? "UNCHANGED" : "PRESERVED_NEWER")
    }
    fflush(stdout)
}
print("READY"); fflush(stdout)
let mailbox = CommandMailbox()
DispatchQueue.global(qos: .userInitiated).async {
    while let command = readLine() { mailbox.append(command) }
    mailbox.append("END")
}
while true {
    guard let command = mailbox.next() else {
        // AppKit's pasteboard can supply promised representations through the
        // main run loop. Blocking it on stdin prevents another process fetching
        // rich data even though this process can read its own cached values.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        continue
    }
    if command == "END" { break }
    let fields = command.split(separator: " ", maxSplits: 1)
    guard fields.count == 2, fields[1].hasPrefix("AetherScreens-QA-"), command.utf8.count < 256,
          ["SET", "SET_RICH", "EXPECT_UPLOAD"].contains(String(fields[0])) else {
        print("INVALID_COMMAND"); fflush(stdout); continue
    }
    // Refuse to overwrite a copy made by the user during this test.
    guard board.changeCount == (ownedCount ?? initialCount) else {
        print("PRESERVED_NEWER"); fflush(stdout); break
    }
    let marker = String(fields[1])
    if fields[0] == "EXPECT_UPLOAD" {
        print("UPLOAD_READY"); fflush(stdout)
        let expected = richFlavors(marker)
        let deadline = Date(timeIntervalSinceNow: 8)
        var accepted = false
        while Date() < deadline {
            let observedCount = board.changeCount
            // Only claim this test's unique synthetic copy, including partial
            // representations, so failed uploads can still restore safely.
            let marked = board.string(forType: .string) == marker || expected.filter({ $0.0 != .png }).contains {
                board.data(forType: $0.0) == $0.1
            }
            if marked, board.changeCount == observedCount {
                ownedCount = observedCount
                accepted = expected.allSatisfy { board.data(forType: $0.0) == $0.1 }
                    && board.pasteboardItems?.count == 1
                    && board.data(forType: .png).flatMap(NSImage.init(data:)) != nil
                if accepted { break }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        print("UPLOAD_TYPES " + expected.map { "\($0.0.rawValue)=\(board.data(forType: $0.0) == $0.1 ? 1 : 0)" }.joined(separator: ","))
        print("UPLOAD_ITEMS \(board.pasteboardItems?.count ?? 0)")
        print(accepted ? "UPLOAD_VERIFIED" : "UPLOAD_REJECTED"); fflush(stdout)
        continue
    }
    board.clearContents()
    let written: Bool
    if fields[0] == "SET_RICH" {
        let flavors = richFlavors(marker)
        board.declareTypes(flavors.map { $0.0 }, owner: nil)
        written = flavors.allSatisfy { board.setData($0.1, forType: $0.0) }
    } else {
        written = board.setString(marker, forType: .string)
    }
    guard written else {
        ownedCount = board.changeCount
        print("WRITE_FAILED"); fflush(stdout); break
    }
    ownedCount = board.changeCount
    if fields[0] == "SET_RICH" {
        print("SOURCE_TYPES " + richFlavors(marker).map { "\($0.0.rawValue)=\(board.data(forType: $0.0) == $0.1 ? 1 : 0)" }.joined(separator: ","))
    }
    changes += 1
    print("CHANGED \(changes)"); fflush(stdout)
}
