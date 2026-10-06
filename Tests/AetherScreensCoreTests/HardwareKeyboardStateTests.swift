import XCTest
@testable import AetherScreensCore

final class HardwareKeyboardStateTests: XCTestCase {
    func testPhysicalMappingRetainsHeldKeysAcrossPreferenceChangesAndBalancesDuplicates() {
        var mapping = HardwareKeyboardMapping()
        var config = HardwareKeyboardConfiguration()
        config.swapCommandControl = true
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.commandLeft, configuration: config), MacKeyMap.controlLeft)
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.controlRight, configuration: config), MacKeyMap.commandRight)
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.commandRight, configuration: config), MacKeyMap.controlRight)
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.controlLeft, configuration: config), MacKeyMap.commandLeft)
        XCTAssertEqual(mapping.event(down: false, key: MacKeyMap.commandRight, configuration: config), MacKeyMap.controlRight)
        XCTAssertEqual(mapping.event(down: false, key: MacKeyMap.controlLeft, configuration: config), MacKeyMap.commandLeft)
        config.swapCommandControl = false
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.commandLeft, configuration: config), MacKeyMap.controlLeft)
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.controlLeft, configuration: config), MacKeyMap.controlLeft)
        XCTAssertNil(mapping.event(down: false, key: MacKeyMap.commandLeft, configuration: config))
        XCTAssertEqual(mapping.event(down: false, key: MacKeyMap.controlLeft, configuration: config), MacKeyMap.controlLeft)
        XCTAssertEqual(mapping.event(down: false, key: MacKeyMap.controlRight, configuration: config), MacKeyMap.commandRight)
        XCTAssertNil(mapping.event(down: false, key: MacKeyMap.controlRight, configuration: config))
        XCTAssertTrue(mapping.releaseAll().isEmpty)
    }

    func testAlternateAppSwitchRequiresEffectiveCommandAndReleasesKeysBeforeModifiers() {
        var mapping = HardwareKeyboardMapping()
        var config = HardwareKeyboardConfiguration()
        config.commandBackslashSwitchesApps = true
        XCTAssertEqual(mapping.event(down: true, key: 0x5C, configuration: config), 0x5C)
        XCTAssertEqual(mapping.event(down: false, key: 0x5C, configuration: config), 0x5C)
        config.swapCommandControl = true
        XCTAssertEqual(mapping.event(down: true, key: MacKeyMap.controlLeft, configuration: config), MacKeyMap.commandLeft)
        XCTAssertEqual(mapping.event(down: true, key: 0x5C, configuration: config), MacKeyMap.tab)
        config.commandBackslashSwitchesApps = false
        XCTAssertEqual(mapping.event(down: true, key: 0x5C, configuration: config), MacKeyMap.tab)
        XCTAssertEqual(mapping.releaseAll(), [MacKeyMap.tab, MacKeyMap.commandLeft])
        XCTAssertTrue(mapping.releaseAll().isEmpty)
        XCTAssertNil(mapping.event(down: false, key: 0x5C, configuration: config))
    }

    func testRepeatDelayIntervalNoBurstAndRelease() {
        let state = HardwareKeyboardState()
        var downs = 0
        state.onKeyEvent = { down, _ in if down { downs += 1 } }
        state.press(usage: 0x50, characters: "", at: 10)
        state.advanceRepeat(at: 10.49)
        XCTAssertEqual(downs, 1)
        state.advanceRepeat(at: 10.5)
        state.advanceRepeat(at: 10.54)
        XCTAssertEqual(downs, 2)
        state.advanceRepeat(at: 100)
        XCTAssertEqual(downs, 3, "A delayed UI tick must not flood buffered repeats")
        state.advanceRepeat(at: 100)
        XCTAssertEqual(downs, 3)
        state.release(usage: 0x50)
        state.advanceRepeat(at: 200)
        XCTAssertEqual(downs, 3)
    }

    func testNativeRepeatModifiersConfigurationAndCancellation() {
        let state = HardwareKeyboardState()
        var downs = 0
        state.onKeyEvent = { down, _ in if down { downs += 1 } }
        state.press(usage: 0xE3, characters: "", at: 0)
        state.advanceRepeat(at: 10)
        XCTAssertEqual(downs, 1)
        state.press(usage: 4, characters: "a", at: 10)
        state.press(usage: 4, characters: "A", at: 10.1)
        state.advanceRepeat(at: 20)
        XCTAssertEqual(downs, 3, "Native repeats disable timer repeats for this hold")
        state.releaseAll()
        state.press(usage: 4, characters: "a", at: 30)
        state.configuration.repeatEnabled = false
        state.advanceRepeat(at: 40)
        XCTAssertEqual(downs, 4)
        state.configuration.repeatEnabled = true
        state.releaseAll()
        state.advanceRepeat(at: 50)
        XCTAssertEqual(downs, 4)
        state.configuration.repeatDelay = -.infinity
        state.configuration.repeatInterval = 0
        XCTAssertEqual(state.configuration.validatedDelay, 0.5)
        XCTAssertEqual(state.configuration.validatedInterval, 0.03)
    }

    func testLayoutCharactersAndSpecialHIDKeys() {
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 4, characters: "q"), 113)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 4, characters: "中"), 0x01004E2D)
        XCTAssertNil(HardwareKeyboardState.keySym(usage: 4, characters: ""))
        XCTAssertNil(HardwareKeyboardState.keySym(usage: 4, characters: "ab"))
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x2A, characters: ""), MacKeyMap.backspace)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x4C, characters: ""), MacKeyMap.delete)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x58, characters: ""), MacKeyMap.return)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x3A, characters: ""), MacKeyMap.f1)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x45, characters: ""), MacKeyMap.f12)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0x68, characters: ""), MacKeyMap.f12 + 1)
        XCTAssertEqual(HardwareKeyboardState.keySym(usage: 0xE7, characters: ""), MacKeyMap.commandRight)
    }

    func testRepeatsRetainOriginalKeyAndCancellationReleasesKeysBeforeModifiers() {
        let state = HardwareKeyboardState()
        var events: [(Bool, UInt32)] = []
        state.onKeyEvent = { events.append(($0, $1)) }
        XCTAssertTrue(state.press(usage: 0xE3, characters: ""))
        XCTAssertTrue(state.press(usage: 4, characters: "q"))
        XCTAssertTrue(state.press(usage: 4, characters: "Q"))
        state.releaseAll()
        XCTAssertEqual(events.map { $0.0 }, [true, true, true, false, false])
        XCTAssertEqual(events.map { $0.1 }, [MacKeyMap.commandLeft, 113, 113, 113, MacKeyMap.commandLeft])
        state.releaseAll()
        XCTAssertEqual(events.count, 5)
        XCTAssertFalse(state.release(usage: 4))
    }

    func testDuplicateKeyOwnersAndUnsupportedEvents() {
        let state = HardwareKeyboardState()
        var releases: [UInt32] = []
        state.onKeyEvent = { if !$0 { releases.append($1) } }
        XCTAssertTrue(state.press(usage: 0x28, characters: ""))
        XCTAssertTrue(state.press(usage: 0x58, characters: ""))
        XCTAssertTrue(state.release(usage: 0x28))
        XCTAssertTrue(releases.isEmpty)
        XCTAssertTrue(state.release(usage: 0x58))
        XCTAssertEqual(releases, [MacKeyMap.return])
        XCTAssertFalse(state.press(usage: 0, characters: ""))
    }
}
