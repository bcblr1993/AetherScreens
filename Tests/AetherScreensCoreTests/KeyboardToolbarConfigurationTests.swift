import XCTest
@testable import AetherScreensCore

@MainActor
final class KeyboardToolbarConfigurationTests: XCTestCase {
    func testOptionalFunctionAndNavigationKeysMigrateHiddenAndPersistSelectionAndOrder() throws {
        var legacy = try JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: Data(#"{"size":"Small","position":"Top","items":[{"id":"00000000-0000-0000-0000-000000000001","action":"Cmd","isVisible":false}]}"#.utf8))
        legacy.normalize()
        let optional = legacy.items.filter { KeyboardToolbarConfiguration.Action.optionalKeys.contains($0.action) }
        XCTAssertEqual(optional.count, 16)
        XCTAssertTrue(optional.allSatisfy { !$0.isVisible })
        XCTAssertFalse(legacy.items.first!.isVisible)
        XCTAssertTrue(try XCTUnwrap(legacy.items.first { $0.action == .userPassword }).isVisible)
        let f12 = try XCTUnwrap(legacy.items.firstIndex { $0.action == .f12 })
        legacy.items[f12].isVisible = true
        let id = legacy.items[f12].id
        legacy.move(id, by: -1)
        let (store, defaults) = makeStore()
        let device = UUID()
        store.save(legacy, for: device)
        let loaded = KeyboardToolbarStore(defaults: defaults).load(for: device)
        XCTAssertEqual(loaded.items.map(\.action), legacy.items.map(\.action))
        XCTAssertTrue(try XCTUnwrap(loaded.items.first { $0.action == .f12 }).isVisible)
        legacy.resetToolbar()
        XCTAssertTrue(legacy.items.filter { KeyboardToolbarConfiguration.Action.optionalKeys.contains($0.action) }.allSatisfy { !$0.isVisible })
    }

    func testHardwareRepeatSettingsPersistPerComputerWithoutResettingWithToolbar() throws {
        let (store, defaults) = makeStore()
        let id = UUID()
        var configuration = KeyboardToolbarConfiguration()
        var hardware = HardwareKeyboardConfiguration()
        hardware.swapCommandControl = true
        hardware.commandBackslashSwitchesApps = true
        hardware.repeatEnabled = false
        hardware.repeatDelay = 1
        hardware.repeatInterval = 0.1
        configuration.hardwareKeyboard = hardware
        configuration.resetToolbar()
        store.save(configuration, for: id)
        XCTAssertEqual(KeyboardToolbarStore(defaults: defaults).load(for: id).hardwareKeyboard, hardware)
        XCTAssertNil(store.load(for: UUID()).hardwareKeyboard)
        let legacy = try JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: Data(#"{"size":"Small","position":"Top","items":[]}"#.utf8))
        XCTAssertNil(legacy.hardwareKeyboard)
        let priorHardware = try JSONDecoder().decode(HardwareKeyboardConfiguration.self,
            from: Data(#"{"repeatEnabled":false,"repeatDelay":1,"repeatInterval":0.1}"#.utf8))
        XCTAssertNil(priorHardware.swapCommandControl)
        XCTAssertNil(priorHardware.commandBackslashSwitchesApps)
        XCTAssertFalse(priorHardware.repeatEnabled)
    }

    func testLegacyAndUnknownPencilSettingsKeepToolbarAndDisableUnrecognizedActions() throws {
        let legacy = try JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: Data(#"{"size":"Small","position":"Top","items":[]}"#.utf8))
        XCTAssertEqual(legacy.size, .small)
        XCTAssertEqual(legacy.pencilAction(for: .doubleTap), .none)
        XCTAssertEqual(legacy.pencilAction(for: .squeeze), .none)
        let future = try JSONDecoder().decode(KeyboardToolbarConfiguration.self, from: Data(#"{"size":"Large","position":"Bottom","items":[],"pencilDoubleTapAction":"Future Action","pencilSqueezeAction":"Secondary Click"}"#.utf8))
        XCTAssertEqual(future.size, .large)
        XCTAssertEqual(future.pencilAction(for: .doubleTap), .none)
        XCTAssertEqual(future.pencilAction(for: .squeeze), .secondaryClick)
    }

    func testPencilSettingsPersistPerComputerAndToolbarResetPreservesThem() {
        let (store, defaults) = makeStore()
        let device = UUID()
        var configuration = KeyboardToolbarConfiguration()
        configuration.size = .large
        configuration.pencilDoubleTapAction = .secondaryClick
        configuration.pencilSqueezeAction = .toggleToolbar
        store.save(configuration, for: device)
        let relaunched = KeyboardToolbarStore(defaults: defaults).load(for: device)
        XCTAssertEqual(relaunched.pencilAction(for: .doubleTap), .secondaryClick)
        XCTAssertEqual(relaunched.pencilAction(for: .squeeze), .toggleToolbar)
        XCTAssertEqual(store.load(for: UUID()).pencilAction(for: .doubleTap), .none)
        configuration.resetToolbar()
        XCTAssertEqual(configuration.size, .medium)
        XCTAssertEqual(configuration.pencilAction(for: .doubleTap), .secondaryClick)
        XCTAssertEqual(configuration.pencilAction(for: .squeeze), .toggleToolbar)
    }

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
        let session = TestSession.make(device: device, password: nil, isTemporary: true, keyboardStore: store)
        session.keyboardConfiguration.position = .top
        session.keyboardConfiguration.size = .large
        XCTAssertEqual(store.load(for: device.id).position, .bottom)
        let saved = TestSession.make(device: device, password: nil, keyboardStore: store)
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
