import XCTest
@testable import AetherScreensCore

@MainActor
final class KeyboardToolbarConfigurationTests: XCTestCase {
    private func makeStore() -> (KeyboardToolbarStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "qa.keyboard.\(UUID().uuidString)")!
        return (KeyboardToolbarStore(defaults: defaults), defaults)
    }
    func testPerComputerOrderVisibilitySizingAndSpacersPersist() {
        let (store, defaults) = makeStore()
        let first = UUID(), second = UUID()
        var configuration = KeyboardToolbarConfiguration()
        configuration.size = .large
        configuration.position = .top
        let id = configuration.items[1].id
        configuration.move(id, by: -1)
        configuration.items[0].isVisible = false
        configuration.items.append(.init(action: .spacer))
        store.save(configuration, for: first)
        let relaunched = KeyboardToolbarStore(defaults: defaults)
        XCTAssertEqual(relaunched.load(for: first), configuration)
        XCTAssertEqual(relaunched.load(for: second).size, .medium)
        XCTAssertEqual(relaunched.load(for: second).position, .bottom)
        XCTAssertEqual(configuration.items.filter { $0.action == .spacer }.count, 4)
    }
    func testFloatingPositionPersistsWithoutChangingOtherComputerPreferences() {
        let (store, defaults) = makeStore()
        let first = UUID(), second = UUID()
        var configuration = KeyboardToolbarConfiguration()
        configuration.position = .floating
        store.save(configuration, for: first)
        XCTAssertEqual(KeyboardToolbarStore(defaults: defaults).load(for: first), configuration)
        XCTAssertEqual(store.load(for: second).position, .bottom)
    }

    func testRepeatSettingsPersistPerComputerAndLegacySettingsRetainLayout() throws {
        let (store, defaults) = makeStore()
        let first = UUID(), second = UUID()
        var configuration = KeyboardToolbarConfiguration()
        configuration.size = .small
        configuration.position = .top
        configuration.items[0].isVisible = false
        for mode in KeyboardToolbarConfiguration.KeyRepeat.allCases {
            configuration.keyRepeat = mode
            store.save(configuration, for: first)
            XCTAssertEqual(KeyboardToolbarStore(defaults: defaults).load(for: first), configuration)
            XCTAssertEqual(store.load(for: second).keyRepeat, .normal)
        }
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any])
        legacy.removeValue(forKey: "keyRepeat")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: KeyboardToolbarStore.keyPrefix + first.uuidString)
        configuration.keyRepeat = .normal
        XCTAssertEqual(store.load(for: first), configuration, "Adding repeat must preserve existing order, IDs, hidden controls, size and position")
    }

    func testCarouselPositionPersistsWithoutChangingOtherComputerPreferences() {
        let (store, defaults) = makeStore()
        let first = UUID(), second = UUID()
        var configuration = KeyboardToolbarConfiguration()
        configuration.position = .carousel
        configuration.keyRepeat = .fast
        store.save(configuration, for: first)
        XCTAssertEqual(KeyboardToolbarStore(defaults: defaults).load(for: first), configuration)
        XCTAssertEqual(store.load(for: second).position, .bottom)
    }

    func testCorruptConfigurationFallsBackAndDuplicateButtonsAreNormalized() {
        let (store, defaults) = makeStore()
        let id = UUID()
        defaults.set(Data("invalid".utf8), forKey: KeyboardToolbarStore.keyPrefix + id.uuidString)
        XCTAssertEqual(store.load(for: id).items.first?.action, .actions)
        var config = KeyboardToolbarConfiguration()
        config.items = [.init(action: .paste, isVisible: false), .init(action: .paste), .init(action: .spacer), .init(action: .spacer)]
        config.normalize()
        XCTAssertEqual(config.items.filter { $0.action == .paste }.count, 1)
        XCTAssertEqual(config.items.filter { $0.action == .spacer }.count, 2)
        XCTAssertFalse(config.items[0].isVisible)
        XCTAssertEqual(Set(config.items.map(\.action)), Set(KeyboardToolbarConfiguration.Action.allCases))
        let original = config
        config.move(config.items[0].id, by: -1)
        config.move(UUID(), by: 1)
        XCTAssertEqual(config, original)
    }
    func testLegacyConfigurationGainsOptionalNavigationKeysWithoutChangingExistingLayout() throws {
        let (store, defaults) = makeStore()
        let id = UUID()
        let navigation: Set<KeyboardToolbarConfiguration.Action> = [.home, .end, .pageUp, .pageDown]
        var legacy = KeyboardToolbarConfiguration()
        legacy.items.removeAll { navigation.contains($0.action) }
        legacy.position = .top
        legacy.size = .small
        legacy.items[0].isVisible = false
        legacy.move(legacy.items[1].id, by: -1)
        defaults.set(try JSONEncoder().encode(legacy), forKey: KeyboardToolbarStore.keyPrefix + id.uuidString)
        var upgraded = store.load(for: id)
        XCTAssertEqual(Array(upgraded.items.prefix(legacy.items.count)), legacy.items)
        XCTAssertEqual(upgraded.position, .top)
        XCTAssertEqual(upgraded.size, .small)
        XCTAssertEqual(Set(upgraded.items.suffix(4).map(\.action)), navigation)
        XCTAssertTrue(upgraded.items.suffix(4).allSatisfy { !$0.isVisible })
        XCTAssertTrue(KeyboardToolbarConfiguration().items.filter { navigation.contains($0.action) }.allSatisfy { !$0.isVisible })
        let pageDown = try XCTUnwrap(upgraded.items.firstIndex { $0.action == .pageDown })
        upgraded.items[pageDown].isVisible = true
        let pageID = upgraded.items[pageDown].id
        upgraded.move(pageID, by: -1)
        store.save(upgraded, for: id)
        XCTAssertEqual(store.load(for: id), upgraded, "Selected navigation keys and their order must survive relaunch")
    }

    func testTemporarySessionCustomizationDoesNotPersist() {
        let (store, _) = makeStore()
        let device = RemoteDevice(name: "Temporary", host: "127.0.0.1")
        let session = SessionViewModel(device: device, password: nil, isTemporary: true, keyboardStore: store)
        session.keyboardConfiguration.position = .top
        session.keyboardConfiguration.size = .large
        XCTAssertEqual(store.load(for: device.id).position, .bottom)
        let saved = SessionViewModel(device: device, password: nil, keyboardStore: store)
        saved.cycleCmd()
        saved.cycleCmd()
        XCTAssertEqual(saved.cmdState, .locked)
        let commandIndex = saved.keyboardConfiguration.items.firstIndex { $0.action == .command }!
        saved.keyboardConfiguration.items[commandIndex].isVisible = false
        XCTAssertEqual(saved.cmdState, .inactive, "Hiding a modifier releases its held remote key")
        saved.keyboardConfiguration.position = .top
        XCTAssertEqual(store.load(for: device.id).position, .top)
        XCTAssertEqual(store.load(for: device.id).size, .medium)
    }
}
