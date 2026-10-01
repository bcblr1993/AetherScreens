import Foundation
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: return AppLocalization.string("Follow System")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

/// Shared by the interface and asynchronous connection errors.
public enum AppLocalization {
    public static let preferenceKey = "com.aethernative.aetherscreens.language"
    private static let lock = NSLock()
    private static var selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system

    public static var language: AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return selection
    }

    static func select(_ language: AppLanguage) {
        lock.lock()
        selection = language
        lock.unlock()
    }

    public static func identifier(for language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if language != .system { return language.rawValue }
        for preferred in preferredLanguages {
            let code = preferred.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if code == "zh" { return "zh-Hans" }
            if code == "en" { return "en" }
        }
        return "en"
    }

    public static func string(_ key: String, language: AppLanguage? = nil) -> String {
        let code = identifier(for: language ?? self.language)
        guard let directory = localizationDirectory(for: code),
              let bundle = Bundle(url: directory) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale(identifier: identifier(for: language)), arguments: arguments)
    }

    /// Stored messages stay in their original form so switching language can redraw existing notices.
    public static func message(_ original: String) -> String {
        guard identifier(for: language) == "zh-Hans" else { return original }
        let translated = string(original)
        if translated != original { return translated }
        let source = original as NSString
        for template in messageTemplates {
            guard let match = template.regex.firstMatch(in: original, range: NSRange(location: 0, length: source.length)) else { continue }
            var values: [CVarArg] = []
            for (index, kind) in template.kinds.enumerated() {
                let value = source.substring(with: match.range(at: index + 1))
                if kind == "@" { values.append(value) }
                else if kind == "d" { values.append(Int(value) ?? 0) }
                else { values.append(Double(value) ?? 0) }
            }
            return String(format: string(template.key), locale: Locale(identifier: "zh-Hans"), arguments: values)
        }
        return original
    }

    // SwiftPM's native build lowercases language directories; Xcode preserves
    // BCP-47 casing. Resource lookup must support both independently of the OS
    // preferred language and Foundation's localized path search.
    static func localizationDirectory(for language: String) -> URL? {
        localizationDirectories[language.lowercased()]
    }

    private static let localizationDirectories: [String: URL] = {
        guard let root = Bundle.module.resourceURL,
              let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [:] }
        return entries.reduce(into: [:]) { result, url in
            guard url.pathExtension.lowercased() == "lproj" else { return }
            result[url.deletingPathExtension().lastPathComponent.lowercased()] = url
        }
    }()

    private struct MessageTemplate {
        let key: String
        let regex: NSRegularExpression
        let kinds: [String]
    }

    private static let messageTemplates: [MessageTemplate] = {
        guard let directory = localizationDirectory(for: "en"),
              let data = try? Data(contentsOf: directory.appendingPathComponent("Localizable.strings")),
              let entries = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let tokens = try? NSRegularExpression(pattern: "%(@|d|\\.\\df)") else { return [] }
        return entries.keys.sorted { $0.count > $1.count }.compactMap { key in
            let source = key as NSString
            let matches = tokens.matches(in: key, range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else { return nil }
            var pattern = "^", cursor = 0, kinds: [String] = []
            for match in matches {
                let literal = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)).replacingOccurrences(of: "%%", with: "%")
                pattern += NSRegularExpression.escapedPattern(for: literal)
                let kind = source.substring(with: match.range(at: 1))
                kinds.append(kind)
                pattern += kind == "@" ? "(.*)" : "([-+]?[0-9]+(?:\\.[0-9]+)?)"
                cursor = NSMaxRange(match.range)
            }
            pattern += NSRegularExpression.escapedPattern(for: source.substring(from: cursor).replacingOccurrences(of: "%%", with: "%")) + "$"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return nil }
            return MessageTemplate(key: key, regex: regex, kinds: kinds)
        }
    }()
}

@MainActor
public final class AppLanguageSettings: ObservableObject {
    public static let shared = AppLanguageSettings()
    private let defaults: UserDefaults
    @Published public var language: AppLanguage {
        didSet {
            AppLocalization.select(language)
            defaults.set(language.rawValue, forKey: AppLocalization.preferenceKey)
        }
    }
    public var locale: Locale { Locale(identifier: AppLocalization.identifier(for: language)) }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = AppLanguage(rawValue: defaults.string(forKey: AppLocalization.preferenceKey) ?? "system") ?? .system
        AppLocalization.select(language)
    }
}
