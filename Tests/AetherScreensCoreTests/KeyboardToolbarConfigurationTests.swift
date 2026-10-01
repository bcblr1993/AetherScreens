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
