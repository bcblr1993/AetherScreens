import Foundation

public struct FileTransferPresetLocation: Identifiable, Sendable, Equatable {
    public let id: String
    public let titleKey: String
    public let path: String
    public let systemIcon: String

    public init(id: String, titleKey: String, path: String, systemIcon: String) {
        self.id = id
        self.titleKey = titleKey
        self.path = path
        self.systemIcon = systemIcon
    }

    public static let desktop = FileTransferPresetLocation(
        id: "desktop",
        titleKey: "Desktop",
        path: "~/Desktop",
        systemIcon: "display"
    )

    public static let downloads = FileTransferPresetLocation(
        id: "downloads",
        titleKey: "Downloads",
        path: "~/Downloads",
        systemIcon: "arrow.down.circle"
    )

    public static let documents = FileTransferPresetLocation(
        id: "documents",
        titleKey: "Documents",
        path: "~/Documents",
        systemIcon: "doc.text"
    )

    public static let home = FileTransferPresetLocation(
        id: "home",
        titleKey: "Home Folder",
        path: "~",
        systemIcon: "house"
    )

    public static let applications = FileTransferPresetLocation(
        id: "applications",
        titleKey: "Applications",
        path: "/Applications",
        systemIcon: "app.badge"
    )

    public static let standardPresets: [FileTransferPresetLocation] = [
        .desktop,
        .downloads,
        .documents,
        .home,
        .applications
    ]
}

public final class FileTransferHistoryStore: @unchecked Sendable {
    public static let shared = FileTransferHistoryStore()

    private let userDefaults: UserDefaults
    private let maxHistoryItems: Int
    private let lock = NSLock()

    private static let uploadKey = "com.aethernative.aetherscreens.recent-upload-destinations"
    private static let downloadKey = "com.aethernative.aetherscreens.recent-download-paths"

    public init(userDefaults: UserDefaults = .standard, maxHistoryItems: Int = 8) {
        self.userDefaults = userDefaults
        self.maxHistoryItems = maxHistoryItems
    }

    public var recentUploadDestinations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.stringArray(forKey: Self.uploadKey) ?? []
    }

    public var recentDownloadPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.stringArray(forKey: Self.downloadKey) ?? []
    }

    public func recordUploadDestination(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var list = userDefaults.stringArray(forKey: Self.uploadKey) ?? []
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxHistoryItems {
            list = Array(list.prefix(maxHistoryItems))
        }
        userDefaults.set(list, forKey: Self.uploadKey)
    }

    public func recordDownloadPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        var list = userDefaults.stringArray(forKey: Self.downloadKey) ?? []
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        if list.count > maxHistoryItems {
            list = Array(list.prefix(maxHistoryItems))
        }
        userDefaults.set(list, forKey: Self.downloadKey)
    }

    public func clearRecentUploads() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.removeObject(forKey: Self.uploadKey)
    }

    public func clearRecentDownloads() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.removeObject(forKey: Self.downloadKey)
    }

    public static func combine(presetPath: String, filename: String) -> String {
        let trimmedPreset = presetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFile = filename.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFile.isEmpty else { return trimmedPreset }

        if trimmedPreset.hasSuffix("/") {
            return "\(trimmedPreset)\(trimmedFile)"
        } else {
            return "\(trimmedPreset)/\(trimmedFile)"
        }
    }
}
