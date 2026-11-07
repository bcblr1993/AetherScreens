import Foundation
import Combine

/// A reusable command or text snippet that can be sent to a remote session with one tap.
public struct QuickSnippet: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var content: String
    public var appendReturn: Bool

    public init(id: UUID = UUID(), title: String, content: String, appendReturn: Bool = true) {
        self.id = id
        self.title = title
        self.content = content
        self.appendReturn = appendReturn
    }
}

/// Persistent store for user-defined quick text/command snippets.
@MainActor
public final class QuickSnippetStore: ObservableObject {
    public static let shared = QuickSnippetStore()

    @Published public private(set) var snippets: [QuickSnippet] = []

    private let defaults: UserDefaults
    private let storageKey = "com.aetherscreens.quickSnippets.v1"

    public init(defaults: UserDefaults = .standard, seedDefaultsIfEmpty: Bool = true) {
        self.defaults = defaults
        load(seedDefaultsIfEmpty: seedDefaultsIfEmpty)
    }

    public func add(_ snippet: QuickSnippet) {
        let trimmedTitle = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !snippet.content.isEmpty else { return }
        let normalized = QuickSnippet(
            id: snippet.id,
            title: trimmedTitle,
            content: snippet.content,
            appendReturn: snippet.appendReturn
        )
        snippets.append(normalized)
        save()
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    private func load(seedDefaultsIfEmpty: Bool) {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([QuickSnippet].self, from: data) {
            self.snippets = decoded
            return
        }
        if seedDefaultsIfEmpty {
            self.snippets = [
                QuickSnippet(title: "System Uptime", content: "uptime", appendReturn: true),
                QuickSnippet(title: "Disk Usage (df -h)", content: "df -h", appendReturn: true),
                QuickSnippet(title: "Docker Containers", content: "docker ps", appendReturn: true)
            ]
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
