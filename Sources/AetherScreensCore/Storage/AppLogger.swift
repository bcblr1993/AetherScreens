import Foundation
import os

/// Unified logging engine for AetherScreens combining Apple Unified OSLog with in-memory diagnostic buffer.
public final class AppLogger: ObservableObject, @unchecked Sendable {
    public static let shared = AppLogger()

    public enum LogLevel: String, Sendable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        public var icon: String {
            switch self {
            case .debug: return "gearshape"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    public struct LogEntry: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let level: LogLevel
        public let category: String
        public let message: String

        public init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            level: LogLevel,
            category: String,
            message: String
        ) {
            self.id = id
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
        }

        public var formattedTime: String {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return df.string(from: timestamp)
        }

        public var fullLine: String {
            "[\(formattedTime)] [\(level.rawValue)] [\(category)] \(message)"
        }
    }

    @Published public private(set) var entries: [LogEntry] = []
    private let lock = NSLock()
    private let maxEntries = 600

    private let osLogGeneral = os.Logger(subsystem: "com.aethernative.aetherscreens", category: "General")
    private let osLogRFB = os.Logger(subsystem: "com.aethernative.aetherscreens", category: "RFB")
    private let osLogNet = os.Logger(subsystem: "com.aethernative.aetherscreens", category: "Network")
    private let osLogAuth = os.Logger(subsystem: "com.aethernative.aetherscreens", category: "Auth")
    private let osLogUI = os.Logger(subsystem: "com.aethernative.aetherscreens", category: "UI")

    private init() {}

    private func logger(for category: String) -> os.Logger {
        switch category.lowercased() {
        case "rfb": return osLogRFB
        case "network", "net", "tailscale": return osLogNet
        case "auth", "crypto": return osLogAuth
        case "ui", "view": return osLogUI
        default: return osLogGeneral
        }
    }

    public func log(level: LogLevel, category: String = "General", message: String) {
        let entry = LogEntry(level: level, category: category, message: message)

        // 1. Log to Apple Unified Logging (Console.app & /usr/bin/log)
        let osLog = logger(for: category)
        switch level {
        case .debug:
            osLog.debug("[\(category)] \(message, privacy: .public)")
        case .info:
            osLog.info("[\(category)] \(message, privacy: .public)")
        case .warning:
            osLog.warning("[\(category)] \(message, privacy: .public)")
        case .error:
            osLog.error("[\(category)] \(message, privacy: .public)")
        }

        // 2. Append to in-memory buffer for in-app UI display
        lock.lock()
        if entries.count >= maxEntries {
            entries.removeFirst(entries.count - maxEntries + 1)
        }
        entries.append(entry)
        lock.unlock()

        Task { @MainActor in
            self.objectWillChange.send()
        }
    }

    public func info(_ message: String, category: String = "General") {
        log(level: .info, category: category, message: message)
    }

    public func debug(_ message: String, category: String = "General") {
        log(level: .debug, category: category, message: message)
    }

    public func warning(_ message: String, category: String = "General") {
        log(level: .warning, category: category, message: message)
    }

    public func error(_ message: String, category: String = "General") {
        log(level: .error, category: category, message: message)
    }

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        Task { @MainActor in
            self.objectWillChange.send()
        }
    }

    public func exportLogs() -> String {
        lock.lock()
        defer { lock.unlock() }
        return entries.map(\.fullLine).joined(separator: "\n")
    }
}
