import Foundation

/// Opt-in input-path evidence. This schema cannot contain key values, text,
/// credentials, clipboard data, pointer coordinates or remote identities.
final class InputDiagnostics: @unchecked Sendable {
    enum Stage: String, Codable, Sendable {
        case collectorStarted, clientCreated, connectionStarted, connectionReady, connectionFailed, connectionClosed
        case tapContact, tapRecognized, tapSuppressed
        case inputGateChanged, pointerGateChanged
        case pointerSuppressed, pointerDropped, pointerQueued, pointerProcessed, pointerFailed
        case returnSuppressed, returnDropped, returnQueued, returnProcessed, returnFailed
        case textSubmission, textSubmissionSuppressed, appleStatus
        case appleDisplayLayoutReceived, appleDisplaySelectionRequested, appleDisplaySelectionConfirmed, appleDisplaySelectionFailed
    }

    struct Flags: OptionSet, Sendable {
        let rawValue: UInt16
        static let inputEnabled = Self(rawValue: 1)
        static let pointerEnabled = Self(rawValue: 2)
        static let connectionPresent = Self(rawValue: 4)
        static let notClosing = Self(rawValue: 8)
        static let foreground = Self(rawValue: 16)
        static let observeOnly = Self(rawValue: 32)
        static let localNavigation = Self(rawValue: 64)
        static let trackpad = Self(rawValue: 128)
        static let directTouch = Self(rawValue: 256)
        static let connected = Self(rawValue: 512)
        static let displaySwitchPending = Self(rawValue: 1024)
    }

    struct Record: Codable, Sendable {
        let sequence: UInt64
        let uptime: TimeInterval
        let session: UUID
        let stage: Stage
        let flags: UInt16
        let buttons: UInt8?
        let down: Bool?
        let appleFlags: UInt16?
        let appleCommand: UInt16?
    }

    struct Snapshot: Codable, Sendable {
        let schema: Int
        let records: [Record]
    }

    static let relativePath = "Library/Caches/AetherScreensInputDiagnostics/input-v1.json"
    /// Present only in a separately signed development diagnostic package.
    /// Ordinary app packages omit this key and still require launch opt-in.
    static let bundleOptInKey = "AetherScreensDevelopmentInputDiagnostics"
    static let enabled = makeEnabled(environment: ProcessInfo.processInfo.environment,
                                     caches: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                                     bundleOptIn: Bundle.main.object(forInfoDictionaryKey: bundleOptInKey) as? Bool == true)

    static func makeEnabled(environment: [String: String], caches: URL?, bundleOptIn: Bool = false) -> InputDiagnostics? {
        guard bundleOptIn || environment["AETHERSCREENS_INPUT_DIAGNOSTICS"] == "1", let caches else { return nil }
        let recorder = InputDiagnostics(fileURL: caches.appendingPathComponent("AetherScreensInputDiagnostics/input-v1.json"))
        recorder.record(.collectorStarted, session: UUID())
        return recorder
    }

    private let fileURL: URL
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "com.aethernative.aetherscreens.input-diagnostics", qos: .utility)
    private var records: [Record] = []
    private var nextSequence: UInt64 = 0
    private var writeScheduled = false
    private let limit = 128

    init(fileURL: URL) { self.fileURL = fileURL }

    func record(_ stage: Stage, session: UUID, flags: Flags = [], buttons: UInt8? = nil,
                down: Bool? = nil, appleFlags: UInt16? = nil, appleCommand: UInt16? = nil) {
        lock.lock()
        nextSequence &+= 1
        records.append(Record(sequence: nextSequence, uptime: ProcessInfo.processInfo.systemUptime,
                              session: session, stage: stage, flags: flags.rawValue,
                              buttons: buttons.map { $0 & 7 }, down: down,
                              appleFlags: appleFlags, appleCommand: appleCommand))
        if records.count > limit { records.removeFirst(records.count - limit) }
        let schedule = !writeScheduled
        writeScheduled = true
        lock.unlock()
        if schedule {
            writer.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.persistLatest() }
        }
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(schema: 1, records: records)
    }

    /// Used by controlled tests to wait for the same serialized writer.
    func flush() async {
        await withCheckedContinuation { continuation in
            writer.async { [self] in
                persistLatest()
                continuation.resume()
            }
        }
    }

    private func persistLatest() {
        lock.lock()
        let value = Snapshot(schema: 1, records: records)
        writeScheduled = false
        lock.unlock()
        // Storage failure must never change remote input or invoke a UI prompt.
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: fileURL, options: .atomic)
        } catch { }
    }
}
