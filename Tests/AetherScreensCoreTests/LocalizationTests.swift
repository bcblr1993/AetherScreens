import XCTest
@testable import AetherScreensCore

final class LocalizationTests: XCTestCase {
    func testLanguageFallbackSelectsFirstSupportedPreference() {
        XCTAssertEqual(AppLocalization.identifier(for: .system, preferredLanguages: ["fr-FR", "zh-Hant-TW", "en-US"]), "zh-Hans")
        XCTAssertEqual(AppLocalization.identifier(for: .system, preferredLanguages: ["en-GB", "zh-Hans"]), "en")
        XCTAssertEqual(AppLocalization.identifier(for: .system, preferredLanguages: ["de-DE"]), "en")
        XCTAssertEqual(AppLocalization.identifier(for: .english, preferredLanguages: ["zh-Hans"]), "en")
    }

    func testBothTranslationResourcesAreAvailable() {
        XCTAssertEqual(AppLocalization.string("Quick Connect", language: .simplifiedChinese), "快速连接")
        XCTAssertEqual(AppLocalization.string("Quick Connect", language: .english), "Quick Connect")
        XCTAssertEqual(AppLocalization.string("Mac Account Password", language: .simplifiedChinese), "Mac 账户密码")
        XCTAssertEqual(AppLocalization.string("unknown server data", language: .simplifiedChinese), "unknown server data")
    }

    func testCatalogKeysAndFormatArgumentsMatch() throws {
        func catalog(_ language: String) throws -> [String: String] {
            let directory = try XCTUnwrap(AppLocalization.localizationDirectory(for: language))
            let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try catalog("en"), chinese = try catalog("zh-Hans")
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let tokens = try NSRegularExpression(pattern: "%(@|d|\\.\\df)")
        for (key, value) in english {
            let translated = try XCTUnwrap(chinese[key])
            XCTAssertFalse(translated.isEmpty, key)
            func arguments(_ text: String) -> [String] {
                let source = text as NSString
                return tokens.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range) }
            }
            XCTAssertEqual(arguments(value), arguments(translated), "Format mismatch: \(key)")
        }
    }

    func testStoredMessagesRedrawWithoutChangingServerDetails() {
        let previous = AppLocalization.language
        defer { AppLocalization.select(previous) }
        AppLocalization.select(.simplifiedChinese)
        XCTAssertEqual(AppLocalization.message("Synced 12 nodes from Tailscale"), "已从 Tailscale 同步 12 个节点")
        XCTAssertEqual(AppLocalization.message("Socket read error: original reason"), "读取连接数据失败：original reason")
        XCTAssertEqual(AppLocalization.message("Tailscale HTTP 401: original reason"), "Tailscale HTTP 错误 401：original reason")
        XCTAssertEqual(AppLocalization.message("Remote host closed connection (received 4/8 bytes)"), "远端主机已关闭连接（已接收 4/8 字节）")
        XCTAssertEqual(AppLocalization.message("Unsupported framebuffer encoding: 2147483646"), "不支持的画面编码：2147483646")
        XCTAssertEqual(AppLocalization.message("Unsupported server message type: 126"), "不支持的服务器消息类型：126")
        XCTAssertTrue(AppLocalization.message("Connection timed out. Check the address, Screen Sharing and your LAN or Tailscale connection. Allow AetherScreens in System Settings > Privacy & Security > Local Network.").contains("系统设置"))
        XCTAssertTrue(AppLocalization.message("Connection timed out. Check the address, Screen Sharing and your LAN or Tailscale connection. Allow AetherScreens in Settings > Privacy & Security > Local Network.").contains("“设置”"))
        AppLocalization.select(.english)
        XCTAssertEqual(AppLocalization.message("Synced 12 nodes from Tailscale"), "Synced 12 nodes from Tailscale")
        XCTAssertEqual(AppLocalization.message("Unsupported framebuffer encoding: 2147483646"), "Unsupported framebuffer encoding: 2147483646")
        XCTAssertEqual(AppLocalization.message("Unsupported server message type: 126"), "Unsupported server message type: 126")
    }

    @MainActor
    func testManualSelectionPersistsAcrossSettingsInstances() throws {
        let previous = AppLocalization.language
        let suite = "test.aetherscreens.language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); AppLocalization.select(previous) }
        let settings = AppLanguageSettings(defaults: defaults)
        settings.language = .simplifiedChinese
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .simplifiedChinese)
        settings.language = .english
        XCTAssertEqual(settings.locale.language.languageCode?.identifier, "en")
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .english)
    }

    @MainActor
    func testManualSelectionOverridesInitialLaunchLanguage() async throws {
        let previous = AppLocalization.language
        let suite = "test.aetherscreens.language-launch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            defaults.removePersistentDomain(forName: suite)
            AppLocalization.select(previous)
        }
        defaults.setVolatileDomain([
            AppLocalization.preferenceKey: AppLanguage.simplifiedChinese.rawValue,
            "qa.unrelated-launch-option": "preserved"
        ], forName: UserDefaults.argumentDomain)
        let settings = AppLanguageSettings(defaults: defaults)
        XCTAssertEqual(settings.language, .simplifiedChinese)

        settings.language = .english
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(settings.language, .english, "Preference notifications must retain the manual selection")
        XCTAssertEqual(AppLocalization.language, .english)
        XCTAssertEqual(defaults.string(forKey: AppLocalization.preferenceKey), "en")
        XCTAssertEqual(defaults.string(forKey: "qa.unrelated-launch-option"), "preserved")
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        XCTAssertEqual(AppLanguageSettings(defaults: defaults).language, .english, "The selection must survive relaunch without arguments")
    }
}
