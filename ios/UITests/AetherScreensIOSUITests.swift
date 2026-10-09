import XCTest
import UIKit

final class AetherScreensIOSUITests: XCTestCase {
    func testControlledSSHSettings() throws { try verifyControlledSSHSettings(language: "en") }
    func testChineseControlledSSHSettings() throws { try verifyControlledSSHSettings(language: "zh-Hans") }

    func testControlledSSHKeyImportSelection() throws { try verifyControlledSSHSettings(language: "en", checkKeyImport: true) }
    func testChineseControlledSSHKeyImportSelection() throws { try verifyControlledSSHSettings(language: "zh-Hans", checkKeyImport: true) }
    func testControlledSSHKeyReuse() throws { try verifyControlledSSHSettings(language: "en", checkSavedKey: true) }
    func testChineseControlledSSHKeyReuse() throws { try verifyControlledSSHSettings(language: "zh-Hans", checkSavedKey: true) }

    func testControlledSSHKeyLibrary() throws { try verifyControlledSSHKeyLibrary(language: "en") }
    func testChineseControlledSSHKeyLibrary() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans") }

    func testControlledSSHKeyReusePaste() throws { try verifyControlledSSHKeyPaste(language: "en", invalid: false) }
    func testChineseControlledSSHKeyReusePaste() throws { try verifyControlledSSHKeyPaste(language: "zh-Hans", invalid: false) }
    func testControlledSSHKeyReuseInvalidPaste() throws { try verifyControlledSSHKeyPaste(language: "en", invalid: true) }
    func testChineseControlledSSHKeyReuseInvalidPaste() throws { try verifyControlledSSHKeyPaste(language: "zh-Hans", invalid: true) }

    private func verifyControlledSSHKeyPaste(language: String, invalid: Bool) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires owned controlled simulator") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        let token = UUID().uuidString
        app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_TOKEN"] = token
        app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = invalid ? "seed-invalid-paste" : "seed-paste"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "AETHERSCREENS_SSH_KEY_QA_ACTION")
        defer {
            app.terminate()
            app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = "cleanup"
            app.launch(); app.terminate()
        }
        func reveal(_ element: XCUIElement) {
            let form = app.collectionViews.firstMatch
            for attempt in 0..<10 {
                let visible = form.frame.insetBy(dx: 0, dy: 12)
                if element.exists && element.isHittable && visible.contains(element.frame) { break }
                let down = element.exists ? element.frame.midY < visible.midY : attempt < 3
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.75))
                    .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.75 : 0.3)))
            }
            XCTAssertTrue(element.isHittable)
            XCTAssertTrue(form.frame.contains(element.frame))
        }
        let quick = app.buttons[label("Quick Connect", "快速连接")]
        XCTAssertTrue(quick.waitForExistence(timeout: 10)); quick.tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText("127.0.0.1\n")
        let toggle = app.switches["ssh-enabled"]
        reveal(toggle)
        let native = toggle.switches.firstMatch
        if native.exists { native.tap() }
        else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        let username = app.textFields["ssh-username"]
        reveal(username); username.tap(); username.typeText("qa-paste-user\n")
        let method = app.buttons["ssh-authentication-method"]
        reveal(method); method.tap()
        app.buttons[label("Private Key", "私钥")].tap()
        let connect = app.buttons[label("Connect", "连接")]
        XCTAssertFalse(connect.isEnabled)
        let fingerprint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch
        var priorFingerprint: String?
        if invalid {
            let choose = app.descendants(matching: .any)["ssh-saved-key"].firstMatch
            reveal(choose); choose.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let option = app.buttons.matching(identifier: "ssh-saved-key-option-" + token).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            reveal(fingerprint)
            priorFingerprint = fingerprint.label
            XCTAssertTrue(connect.isEnabled)
        }
        let paste = app.descendants(matching: .any)["ssh-paste-key"].firstMatch
        reveal(paste)
        XCTAssertTrue(paste.isEnabled)
        paste.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if invalid {
            let error = app.staticTexts[label("The SSH private key is invalid or damaged.", "SSH 私钥无效或已损坏。")]
            reveal(error)
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertEqual(fingerprint.label, priorFingerprint)
        } else {
            XCTAssertTrue(fingerprint.waitForExistence(timeout: 5))
            reveal(fingerprint)
        }
        XCTAssertTrue(connect.isEnabled)
        attachScreenshot(app, name: (invalid ? "Invalid key paste preserves selection " : "Native private key paste ") + language)
        app.buttons[label("Cancel", "取消")].tap()
    }

    func testControlledSSHKeyLibraryPaste() throws { try verifyControlledSSHKeyLibrary(language: "en", paste: true) }
    func testChineseControlledSSHKeyLibraryPaste() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans", paste: true) }

    func testControlledSSHKeyLibraryFile() throws { try verifyControlledSSHKeyLibrary(language: "en", file: true) }
    func testChineseControlledSSHKeyLibraryFile() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans", file: true) }

    func testControlledSSHKeyLibraryExport() throws { try verifyControlledSSHKeyLibrary(language: "en", export: true) }
    func testChineseControlledSSHKeyLibraryExport() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans", export: true) }
    func testControlledSSHKeyLibraryExportSave() throws { try verifyControlledSSHKeyLibrary(language: "en", export: true, exportSave: true) }
    func testChineseControlledSSHKeyLibraryExportSave() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans", export: true, exportSave: true) }

    func testControlledSSHKeyLibraryFileEncrypted() throws { try verifyControlledSSHKeyLibrary(language: "en", file: true, encryptedKey: true) }
    func testChineseControlledSSHKeyLibraryFileEncrypted() throws { try verifyControlledSSHKeyLibrary(language: "zh-Hans", file: true, encryptedKey: true) }

    private func verifyControlledSSHKeyLibrary(language: String, paste: Bool = false, file: Bool = false, export: Bool = false, exportSave: Bool = false, encryptedKey: Bool = false) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires owned controlled simulator") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        let token = UUID().uuidString
        app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_TOKEN"] = token
        app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = encryptedKey ? "seed-encrypted-file" : ((file || exportSave) ? "seed-library-file" : (paste ? "seed-library-paste" : "seed-library"))
        app.launch()
        app.launchEnvironment.removeValue(forKey: "AETHERSCREENS_SSH_KEY_QA_ACTION")
        defer {
            app.terminate()
            app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = "cleanup"
            app.launch(); app.terminate()
        }
        func openLibrary() {
            let more = app.buttons[label("More Actions", "更多操作")]
            XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
            app.buttons[label("Settings", "设置")].tap()
            let link = app.buttons["ssh-key-library"]
            XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
            XCTAssertTrue(app.navigationBars[label("SSH Keys", "SSH 密钥")].waitForExistence(timeout: 5))
        }
        openLibrary()
        var importedToken = token
        if file {
            app.buttons["ssh-library-import"].tap()
            let name = "QA-Key-" + token
            let document = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            // Files retains a last-used directory as well as Recents/Locations.
            if !document.waitForExistence(timeout: 3) {
                let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览"])).firstMatch
                if browse.exists { browse.tap() }
                if !document.waitForExistence(timeout: 5) {
                    let container = app.cells["AetherScreens, Container"].firstMatch
                    if !container.waitForExistence(timeout: 2) {
                        let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "On My iPad", "我的iPhone", "我的iPad", "我的 iPhone", "我的 iPad"])).firstMatch
                        XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap()
                    }
                    XCTAssertTrue(container.waitForExistence(timeout: 5)); container.tap()
                }
            }
            XCTAssertTrue(document.waitForExistence(timeout: 5)); document.tap()
            if encryptedKey {
                let phrase = app.secureTextFields["ssh-key-passphrase"]
                XCTAssertTrue(phrase.waitForExistence(timeout: 10))
                do {
                    let readyPhrase = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: phrase)
                    XCTAssertEqual(XCTWaiter.wait(for: [readyPhrase], timeout: 10), .completed)
                }
                phrase.tap(); phrase.typeText("QA-only encrypted import")
                app.buttons["ssh-key-unlock"].tap()
            }

        }
        if paste {
            let nativePaste = app.buttons["ssh-library-paste"].firstMatch
            XCTAssertTrue(nativePaste.waitForExistence(timeout: 5))
            XCTAssertTrue(nativePaste.isEnabled); nativePaste.tap()
        }
        if paste || file {
            let imported = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@", "ssh-library-delete-", "ssh-library-delete-" + token)).firstMatch
            XCTAssertTrue(imported.waitForExistence(timeout: 5))
            importedToken = String(imported.identifier.dropFirst("ssh-library-delete-".count))
            XCTAssertNotNil(UUID(uuidString: importedToken))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).count, 2)
        }
        if encryptedKey {
            let seedFingerprint = app.staticTexts["ssh-library-fingerprint-" + token]
            let importedFingerprint = app.staticTexts["ssh-library-fingerprint-" + importedToken]
            XCTAssertTrue(importedFingerprint.waitForExistence(timeout: 10))
            XCTAssertEqual(importedFingerprint.label, seedFingerprint.label)
            attachScreenshot(app, name: "Encrypted Key Saved Library " + language)
        }
        let delete = app.buttons["ssh-library-delete-" + importedToken]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(delete.isEnabled)
        let fingerprint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch
        XCTAssertTrue(fingerprint.exists)
        XCTAssertTrue(app.buttons["ssh-library-import"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["ssh-library-paste"].firstMatch.exists)
        if export {
            let exportButton = app.buttons["ssh-library-export-" + importedToken]
            XCTAssertTrue(exportButton.isEnabled)
            exportButton.tap()
            let warning = app.staticTexts[label("The exported file contains your unencrypted private key. Choose a trusted destination.", "导出的文件包含未加密私钥，请选择可信的保存位置。")]
            XCTAssertTrue(warning.waitForExistence(timeout: 5))
            attachScreenshot(app, name: "SSH Export Confirmation " + language)
            let confirmationCancel = app.buttons[label("Cancel", "取消")].firstMatch
            if confirmationCancel.exists {
                confirmationCancel.tap()
            } else {
                let dismiss = app.otherElements["PopoverDismissRegion"]
                XCTAssertTrue(dismiss.exists)
                dismiss.tap()
            }
            XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
            exportButton.tap()
            app.buttons[label("Export", "导出")].firstMatch.tap()
            // iOS 27's document picker exposes Cancel as Other rather than Button.
            let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 10))
            attachScreenshot(app, name: "SSH Native Export Picker " + language)
            if cancel.isHittable {
                cancel.tap()
            } else {
                // The picker exposes a hidden Cancel element; dismiss its visible sheet edge.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.075))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
            }
            XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
            XCTAssertTrue(delete.exists)
        }
        if exportSave {
            let selectedFingerprint = app.staticTexts["ssh-library-fingerprint-" + token].label
            let existing = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).allElementsBoundByIndex.map(\.identifier))
            app.buttons["ssh-library-export-" + token].tap()
            app.buttons[label("Export", "导出")].firstMatch.tap()
            let filename = app.textFields["DOCPicker.filenameTextField"]
            XCTAssertTrue(filename.waitForExistence(timeout: 10))
            filename.tap()
            filename.press(forDuration: 1)
            let selectAll = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Select All", "全选"])).firstMatch
            if selectAll.exists { selectAll.tap() }
            // Native fields select their stem on focus; clear the verified existing value explicitly.
            let current = filename.value as? String ?? ""
            filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "QA-Export-" + token)
            let save = app.buttons["DOCPicker.actionButton"]
            XCTAssertTrue(save.waitForExistence(timeout: 10))
            attachScreenshot(app, name: "SSH Export Save Destination " + language)
            save.tap()
            XCTAssertTrue(app.buttons["ssh-library-export-" + token].waitForExistence(timeout: 10))
            app.terminate()
            app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = "verify-export"
            app.launch()
            app.launchEnvironment.removeValue(forKey: "AETHERSCREENS_SSH_KEY_QA_ACTION")
            openLibrary() // The QA-only bootstrap rejects missing or non-identical exported bytes.
            app.buttons["ssh-library-import"].tap()
            let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "QA-Export-" + token)).firstMatch
            // Files can retain the just-used save directory instead of starting at Locations.
            if !saved.waitForExistence(timeout: 3) {
                let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览"])).firstMatch
                if browse.exists { browse.tap() }
                if !saved.waitForExistence(timeout: 5) {
                    let container = app.cells["AetherScreens, Container"].firstMatch
                    if !container.waitForExistence(timeout: 2) {
                        let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "我的iPhone", "我的 iPhone"])).firstMatch
                        XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap()
                    }
                    XCTAssertTrue(container.waitForExistence(timeout: 5)); container.tap()
                }
            }
            XCTAssertTrue(saved.waitForExistence(timeout: 5)); saved.tap()
            let importedReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-"))
                    .allElementsBoundByIndex.filter { !existing.contains($0.identifier) }.count == 1
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [importedReady], timeout: 10), .completed)
            let newKeys = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).allElementsBoundByIndex.filter { !existing.contains($0.identifier) }
            XCTAssertEqual(newKeys.count, 1)
            let newReference = String(try XCTUnwrap(newKeys.first).identifier.dropFirst("ssh-library-delete-".count))
            XCTAssertEqual(app.staticTexts["ssh-library-fingerprint-" + newReference].label, selectedFingerprint)
            attachScreenshot(app, name: "SSH Export Reimport " + language)
        }
        app.buttons["ssh-library-rename-" + importedToken].tap()
        let renameAlert = app.alerts[label("Key Name", "密钥名称")]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 5))
        // Scope the field to the exact rename alert and verify a single input.
        XCTAssertEqual(renameAlert.textFields.count, 1)
        let name = renameAlert.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("QA Work Key")
        renameAlert.buttons[label("Save", "保存")].tap()
        XCTAssertTrue(app.staticTexts["QA Work Key"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        openLibrary()
        XCTAssertTrue(app.staticTexts["QA Work Key"].waitForExistence(timeout: 5), "The key label must survive relaunch")
        XCTAssertTrue(fingerprint.exists)
        attachScreenshot(app, name: "Standalone SSH Key Library " + language)
        let keyCountBeforeRemoval = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).count
        delete.tap()
        let confirmation = app.buttons.matching(NSPredicate(format: "label == %@", label("Delete", "删除")))
            .allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "ssh-library-delete-" + importedToken }
        try XCTUnwrap(confirmation).tap()
        if paste || file {
            XCTAssertTrue(app.buttons["ssh-library-delete-" + token].exists)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).count, 1)
            XCTAssertFalse(app.staticTexts["QA Work Key"].exists)
        } else if export {
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ssh-library-delete-")).count, keyCountBeforeRemoval - 1)
        } else {
            XCTAssertTrue(app.staticTexts[label("No saved private keys", "暂无已保存的私钥")].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(delete.exists)
        attachScreenshot(app, name: "Empty SSH Key Library " + language)
    }

    func testControlledSSHKeyLibraryFileDraft() throws { try verifyControlledSSHSettings(language: "en", checkKeyImport: true, checkDraftFile: true) }
    func testChineseControlledSSHKeyLibraryFileDraft() throws { try verifyControlledSSHSettings(language: "zh-Hans", checkKeyImport: true, checkDraftFile: true) }

    func testControlledSSHKeyLibraryFileEncryptedDraft() throws { try verifyControlledSSHSettings(language: "en", checkKeyImport: true, checkDraftFile: true, encryptedKey: true) }
    func testChineseControlledSSHKeyLibraryFileEncryptedDraft() throws { try verifyControlledSSHSettings(language: "zh-Hans", checkKeyImport: true, checkDraftFile: true, encryptedKey: true) }

    private func verifyControlledSSHSettings(language: String, checkKeyImport: Bool = false, checkSavedKey: Bool = false, checkDraftFile: Bool = false, encryptedKey: Bool = false) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires owned controlled simulator") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        let keyToken = UUID().uuidString
        if checkSavedKey || checkDraftFile {
            app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_TOKEN"] = keyToken
            app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = encryptedKey ? "seed-encrypted-file" : (checkDraftFile ? "seed-library-file" : "seed")
        }
        app.launch()
        if checkSavedKey || checkDraftFile { app.launchEnvironment.removeValue(forKey: "AETHERSCREENS_SSH_KEY_QA_ACTION") }
        defer {
            if checkSavedKey || checkDraftFile {
                app.terminate()
                app.launchEnvironment["AETHERSCREENS_SSH_KEY_QA_ACTION"] = "cleanup"
                app.launch()
                app.terminate()
            }
        }
        let computer = ensureLoopbackComputer(in: app, language: language)
        func scrollForm(down: Bool) {
            // Drag the Form content rather than the sheet surface: a downward
            // sheet swipe can dismiss iPad's editor before reaching the fields.
            let form = app.collectionViews.firstMatch
            XCTAssertTrue(form.exists)
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.75))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.75 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        func reveal(_ element: XCUIElement) {
            let form = app.collectionViews.firstMatch
            for attempt in 0..<10 {
                let visible = form.frame.insetBy(dx: 0, dy: 12)
                if element.exists && element.isHittable && visible.contains(element.frame) { break }
                if element.exists {
                    scrollForm(down: element.frame.midY < visible.midY)
                } else {
                    // Lazy iPad rows may be absent from AX in either direction.
                    // Search from the top rather than always scrolling farther down.
                    scrollForm(down: attempt < 3)
                }
            }
            XCTAssertTrue(element.isHittable)
            XCTAssertTrue(form.frame.contains(element.frame), "Control must be fully visible before tapping")
        }
        func tapSSHSwitch() {
            let control = app.switches["ssh-enabled"]
            reveal(control)
            let nativeSwitch = control.switches.firstMatch
            if nativeSwitch.exists { nativeSwitch.tap() }
            else { control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        }
        func edit() {
            scrollComputerIntoView(computer, in: app)
            // iOS 27 can expose the card as Button/PopUpButton inconsistently.
            // Use the observed, fully visible card frame for the real long press.
            let window = app.windows.firstMatch
            let frame = computer.frame
            XCTAssertTrue(window.frame.contains(frame))
            window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX - window.frame.minX, dy: frame.midY - window.frame.minY))
                .press(forDuration: 1)
            let editAction = app.buttons[label("Edit Computer...", "编辑电脑…")]
            XCTAssertTrue(editAction.waitForExistence(timeout: 5))
            editAction.tap()
            XCTAssertTrue(app.navigationBars[label("Edit Computer", "编辑电脑")].waitForExistence(timeout: 5))
            scrollForm(down: true); scrollForm(down: true)
        }
        func save() {
            // AutoFill may offer to save the QA-only password in the system
            // password manager after the app has stored it in its own vault.
            // Keep that separate store empty; this test verifies the app vault.
            let later = app.buttons.matching(NSPredicate(format: "label IN %@", ["Not Now", "Not now", "以后", "暂不"])).firstMatch
            if later.waitForExistence(timeout: 2) { later.tap() }
            app.navigationBars[label("Edit Computer", "编辑电脑")].buttons[label("Save", "保存")].tap()
            if later.waitForExistence(timeout: 2) { later.tap() }
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                object: app.navigationBars[label("Edit Computer", "编辑电脑")])
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed, "Saving must dismiss the edit sheet")
        }
        let toggle = app.switches["ssh-enabled"]
        let username = app.textFields["ssh-username"]
        let port = app.textFields["ssh-port"]
        if !checkDraftFile {
            edit()
            reveal(toggle)
            if toggle.value as? String == "0" { tapSSHSwitch() }
            XCTAssertEqual(toggle.value as? String, "1")
            reveal(username)
            username.tap()
            let old = username.value as? String ?? ""
            if old != label("SSH Username", "SSH 用户名") {
                username.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            XCTAssertFalse(app.buttons[label("Save", "保存")].isEnabled, "An SSH account is required")
            username.typeText("qa-ssh-user\n")
            reveal(port)
            replacePort(port, with: "2222")
            XCTAssertTrue(app.buttons[label("Save", "保存")].isEnabled)
            let sshPassword = app.secureTextFields["ssh-settings-password"]
            reveal(sshPassword)
            sshPassword.tap()
            sshPassword.typeText("QA-only-no-real-account\n")
            reveal(app.textFields["ssh-desktop-host"])
            attachScreenshot(app, name: "SSH Settings " + language)
            save()
            edit()
            reveal(toggle)
            XCTAssertEqual(toggle.value as? String, "1")
            reveal(username)
            XCTAssertEqual(username.value as? String, "qa-ssh-user")
            XCTAssertEqual(port.value as? String, "2222")
            attachScreenshot(app, name: "Reloaded SSH Settings " + language)
            reveal(toggle)
            tapSSHSwitch()
            save()
            edit()
            reveal(toggle)
            XCTAssertEqual(toggle.value as? String, "0")
            XCTAssertFalse(username.exists)
            app.buttons[label("Cancel", "取消")].tap()
        }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText("127.0.0.1\n")
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        reveal(toggle)
        tapSSHSwitch()
        reveal(username)
        username.tap(); username.typeText("qa-ssh-user\n")
        XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
        attachScreenshot(app, name: "Temporary SSH Quick Connect " + language)
        if checkKeyImport {
            let method = app.buttons["ssh-authentication-method"]
            reveal(method)
            method.tap()
            app.buttons[label("Private Key", "私钥")].tap()
            let importButton = app.buttons["ssh-import-key"]
            reveal(importButton)
            XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled, "A key must be imported before connecting")
            attachScreenshot(app, name: "Private Key Selection " + language)
            importButton.tap()
            if checkDraftFile {
                let document = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "QA-Key-" + keyToken)).firstMatch
                if !document.waitForExistence(timeout: 3) {
                    let browse = app.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览"])).firstMatch
                    if browse.exists { browse.tap() }
                    if !document.waitForExistence(timeout: 5) {
                        let container = app.cells["AetherScreens, Container"].firstMatch
                        if !container.waitForExistence(timeout: 2) {
                            let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "我的iPhone", "我的 iPhone"])).firstMatch
                            XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap()
                        }
                        XCTAssertTrue(container.waitForExistence(timeout: 5)); container.tap()
                    }
                }
                XCTAssertTrue(document.waitForExistence(timeout: 5)); document.tap()
                if encryptedKey {
                    let phrase = app.secureTextFields["ssh-key-passphrase"]
                    XCTAssertTrue(phrase.waitForExistence(timeout: 10))
                    do {
                        let readyPhrase = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: phrase)
                        XCTAssertEqual(XCTWaiter.wait(for: [readyPhrase], timeout: 10), .completed)
                    }
                    attachScreenshot(app, name: "Encrypted Key Passphrase " + language)
                    phrase.tap(); phrase.typeText("wrong QA phrase")
                    app.buttons["ssh-key-unlock"].tap()
                    let failure = app.staticTexts[label("Could not unlock the private key. Check the passphrase and key file.", "无法解锁私钥，请检查口令和私钥文件。")]
                    XCTAssertTrue(failure.waitForExistence(timeout: 10))
                    attachScreenshot(app, name: "Encrypted Key Wrong Passphrase " + language)
                    app.buttons["ssh-key-unlock-cancel"].tap()
                    XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled)
                    XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch.exists)
                    importButton.tap()
                    XCTAssertTrue(document.waitForExistence(timeout: 10)); document.tap()
                    XCTAssertTrue(phrase.waitForExistence(timeout: 10))
                    do {
                        let readyPhrase = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: phrase)
                        XCTAssertEqual(XCTWaiter.wait(for: [readyPhrase], timeout: 10), .completed)
                    }
                    phrase.tap(); phrase.typeText("QA-only encrypted import")
                    app.buttons["ssh-key-unlock"].tap()
                }
                let imported = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch
                XCTAssertTrue(imported.waitForExistence(timeout: 10))
                let uncovered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: importButton)
                XCTAssertEqual(XCTWaiter.wait(for: [uncovered], timeout: 10), .completed)
                let interactiveFingerprint = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: imported)
                XCTAssertEqual(XCTWaiter.wait(for: [interactiveFingerprint], timeout: 10), .completed)
                XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
                attachScreenshot(app, name: "Temporary SSH Draft File Import " + language)
            } else {
                // Document picker belongs to the native system UI. Only cancel the
                // currently hittable foreground action, preserving the draft sheet.
                let covered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: importButton)
                XCTAssertEqual(XCTWaiter.wait(for: [covered], timeout: 10), .completed, "Wait for the picker to cover the draft before locating Cancel")
                // On iOS 27 the document picker is a separate extension process.
                // Its bundle ID is verified against the installed runtime's plist.
                let documentService = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
                let cancelPredicate = NSPredicate(format: "label IN %@", ["Cancel", "取消"])
                let appCancels = app.buttons.matching(cancelPredicate)
                let serviceCancels = documentService.buttons.matching(cancelPredicate)
                func foregroundCancel() -> XCUIElement? {
                    (serviceCancels.allElementsBoundByIndex + appCancels.allElementsBoundByIndex)
                        .first(where: { $0.isHittable })
                }
                let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    foregroundCancel() != nil
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 15), .completed)
                let pickerImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                pickerImage.name = "Private Key File Picker " + language
                pickerImage.lifetime = .keepAlways
                add(pickerImage)
                try XCTUnwrap(foregroundCancel()).tap()
                let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: importButton)
                XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
                XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled)
            }
            reveal(method)
            method.tap()
            app.buttons[label("Password", "密码")].tap()
            XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
        }
        if checkSavedKey {
            func chooseSavedKey() {
                let method = app.buttons["ssh-authentication-method"]
                reveal(method); method.tap()
                app.buttons[label("Private Key", "私钥")].tap()
                let menu = app.descendants(matching: .any)["ssh-saved-key"].firstMatch
                reveal(menu)
                menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let option = app.buttons.matching(identifier: "ssh-saved-key-option-" + keyToken).firstMatch
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
                let fingerprint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch
                reveal(fingerprint)
                XCTAssertTrue(fingerprint.exists)
            }
            chooseSavedKey()
            XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
            attachScreenshot(app, name: "Reused private key temporary " + language)
            app.buttons[label("Cancel", "取消")].tap()
            edit()
            reveal(toggle); tapSSHSwitch()
            reveal(username); username.tap(); username.typeText("qa-ssh-user\n")
            chooseSavedKey()
            save()
            app.terminate(); app.launch()
            edit()
            let fingerprint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SHA256:")).firstMatch
            reveal(fingerprint)
            XCTAssertTrue(fingerprint.exists, "Saved key identity must survive relaunch")
            attachScreenshot(app, name: "Reused private key reloaded " + language)
            // iPad Form lazily removes rows above the viewport from AX. Return
            // upward before looking for its SSH switch after the lower key row.
            scrollForm(down: true); scrollForm(down: true)
            reveal(toggle); tapSSHSwitch(); save()
        } else {
            app.buttons[label("Cancel", "取消")].tap()
        }
    }

    func testControlledDisconnectAction() throws { try verifyControlledDisconnectAction(language: "en") }
    func testChineseControlledDisconnectAction() throws { try verifyControlledDisconnectAction(language: "zh-Hans") }

    func testControlledStaticLockNotice() throws { try verifyStaticLockNotice(language: "en") }
    func testChineseControlledStaticLockNotice() throws { try verifyStaticLockNotice(language: "zh-Hans") }

    func testControlledReducedMotionLockNotice() throws {
        try withReducedMotionEnabled { try verifyStaticLockNotice(language: "en") }
    }

    func testControlledReducedMotionKeyboardOverlays() throws {
        try withReducedMotionEnabled {
            try verifyFloatingToolbar(language: "en")
            try verifyCarouselToolbar(language: "en")
        }
    }

    func testControlledSystemReducedMotionOff() throws {
        try withReducedMotionEnabled(restoring: "0") {}
    }

    private func withReducedMotionEnabled(restoring: String? = nil, _ verify: () throws -> Void) throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("System setting changes are isolated to the owned simulator")
        #endif
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let reducedMotion = settings.switches["REDUCE_MOTION"].firstMatch
        let motion = settings.cells["MOTION_TITLE"]
        func openMotionPage() {
            if !reducedMotion.waitForExistence(timeout: 2) {
                if !motion.exists {
                    for _ in 0..<5 { settings.swipeDown() }
                    let accessibility = settings.buttons["com.apple.settings.accessibility"]
                    for _ in 0..<5 { if accessibility.exists && accessibility.isHittable { break }; settings.swipeUp() }
                    attachScreenshot(settings, name: "System Accessibility Entry")
                    let hierarchy = XCTAttachment(string: settings.debugDescription)
                    hierarchy.name = "System Settings Hierarchy"
                    hierarchy.lifetime = .keepAlways
                    add(hierarchy)
                    XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
                    accessibility.tap()
                }
                XCTAssertTrue(motion.waitForExistence(timeout: 5))
                motion.tap()
            }
            XCTAssertTrue(reducedMotion.waitForExistence(timeout: 5))
        }
        openMotionPage()
        let original = try XCTUnwrap(reducedMotion.value as? String)
        let originalValue = XCTAttachment(string: original)
        originalValue.name = "Owned Simulator Reduce Motion Original Value"
        originalValue.lifetime = .keepAlways
        add(originalValue)
        func setReducedMotion(_ desired: String) {
            for _ in 0..<2 {
                if reducedMotion.value as? String == desired { return }
                reducedMotion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", desired), object: reducedMotion)
                if XCTWaiter.wait(for: [settled], timeout: 5) == .completed { return }
            }
            XCTAssertEqual(reducedMotion.value as? String, desired)
        }
        if let restoring {
            setReducedMotion(restoring)
            XCTAssertEqual(reducedMotion.value as? String, restoring)
            attachScreenshot(settings, name: "Owned Simulator Reduce Motion Recovery")
            settings.terminate()
            return
        }
        defer {
            settings.activate()
            openMotionPage()
            setReducedMotion(original)
            attachScreenshot(settings, name: "System Reduce Motion Restored")
            XCTAssertEqual(reducedMotion.value as? String, original, "Restore the owned simulator setting")
            settings.terminate()
        }
        setReducedMotion("1")
        attachScreenshot(settings, name: "System Reduce Motion Enabled")
        try verify()
    }

    func testControlledSystemSettingsInventory() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("System settings inspection is isolated to the owned simulator")
        #endif
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        defer { settings.terminate() }
        for _ in 0..<5 { settings.swipeDown() }
        for page in 0..<3 {
            let hierarchy = XCTAttachment(string: settings.debugDescription)
            hierarchy.name = "System Settings Inventory " + String(page)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(settings, name: "System Settings Inventory " + String(page))
            settings.swipeUp()
        }
        for _ in 0..<5 { settings.swipeDown() }
        let accessibility = settings.buttons["com.apple.settings.accessibility"]
        if accessibility.exists {
            accessibility.tap()
            let hierarchy = XCTAttachment(string: settings.debugDescription)
            hierarchy.name = "System Accessibility Inventory"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(settings, name: "System Accessibility Inventory")
        }
        let motion = settings.cells["MOTION_TITLE"]
        if motion.exists {
            motion.tap()
            let hierarchy = XCTAttachment(string: settings.debugDescription)
            hierarchy.name = "System Motion Inventory"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(settings, name: "System Motion Inventory")
        }
    }

    private func verifyStaticLockNotice(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        host.typeText("\n")
        let hostKeyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hostKeyboardDismissed], timeout: 3), .completed)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let connection = try lastFixtureConnection()
        let before = try fixtureEvents().filter { $0["connection"] as? Int == connection && $0["type"] as? String == "frame" }.count
        app.buttons[label("Session Options", "会话选项")].tap()
        attachScreenshot(app, name: "Static Lock Session Menu " + language)
        let lockAction = app.buttons[label("Lock Remote Mac", "锁定远端 Mac")]
        for _ in 0..<12 {
            if lockAction.exists && lockAction.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(lockAction.waitForExistence(timeout: 3))
        lockAction.tap()
        let notice = app.staticTexts[label("Lock Screen shortcut sent", "已发送锁屏快捷键")]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        let window = app.windows.firstMatch.frame
        for element in [notice, app.buttons[label("Dismiss", "关闭提示")], app.buttons[label("Reconnect", "重新连接")]] {
            XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX)
        }
        attachScreenshot(app, name: "Static Lock Notice " + language)
        app.buttons[label("Dismiss", "关闭提示")].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
        let events = try waitForFixtureEvents { $0.contains { $0["connection"] as? Int == connection && $0["type"] as? String == "key" && $0["key"] as? Int == 65507 && $0["down"] as? Int == 0 } }
        let keys = events.filter { $0["connection"] as? Int == connection && $0["type"] as? String == "key" }
        XCTAssertEqual(keys.compactMap { $0["key"] as? Int }, [65507, 65515, 113, 113, 65515, 65507])
        XCTAssertEqual(events.filter { $0["connection"] as? Int == connection && $0["type"] as? String == "frame" }.count, before, "Notice must refresh without a new frame")
        attachScreenshot(app, name: "Static Lock Notice Dismissed " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledDisconnectAction(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        let computer = ensureLoopbackComputer(in: app, language: language)
        computer.press(forDuration: 1)
        app.buttons[label("Edit Computer...", "编辑电脑…")].tap()
        XCTAssertTrue(app.navigationBars[label("Edit Computer", "编辑电脑")].waitForExistence(timeout: 5))
        // A failed SSH settings run may leave this owned fixture configured for
        // tunneling. This scenario must deliberately use the direct RFB fixture.
        app.swipeDown(); app.swipeDown()
        let sshToggle = app.switches["ssh-enabled"]
        for _ in 0..<6 { if sshToggle.exists && sshToggle.isHittable { break }; app.swipeUp() }
        if sshToggle.value as? String == "1" {
            sshToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        app.swipeDown(); app.swipeDown()
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        let picker = app.descendants(matching: .any)["disconnect-action"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons[label("Lock Screen", "锁定屏幕")].tap()
        attachScreenshot(app, name: "Disconnect Action Settings " + language)
        app.buttons[label("Save", "保存")].tap()
        computer.press(forDuration: 1)
        app.buttons[label("Edit Computer...", "编辑电脑…")].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, label("Lock Screen", "锁定屏幕"))
        app.buttons[label("Cancel", "取消")].tap()
        try resetGestureFixture()
        computer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 15))
        app.buttons[label("Disconnect", "断开连接")].tap()
        let events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "key" && $0["key"] as? Int == 65507 && $0["down"] as? Int == 0 } }
        let keys = events.filter { $0["type"] as? String == "key" }
        XCTAssertEqual(keys.compactMap { $0["key"] as? Int }, [65507, 65515, 113, 113, 65515, 65507])
        XCTAssertEqual(keys.compactMap { $0["down"] as? Int }, [1, 1, 1, 0, 0, 0])
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.press(forDuration: 1)
        app.buttons[label("Edit Computer...", "编辑电脑…")].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons[label("No Action", "不执行动作")].tap()
        app.buttons[label("Save", "保存")].tap()
    }
    func testControlledShortcutsCatalog() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("System Shortcuts acceptance is isolated to the owned simulator")
        #endif
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires isolated controlled simulator") }
        continueAfterFailure = false
        let app = makeApp()
        app.launch()
        let saved = app.buttons["Connect to QA Shortcut Fixture"].firstMatch
        if !saved.exists {
            app.buttons["Add Computer"].tap()
            let name = app.textFields["Name (e.g. Studio Mac)"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap(); name.typeText("QA Shortcut Fixture")
            let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
            host.tap(); host.typeText(gestureFixtureHost)
            replacePort(app.textFields["Port"], with: gestureFixturePort)
            app.buttons["Save"].tap()
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.terminate()
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        defer { shortcuts.terminate() }
        XCTAssertTrue(shortcuts.wait(for: .runningForeground, timeout: 10))
        let onboarding = shortcuts.buttons["继续"]
        if onboarding.waitForExistence(timeout: 3) { onboarding.tap() }
        let create = shortcuts.buttons["main.button.newshortcut"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let actionSearch = shortcuts.searchFields.firstMatch
        XCTAssertTrue(actionSearch.waitForExistence(timeout: 10))
        actionSearch.tap()
        actionSearch.typeText("连接电脑")
        XCTAssertTrue(shortcuts.staticTexts["连接电脑"].firstMatch.waitForExistence(timeout: 15))
        shortcuts.staticTexts["连接电脑"].firstMatch.tap()
        let computerParameter = shortcuts.buttons["电脑"]
        XCTAssertTrue(computerParameter.waitForExistence(timeout: 5))
        computerParameter.tap()
        let savedParameter = shortcuts.buttons["QA Shortcut Fixture, 127.0.0.1"]
        XCTAssertTrue(savedParameter.waitForExistence(timeout: 10))
        savedParameter.tap()
        try resetGestureFixture()
        let run = shortcuts.buttons["播放"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 15))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 1)
        try attachGesturePackets(events, name: "System Shortcut Connection Click")
        attachScreenshot(app, name: "System Shortcut Connected Session")
        let connection = try lastFixtureConnection()
        shortcuts.activate()
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        run.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let reused = try waitForFixtureEvents { $0.filter { $0["type"] as? String == "pointer" && $0["mask"] as? Int == 1 }.count >= 2 }
        XCTAssertEqual(reused.filter { $0["type"] as? String == "ready" }.count, 1, "Repeated saved shortcut must reuse the live session")
        XCTAssertEqual(try lastFixtureConnection(), connection)
        XCTAssertTrue(reused.filter { $0["type"] as? String == "pointer" }.allSatisfy { $0["connection"] as? Int == connection })
        attachScreenshot(shortcuts, name: "System Shortcuts initial catalog")
        let hierarchy = XCTAttachment(string: shortcuts.debugDescription)
        hierarchy.name = "System Shortcuts initial hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure || issue.type == .uncaughtException {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Failure screen"
            screenshot.lifetime = .keepAlways
            let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
            hierarchy.name = "Failure UI hierarchy"
            hierarchy.lifetime = .keepAlways
            let captured = XCTIssue(type: issue.type,
                                    compactDescription: issue.compactDescription,
                                    detailedDescription: issue.detailedDescription,
                                    sourceCodeContext: issue.sourceCodeContext,
                                    associatedError: issue.associatedError,
                                    attachments: issue.attachments + [screenshot, hierarchy])
            super.record(captured)
            return
        }
        super.record(issue)
    }

    func testControlledDisplayQuality() throws { try verifyDisplayQuality(language: "en") }
    func testChineseControlledDisplayQuality() throws { try verifyDisplayQuality(language: "zh-Hans") }

    private func verifyDisplayQuality(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let bounds = input.frame
        var previous = try lastFixtureConnection()
        for (name, translated, bits) in [("Reduced Colors", "减少色彩", 16), ("Full Color", "全彩", 32)] {
            app.buttons[label("Session Options", "会话选项")].tap()
            app.buttons["session-display-quality"].tap()
            app.buttons["display-color-depth"].tap()
            app.buttons[label(name, translated)].tap()
            let events = try waitForFixtureEvents { events in
                events.contains { $0["type"] as? String == "frame" && $0["full"] as? Bool == true && $0["bitsPerPixel"] as? Int == bits && $0["connection"] as? Int != previous }
            }
            let connection = try XCTUnwrap(events.last { $0["type"] as? String == "frame" && $0["bitsPerPixel"] as? Int == bits }?["connection"] as? Int)
            XCTAssertNotEqual(connection, previous)
            let frame = try XCTUnwrap(events.last { $0["type"] as? String == "frame" && $0["connection"] as? Int == connection && $0["full"] as? Bool == true })
            XCTAssertEqual(frame["rawPixelBytes"] as? Int, 640 * 360 * (bits / 8))
            attachScreenshot(app, name: "Display quality selection " + language + " " + String(bits))
            app.buttons[label("Done", "完成")].tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(input.frame, bounds)
            try resetGestureFixture()
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let click = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
            XCTAssertEqual(Double(try XCTUnwrap(click["x"])), 320, accuracy: 5)
            XCTAssertEqual(Double(try XCTUnwrap(click["y"])), 180, accuracy: 5)
            attachScreenshot(app, name: "Display quality restored canvas " + language + " " + String(bits))
            previous = connection
        }
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testPhysicalZoomedTrackpadEdgeFollow() throws { try verifyZoomedTrackpadEdgeFollow(language: "en") }
    func testControlledZoomedTrackpadEdgeFollow() throws { try verifyZoomedTrackpadEdgeFollow(language: "en") }
    func testChineseControlledZoomedTrackpadEdgeFollow() throws { try verifyZoomedTrackpadEdgeFollow(language: "zh-Hans") }

    private func verifyZoomedTrackpadEdgeFollow(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 15))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        func mode(_ value: String) {
            app.buttons[label("Input Mode", "输入模式")].tap()
            app.buttons[value].tap()
        }
        func centerX() throws -> Int {
            try resetGestureFixture()
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        }
        func resetView() {
            app.buttons[label("Session Options", "会话选项")].tap()
            app.buttons[label("Fit to Window", "适应窗口")].tap()
            mode(label("Touch", "触控"))
            input.pinch(withScale: 2, velocity: 1)
        }
        // A direct touch at the same visible location measures the displayed
        // viewport independently from the trackpad pointer's remote position.
        for right in [true, false] {
            resetView()
            let baseline = try centerX()
            mode(label("Trackpad", "触控板"))
            try resetGestureFixture()
            let start = input.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.15 : 0.85, dy: 0.5))
            let end = input.coordinate(withNormalizedOffset: CGVector(dx: right ? 0.85 : 0.15, dy: 0.5))
            for _ in 0..<2 { start.press(forDuration: 0.05, thenDragTo: end) }
            let moved = try waitForGesturePointers { !$0.isEmpty }
            XCTAssertTrue(moved.allSatisfy { $0["mask"] == 0 }, "Moving pointer must not hold a mouse button")
            try attachGesturePackets(moved, name: right ? "Controlled edge follow right" : "Controlled edge follow left")
            attachScreenshot(app, name: right ? "Controlled zoomed viewport right" : "Controlled zoomed viewport left")
            mode(label("Touch", "触控"))
            let shifted = try centerX()
            if right { XCTAssertGreaterThan(shifted, baseline + 40) }
            else { XCTAssertLessThan(shifted, baseline - 40) }
        }
        resetView()
        let baseline = try centerX()
        mode(label("Trackpad", "触控板"))
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).press(forDuration: 0.4,
            thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        let dragged = try waitForGesturePointers {
            $0.filter { $0["mask"] == 1 }.count > 1 && $0.last?["mask"] == 0
        }
        let held = dragged.filter { $0["mask"] == 1 }
        XCTAssertGreaterThan(held.count, 1)
        XCTAssertNotEqual(held.first?["x"], held.last?["x"])
        try attachGesturePackets(dragged, name: "Controlled held drag edge follow")
        attachScreenshot(app, name: "Controlled zoomed held drag viewport")
        mode(label("Touch", "触控"))
        XCTAssertGreaterThan(try centerX(), baseline + 40, "Held-button dragging must move the viewport too")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledMobileSessionSelection() throws { try verifyMobileSessionSelection(language: "en") }
    func testChineseControlledMobileSessionSelection() throws { try verifyMobileSessionSelection(language: "zh-Hans") }

    private func verifyMobileSessionSelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        try resetGestureFixture()
        func connect() {
            app.buttons[label("Quick Connect", "快速连接")].tap()
            let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
            host.tap(); host.typeText(gestureFixtureHost)
            let port = app.textFields[label("Port", "端口")]
            replacePort(port, with: gestureFixturePort)
            app.buttons[label("Connect", "连接")].tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        }
        func library() {
            app.buttons[label("Session Options", "会话选项")].tap()
            app.buttons["session-return-to-library"].tap()
            XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        }
        func select(_ number: Int) {
            app.buttons["open-sessions"].tap()
            attachScreenshot(app, name: "Open Sessions \(number) " + language)
            app.buttons["open-session-\(number)"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 5))
        }
        func events() throws -> [[String: Any]] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
        }
        connect()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        library()
        connect()
        let ready = try events().filter { $0["type"] as? String == "ready" }
        XCTAssertEqual(ready.count, 2)
        let firstID = try XCTUnwrap(ready.first?["connection"] as? Int)
        let secondID = try XCTUnwrap(ready.last?["connection"] as? Int)
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }
        XCTAssertTrue(try events().filter { $0["type"] as? String == "pointer" && $0["mask"] as? Int == 1 }
            .allSatisfy { $0["connection"] as? Int == secondID })
        library()
        select(1)
        let previousPointers = try gesturePointers().count
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        XCTAssertEqual(try gesturePointers().count, previousPointers, "Restored Observe session must still suppress control")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.count > previousPointers }
        XCTAssertEqual(try events().last(where: { $0["type"] as? String == "pointer" })?["connection"] as? Int, firstID)
        XCTAssertEqual(try events().filter { $0["type"] as? String == "ready" }.count, 2, "Switching must reuse both live sockets")
        XCTAssertTrue(try events().filter { $0["type"] as? String == "disconnected" }.isEmpty)
        attachScreenshot(app, name: "Restored Mobile Session " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        select(2)
        app.descendants(matching: .any)["remote-desktop-input"].firstMatch.tap()
        _ = try waitForGesturePointers { $0.count > previousPointers + 2 }
        XCTAssertEqual(try events().last(where: { $0["type"] as? String == "pointer" })?["connection"] as? Int, secondID)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-sessions"].isEnabled)
        attachScreenshot(app, name: "Closed Mobile Sessions " + language)
    }

    func testReceivedNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "en") }
    func testReceivedChineseNativeGesturesOnControlledDesktop() throws { try verifyReceivedNativeGestures(language: "zh-Hans") }
    func testControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "en") }
    func testControlledComputerPreview() throws { try verifyControlledComputerPreview(language: "en") }
    func testChineseControlledComputerPreview() throws { try verifyControlledComputerPreview(language: "zh-Hans") }
    func testControlledComputerPreviewScrollingPerformance() throws {
        try verifyControlledComputerPreview(language: "en", measureScrolling: true)
    }

    func testControlledLargeLibraryScrollingPerformance() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires generated QA app") }
        let token = UUID().uuidString
        let app = makeApp()
        app.launchEnvironment["AETHERSCREENS_LIBRARY_QA_TOKEN"] = token
        app.launchEnvironment["AETHERSCREENS_LIBRARY_QA_ACTION"] = "seed"
        defer {
            app.terminate()
            app.launchEnvironment["AETHERSCREENS_LIBRARY_QA_ACTION"] = "cleanup"
            app.launch()
            XCTAssertFalse(app.buttons["Connect to QA Scroll " + token + " 001"].exists)
        }
        app.launch()
        app.terminate()
        app.launchEnvironment["AETHERSCREENS_LIBRARY_QA_ACTION"] = "display"
        app.launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("QA Scroll " + token + "\n")
        let first = app.buttons["Connect to QA Scroll " + token + " 001"].firstMatch
        let last = app.buttons["Connect to QA Scroll " + token + " 064"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "value == %@", "Desktop preview available")
        expectation(for: ready, evaluatedWith: first)
        waitForExpectations(timeout: 5)
        attachScreenshot(app, name: "64 Computer Library Start")
        let scroll = app.scrollViews.firstMatch
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                                   XCTMemoryMetric(application: app)]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        measure(metrics: metrics, options: options) {
            for _ in 0..<6 { scroll.swipeUp(velocity: .fast) }
            stopMeasuring()
            for _ in 0..<6 { scroll.swipeDown(velocity: .fast) }
        }
        for _ in 0..<40 {
            if last.exists && last.isHittable { break }
            scroll.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        scrollComputerIntoView(last, in: app)
        expectation(for: ready, evaluatedWith: last)
        waitForExpectations(timeout: 5)
        attachScreenshot(app, name: "64 Computer Library End")
        let metadata = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "computerCount": 64, "previewWidth": 480, "previewHeight": 300,
            "fastSwipesPerMeasuredIteration": 6, "previewSource": "generated QA images",
            "fullTraversal": "separate correctness check outside measured interval"]), uniformTypeIdentifier: "public.json")
        metadata.name = "Large Library Dataset"
        metadata.lifetime = .keepAlways
        add(metadata)
    }

    private func verifyControlledComputerPreview(language: String, measureScrolling: Bool = false) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        let name = "QA Preview " + UUID().uuidString
        app.launch()
        let card = app.buttons[label("Connect to " + name, "连接到 " + name)].firstMatch
        defer {
            app.terminate(); app.launch()
            if card.waitForExistence(timeout: 5) {
                scrollComputerIntoView(card, in: app)
                card.press(forDuration: 1)
                let delete = app.buttons[label("Delete", "删除")].firstMatch
                if delete.waitForExistence(timeout: 3) { delete.tap() }
                XCTAssertFalse(card.waitForExistence(timeout: 1), "Owned preview computer must be removed")
            }
        }
        app.buttons[label("Add Computer", "添加电脑")].tap()
        let nameField = app.textFields[label("Name (e.g. Studio Mac)", "名称（如 工作室 Mac）")]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText(name)
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Save", "保存")].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        scrollComputerIntoView(card, in: app)
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Preview Source Desktop " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        scrollComputerIntoView(card, in: app)
        let previewReady = NSPredicate(format: "value == %@", label("Desktop preview available", "桌面预览已就绪"))
        expectation(for: previewReady, evaluatedWith: card)
        waitForExpectations(timeout: 5)
        attachScreenshot(app, name: "Warm Computer Preview " + language)
        app.terminate(); app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        scrollComputerIntoView(card, in: app)
        expectation(for: previewReady, evaluatedWith: card)
        waitForExpectations(timeout: 5)
        attachScreenshot(app, name: "Cold Computer Preview " + language)
        if measureScrolling {
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists)
            scroll.swipeDown(velocity: .fast)
            var metrics: [XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                                       XCTMemoryMetric(application: app)]
            if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            options.invocationOptions = [.manuallyStop]
            measure(metrics: metrics, options: options) {
                scroll.swipeUp(velocity: .fast)
                stopMeasuring()
                // Reset outside the measured interval so each iteration starts at the top.
                scroll.swipeDown(velocity: .fast)
            }
            attachScreenshot(app, name: "Computer List After Scrolling Measurement")
        }
    }
    func testChineseControlledConnectionRecovery() throws { try verifyControlledConnectionRecovery(language: "zh-Hans") }

    func testControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "en") }
    func testChineseControlledViewportNavigation() throws { try verifyControlledViewportNavigation(language: "zh-Hans") }

    func testControlledDisplaySelection() throws { try verifyControlledDisplaySelection(language: "en") }
    func testChineseControlledDisplaySelection() throws { try verifyControlledDisplaySelection(language: "zh-Hans") }

    func testControlledFullscreenGestures() throws { try verifyControlledFullscreenGestures(language: "en") }
    func testChineseControlledFullscreenGestures() throws { try verifyControlledFullscreenGestures(language: "zh-Hans") }

    private func verifyControlledFullscreenGestures(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let normalOptionsY = app.buttons[label("Session Options", "会话选项")].frame.minY
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        let fullscreenReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.value as? String == label("Full Screen", "全屏")
        }, object: nil)
        guard XCTWaiter.wait(for: [fullscreenReady], timeout: 3) == .completed else {
            XCTFail("One two-finger double-tap must enter fullscreen")
            return
        }
        XCTAssertEqual(input.value as? String, label("Full Screen", "全屏"))
        XCTAssertFalse(app.buttons[label("Session Options", "会话选项")].exists)
        XCTAssertFalse(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        XCTAssertTrue(try gesturePointers().isEmpty, "Fullscreen must not deliver a right click")
        attachScreenshot(app, name: "Controlled Fullscreen " + language)
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
        XCTAssertTrue(try gesturePointers().isEmpty)
        attachScreenshot(app, name: "Controlled Fullscreen Restored " + language)
        // Repeated native gestures catch layout publication races; each gesture
        // must succeed once, without corrective taps or remote pointer packets.
        for _ in 0..<3 {
            input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
            let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                input.value as? String == label("Full Screen", "全屏")
            }, object: nil)
            guard XCTWaiter.wait(for: [entered], timeout: 3) == .completed else {
                XCTFail("Repeated fullscreen entry must succeed on one gesture")
                return
            }
            XCTAssertFalse(app.buttons[label("Session Options", "会话选项")].exists)
            input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
            XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].exists)
            XCTAssertTrue(try gesturePointers().isEmpty)
        }
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        let observeFullscreenReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.value as? String == label("Full Screen", "全屏")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [observeFullscreenReady], timeout: 3), .completed)
        _ = try gestureFixtureData(path: "drop")
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].exists, "A failed fullscreen session must expose recovery and disconnect controls")
        // iOS 27 does not expose the system status bar in this app's XCTest
        // hierarchy. Verify recovery restores the normal safe-area placement,
        // then retain its rendered screenshot for status-bar inspection.
        let recoveryLayout = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(app.buttons[label("Session Options", "会话选项")].frame.minY - normalOptionsY) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recoveryLayout], timeout: 3), .completed,
                       "Recovery restores the same top-control position as normal mode")
        attachScreenshot(app, name: "Controlled Fullscreen Connection Lost " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Reconnect", "重新连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, label("Full Screen", "全屏"), "Reconnect preserves the fullscreen preference")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 2, numberOfTouches: 2)
        XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].waitForExistence(timeout: 3))
        XCTAssertTrue(try gesturePointers().isEmpty, "Observe fullscreen remains a local action")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func verifyControlledDisplaySelection(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureDisplayFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Session Options", "会话选项")].tap()
        XCTAssertTrue(app.buttons[label("Display 1", "显示器 1")].waitForExistence(timeout: 3))
        app.buttons[label("Display 2", "显示器 2")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let selected = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(selected["x"])), 528, accuracy: 5, "Visible crop and input must use the selected monitor's width and origin")
        XCTAssertEqual(Double(try XCTUnwrap(selected["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Controlled Selected Right Display " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("All Displays", "全部显示器")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let full = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(full["x"])), 416, accuracy: 5)
        attachScreenshot(app, name: "Controlled Full Desktop " + language)
        // The framebuffer and its pixels stay unchanged: the monitor menu must
        // refresh from the layout publication itself, rather than another frame.
        _ = try gestureFixtureData(path: "three-displays")
        app.buttons[label("Session Options", "会话选项")].tap()
        XCTAssertTrue(app.buttons[label("Display 3", "显示器 3")].waitForExistence(timeout: 3))
        app.buttons[label("Display 3", "显示器 3")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let changed = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(changed["x"])), 565, accuracy: 5)
        attachScreenshot(app, name: "Controlled Live Layout Change " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledRotationMapping() throws { try verifyControlledRotationMapping(language: "en") }
    func testChineseControlledRotationMapping() throws { try verifyControlledRotationMapping(language: "zh-Hans") }

    private func verifyControlledRotationMapping(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        for zoomed in [false, true] {
            if zoomed { input.pinch(withScale: 1.8, velocity: 1) }
            for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight] {
                XCUIDevice.shared.orientation = orientation
                let landscape = orientation != .portrait
                let window = app.windows.firstMatch
                let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    landscape ? window.frame.width > window.frame.height : window.frame.height > window.frame.width
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
                XCTAssertTrue(app.buttons[label("Disconnect", "断开连接")].isHittable)
                XCTAssertTrue(app.buttons[label("Session Options", "会话选项")].isHittable)
                XCTAssertTrue(app.buttons[label("Show Keyboard", "显示键盘")].isHittable)
                try resetGestureFixture()
                input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let center = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }.first { $0["mask"] == 1 })
                XCTAssertEqual(Double(try XCTUnwrap(center["x"])), 320, accuracy: 5)
                XCTAssertEqual(Double(try XCTUnwrap(center["y"])), 180, accuracy: 5)
                if !zoomed {
                    try resetGestureFixture()
                    input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
                    let offset = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
                    XCTAssertEqual(Double(try XCTUnwrap(offset["x"])), 416, accuracy: 5)
                }
                attachScreenshot(app, name: "Rotation " + language + " " + String(orientation.rawValue) + (zoomed ? " zoomed" : " fit"))
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Rotation hierarchy " + language + " " + String(orientation.rawValue) + (zoomed ? " zoomed" : " fit")
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                try attachGesturePackets(try gesturePointers(), name: "Rotation mapping packets")
            }
        }
    }

    private func verifyControlledViewportNavigation(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        input.pinch(withScale: 1.5, velocity: 1)
        let center = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        try resetGestureFixture()
        center.tap()
        let before = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        app.buttons[label("Session Options", "会话选项")].tap()
        let pan = app.buttons[label("Pan View", "移动视图")]
        XCTAssertTrue(pan.waitForExistence(timeout: 3), "Zoomed iOS sessions must expose local viewport navigation")
        guard pan.exists else { return }
        pan.tap()
        XCTAssertTrue(app.staticTexts[label("Pan · " + gestureFixtureHost, "移动视图 · " + gestureFixtureHost)].exists)
        try resetGestureFixture()
        center.press(forDuration: 0.05, thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        center.tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Local panning and taps must not send remote input")
        attachScreenshot(app, name: "Controlled Local Pan " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Pan View", "移动视图")].tap()
        center.tap()
        let after = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertLessThan(after, before - 20, "Local panning must actually move the displayed remote viewport")
        try attachGesturePackets(try gesturePointers(), name: "Received Touch After Local Pan " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 3), "Observe must retain local navigation")
        try resetGestureFixture()
        input.pinch(withScale: 1.3, velocity: 1)
        center.press(forDuration: 0.4, thenDragTo: input.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        center.tap()
        XCTAssertTrue(try gesturePointers().isEmpty)
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        attachScreenshot(app, name: "Controlled Observe Navigation " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        center.tap()
        let observed = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertGreaterThan(observed, after + 30, "Observe navigation must move the viewport while suppressing remote input")
        try attachGesturePackets(try gesturePointers(), name: "Received Touch After Observe Navigation " + language)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Fit to Window", "适应窗口")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let fitted = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 }?["x"])
        XCTAssertEqual(Double(fitted), 416, accuracy: 5, "Fit must reset both zoom and viewport offset")
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    private func revealToolbarAction(_ action: String, in app: XCUIApplication) -> XCUIElement {
        let scroll = app.scrollViews["keyboard-toolbar-scroll"]
        let button = app.buttons["keyboard-action-" + action]
        XCTAssertTrue(button.exists)
        for _ in 0..<6 {
            let vertical = scroll.frame.height > scroll.frame.width
            let bounds = scroll.frame.insetBy(dx: vertical ? 0 : 8, dy: vertical ? 8 : 0)
            if bounds.contains(button.frame) { break }
            let maximum = vertical ? button.frame.maxY : button.frame.maxX
            let minimum = vertical ? button.frame.minY : button.frame.minX
            let visibleMaximum = vertical ? bounds.maxY : bounds.maxX
            let visibleMinimum = vertical ? bounds.minY : bounds.minX
            let length = vertical ? scroll.frame.height : scroll.frame.width
            let direction: CGFloat = maximum > visibleMaximum ? -1 : 1
            let overflow = direction < 0 ? maximum - visibleMaximum : visibleMinimum - minimum
            let distance = min(length * 0.45, max(60, overflow + 16)) / length
            let start: CGFloat = direction < 0 ? 0.8 : 0.2
            let from = CGVector(dx: vertical ? 0.5 : start, dy: vertical ? start : 0.5)
            let to = CGVector(dx: vertical ? 0.5 : start + direction * distance, dy: vertical ? start + direction * distance : 0.5)
            scroll.coordinate(withNormalizedOffset: from)
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: to), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let vertical = scroll.frame.height > scroll.frame.width
        XCTAssertTrue(scroll.frame.insetBy(dx: vertical ? 0 : 8, dy: vertical ? 8 : 0).contains(button.frame), "Toolbar control must be fully visible before tapping")
        return button
    }

    func testControlledFloatingToolbar() throws { try verifyFloatingToolbar(language: "en") }
    func testChineseControlledFloatingToolbar() throws { try verifyFloatingToolbar(language: "zh-Hans") }

    private func verifyFloatingToolbar(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap(); app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let bounds = input.frame
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        app.buttons["keyboard-position"].tap()
        let floating = app.buttons[label("Floating", "浮动")]
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssertFalse(floating.exists, "Floating mode belongs to iPad")
            app.buttons[label("Bottom", "底部")].tap()
            app.buttons[label("Done", "完成")].tap()
            app.buttons[label("Disconnect", "断开连接")].tap()
            return
        }
        XCTAssertTrue(floating.exists); floating.tap()
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let handle = app.descendants(matching: .any)["floating-toolbar-handle"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        revealToolbarAction("Fn", in: app).tap()
        XCTAssertTrue(app.scrollViews["keyboard-function-row"].waitForExistence(timeout: 5))
        let originalY = handle.frame.midY
        let originalX = handle.frame.midX
        try resetGestureFixture()
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 60, dy: -80)))
        XCTAssertLessThan(handle.frame.midY, originalY - 40)
        XCTAssertGreaterThan(handle.frame.midX, originalX + 30, "Expanded floating toolbar must move horizontally too")
        XCTAssertTrue(try gesturePointers().isEmpty, "Toolbar dragging must stay local")
        attachScreenshot(app, name: "Floating toolbar moved " + language)
        let collapse = app.buttons["floating-toolbar-collapse"]
        collapse.tap()
        XCTAssertEqual(collapse.label, label("Expand Keyboard Toolbar", "展开键盘工具栏"))
        XCTAssertFalse(app.scrollViews["keyboard-toolbar-scroll"].isHittable)
        // The label changes before the collapse spring has settled. Starting
        // a drag from its moving frame can miss the button entirely.
        func waitForStableCollapseFrame() {
            var previous = collapse.frame
            var unchangedSince = ProcessInfo.processInfo.systemUptime
            let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let current = collapse.frame
                let now = ProcessInfo.processInfo.systemUptime
                if abs(current.midX - previous.midX) > 0.5 || abs(current.midY - previous.midY) > 0.5 {
                    previous = current
                    unchangedSince = now
                    return false
                }
                return collapse.isHittable && now - unchangedSince >= 0.35
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 5), .completed)
        }
        waitForStableCollapseFrame()
        let original = collapse.frame
        let collapsedStart = collapse.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        collapsedStart.press(forDuration: 0.05, thenDragTo: collapsedStart.withOffset(CGVector(dx: 80, dy: -50)))
        waitForStableCollapseFrame()
        XCTAssertGreaterThan(collapse.frame.midX, original.midX + 40)
        XCTAssertLessThan(collapse.frame.midY, original.midY - 20)
        XCTAssertEqual(collapse.label, label("Expand Keyboard Toolbar", "展开键盘工具栏"))
        XCTAssertTrue(try gesturePointers().isEmpty)
        attachScreenshot(app, name: "Collapsed floating toolbar moved " + language)
        collapse.press(forDuration: 1)
        let escape = app.buttons[label("esc", "esc")]
        XCTAssertTrue(escape.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(escape.frame.height, 44, "Quick actions need comfortable touch targets")
        attachScreenshot(app, name: "Floating toolbar quick menu " + language)
        escape.tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["key"] as? Int == 65307 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        XCTAssertEqual(collapse.label, label("Expand Keyboard Toolbar", "展开键盘工具栏"), "Quick actions must leave the toolbar collapsed")
        collapse.tap()
        XCTAssertTrue(app.scrollViews["keyboard-function-row"].isHittable, "Collapse must preserve expanded rows")
        revealToolbarAction("Type", in: app).tap()
        let text = app.textFields["keyboard-text-input"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap(); text.typeText("QA")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        collapse.tap()
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 3), .completed, "Collapsing focused text must dismiss the software keyboard")
        attachScreenshot(app, name: "Floating focused text collapsed " + language)
        collapse.tap()
        XCTAssertEqual(text.value as? String, "QA", "Collapsing must retain the unsent draft")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Expanding a retained draft must not reopen the keyboard without a field tap")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        XCTAssertEqual(text.value as? String, "QA")
        XCTAssertTrue(collapse.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(collapse.frame), "Rotation must keep the floating controls on screen")
        attachScreenshot(app, name: "Floating draft portrait " + language)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons[label("Close Text Input", "关闭文字输入")].tap()
        let closedKeyboard = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [closedKeyboard], timeout: 3), .completed)
        XCTAssertEqual(input.frame, bounds)
        app.buttons[label("Hide Keyboard", "隐藏键盘")].tap()
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let down = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(down["x"])), 320, accuracy: 5)
        XCTAssertEqual(Double(try XCTUnwrap(down["y"])), 180, accuracy: 5)
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledCarouselToolbar() throws { try verifyCarouselToolbar(language: "en") }
    func testChineseControlledCarouselToolbar() throws { try verifyCarouselToolbar(language: "zh-Hans") }

    private func verifyCarouselToolbar(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap(); app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let originalBounds = input.frame
        let oldConnection = try lastFixtureConnection()
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        app.buttons["keyboard-position"].tap()
        app.buttons[label("Carousel", "环形")].tap()
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let ring = app.descendants(matching: .any)["carousel-expanded"].firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["keyboard-toolbar-scroll"].exists)
        XCTAssertEqual(input.frame, originalBounds)
        XCTAssertEqual(ring.frame.width, ring.frame.height, accuracy: 2)
        let before = ring.frame
        try resetGestureFixture()
        ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).press(forDuration: 0.1,
            thenDragTo: ring.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertNotEqual(ring.frame, before)
        XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: 4, dy: 4).contains(ring.frame))
        XCTAssertTrue(try fixtureEvents().filter { $0["type"] as? String == "pointer" }.isEmpty, "Moving the local ring must not move or click the remote cursor")
        attachScreenshot(app, name: "Carousel moved " + language)
        app.buttons["carousel-group-modifiers"].tap()
        let shift = app.buttons["carousel-modifier-shift"]
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        shift.tap()
        XCTAssertEqual(shift.value as? String, label("Next action", "下一次操作"))
        shift.tap()
        XCTAssertEqual(shift.value as? String, label("Locked", "已锁定"))
        attachScreenshot(app, name: "Carousel locked modifier menu " + language)
        shift.tap()
        XCTAssertEqual(shift.value as? String, label("Inactive", "未启用"))
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-navigation"].tap()
        let pageDown = app.buttons["carousel-key-Page Down"]
        XCTAssertTrue(pageDown.waitForExistence(timeout: 5))
        pageDown.tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["key"] as? Int == 65366 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        attachScreenshot(app, name: "Carousel navigation menu " + language)
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-edit"].tap()
        try resetGestureFixture()
        app.buttons["carousel-edit-Copy"].tap()
        let copied = try waitForFixtureEvents { $0.contains { $0["key"] as? Int == 65515 && $0["down"] as? Int == 0 } }
            .filter { $0["type"] as? String == "key" }
        XCTAssertEqual(copied.compactMap { $0["key"] as? Int }, [65515, 99, 99, 65515])
        XCTAssertEqual(copied.compactMap { $0["down"] as? Int }, [1, 1, 0, 0])
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-functionKeys"].tap()
        try resetGestureFixture()
        let f12 = app.buttons["carousel-key-F12"]
        XCTAssertTrue(f12.waitForExistence(timeout: 5))
        f12.tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["key"] as? Int == 65481 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        attachScreenshot(app, name: "Carousel function menu " + language)
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-shortcuts"].tap()
        try resetGestureFixture()
        app.buttons["carousel-shortcut-Spotlight (⌘Space)"].tap()
        let spotlight = try waitForFixtureEvents { $0.contains { $0["key"] as? Int == 65515 && $0["down"] as? Int == 0 } }
            .filter { $0["type"] as? String == "key" }
        XCTAssertEqual(spotlight.compactMap { $0["key"] as? Int }, [65515, 32, 32, 65515])
        XCTAssertEqual(spotlight.compactMap { $0["down"] as? Int }, [1, 1, 0, 0])
        attachScreenshot(app, name: "Carousel shortcuts menu " + language)
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-actions"].tap()
        app.buttons["carousel-action-fit"].tap()
        XCTAssertEqual(input.frame, originalBounds)
        app.buttons["carousel-menu-done"].tap()
        app.buttons["carousel-group-typing"].tap()
        let text = app.textFields["carousel-text-input"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText("QA")
        XCTAssertEqual(text.value as? String, "QA")
        app.buttons["carousel-menu-done"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.keyboards.firstMatch.exists && input.frame == originalBounds }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 3), .completed)
        app.buttons["carousel-group-typing"].tap()
        XCTAssertEqual(text.value as? String, "QA", "Dismissal preserves the unsent draft")
        try resetGestureFixture()
        app.buttons["carousel-text-send"].tap()
        _ = try waitForFixtureEvents { events in
            [81, 65].allSatisfy { key in
                events.contains { $0["key"] as? Int == key && $0["down"] as? Int == 1 } &&
                events.contains { $0["key"] as? Int == key && $0["down"] as? Int == 0 }
            }
        }
        app.buttons["carousel-menu-done"].tap()
        try resetGestureFixture()
        // Touch the ring's center hole: the underlying desktop must receive it.
        let center = ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.tap()
        _ = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let expand = app.buttons["carousel-expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 3))
        attachScreenshot(app, name: "Carousel remote interaction minimized " + language)
        try resetGestureFixture()
        expand.tap()
        XCTAssertTrue(ring.waitForExistence(timeout: 3))
        XCTAssertTrue(try fixtureEvents().filter { $0["type"] as? String == "pointer" }.isEmpty)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.insetBy(dx: 4, dy: 4).contains(ring.frame))
        attachScreenshot(app, name: "Carousel portrait " + language)
        _ = try gestureFixtureData(path: "drop")
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["carousel-group-navigation"].isEnabled)
        XCTAssertFalse(app.buttons["carousel-group-functionKeys"].isEnabled)
        XCTAssertTrue(app.buttons["carousel-group-actions"].isEnabled)
        attachScreenshot(app, name: "Carousel disconnected controls " + language)
        app.buttons["carousel-group-actions"].tap()
        app.buttons["carousel-action-reconnect"].tap()
        _ = try waitForFixtureEvents { events in
            events.contains { $0["type"] as? String == "ready" && $0["connection"] as? Int != oldConnection }
        }
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let newConnection = try lastFixtureConnection()
        XCTAssertNotEqual(oldConnection, newConnection)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.buttons["carousel-group-functionKeys"].isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed)
        app.buttons["carousel-group-functionKeys"].tap()
        app.buttons["carousel-key-F1"].tap()
        _ = try waitForFixtureEvents { events in
            events.contains { $0["connection"] as? Int == newConnection && $0["key"] as? Int == 65470 && $0["down"] as? Int == 0 }
        }
        attachScreenshot(app, name: "Carousel reconnected function menu " + language)
        app.buttons["carousel-menu-done"].tap()
        app.buttons[label("Hide Keyboard", "隐藏键盘")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledToolbarRepeat() throws { try verifyToolbarRepeat(language: "en") }
    func testChineseControlledToolbarRepeat() throws { try verifyToolbarRepeat(language: "zh-Hans") }

    private func verifyToolbarRepeat(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let bounds = input.frame
        func setRepeat(_ en: String, _ zh: String) {
            app.buttons[label("Session Options", "会话选项")].tap()
            app.buttons["session-customize-keyboard"].tap()
            let picker = app.buttons["keyboard-repeat"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            app.buttons[label(en, zh)].tap()
            attachScreenshot(app, name: "Key repeat settings " + en + " " + language)
            app.buttons[label("Done", "完成")].tap()
        }
        setRepeat("Off", "关闭")
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let right = revealToolbarAction("Right Arrow", in: app)
        try resetGestureFixture()
        right.press(forDuration: 1.0)
        let off = try waitForFixtureEvents { $0.contains { $0["key"] as? Int == 65363 && $0["down"] as? Int == 0 } }
            .filter { $0["key"] as? Int == 65363 }
        XCTAssertEqual(off.count, 2, "Disabled repeat keeps one tap on release")
        setRepeat("Fast", "快速")
        try resetGestureFixture()
        revealToolbarAction("Shift", in: app).tap()
        revealToolbarAction("Right Arrow", in: app).press(forDuration: 1.0)
        let held = try waitForFixtureEvents { $0.contains { $0["key"] as? Int == 65505 && $0["down"] as? Int == 0 } }
            .filter { $0["type"] as? String == "key" }
        let arrows = held.filter { $0["key"] as? Int == 65363 }
        XCTAssertGreaterThanOrEqual(arrows.filter { $0["down"] as? Int == 1 }.count, 3)
        XCTAssertEqual(arrows.filter { $0["down"] as? Int == 0 }.count, 1)
        XCTAssertEqual(held.first?["key"] as? Int, 65505)
        XCTAssertEqual(held.first?["down"] as? Int, 1)
        XCTAssertEqual(held.last?["key"] as? Int, 65505)
        XCTAssertEqual(held.last?["down"] as? Int, 0, "Once Shift releases after the held arrow, never during repeats")
        let count = held.count
        let quiet = expectation(description: "No repeat after release")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertEqual(try fixtureEvents().filter { $0["type"] as? String == "key" }.count, count)
        let wire = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        wire.name = "Held Shift right arrow wire " + language; wire.lifetime = .keepAlways; add(wire)
        attachScreenshot(app, name: "Repeat released canvas " + language)
        XCTAssertEqual(input.frame, bounds)
        app.buttons[label("Hide Keyboard", "隐藏键盘")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
    }

    func testControlledToolbarRotation() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = makeApp()
        app.launch()
        defer { app.terminate() }
        app.buttons["Quick Connect"].tap()
        let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields["Port"], with: gestureFixturePort)
        app.buttons["Connect"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Input Mode"].tap(); app.buttons["Touch"].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let initialBounds = input.frame
        app.buttons["Show Keyboard"].tap()
        revealToolbarAction("Fn", in: app).tap()
        XCTAssertTrue(app.scrollViews["keyboard-function-row"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        let scroll = app.scrollViews["keyboard-toolbar-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(scroll.frame.width, scroll.frame.height)
        XCTAssertTrue(app.scrollViews["keyboard-function-row"].exists, "Rotation must preserve expanded controls")
        attachScreenshot(app, name: "Portrait toolbar after rotation")
        app.buttons["F1"].tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["key"] as? Int == 65470 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.scrollViews["keyboard-function-row"].exists)
        XCTAssertEqual(input.frame, initialBounds)
        try resetGestureFixture()
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let down = try XCTUnwrap(try waitForGesturePointers { $0.contains { $0["mask"] == 1 } }.first { $0["mask"] == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(down["x"])), 320, accuracy: 5)
        XCTAssertEqual(Double(try XCTUnwrap(down["y"])), 180, accuracy: 5)
        attachScreenshot(app, name: "Landscape toolbar after rotation")
        app.buttons["Disconnect"].tap()
    }

    func testControlledToolbarInteraction() throws { try verifyControlledToolbarInteraction(language: "en") }
    func testChineseControlledToolbarInteraction() throws { try verifyControlledToolbarInteraction(language: "zh-Hans") }

    private func verifyControlledToolbarInteraction(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer { app.terminate() }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 10))
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        let initialBounds = input.frame
        for cycle in 0..<3 {
            app.buttons[label("Show Keyboard", "显示键盘")].tap()
            let scroll = app.scrollViews["keyboard-toolbar-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            if UIDevice.current.userInterfaceIdiom == .phone {
                XCTAssertLessThan(scroll.frame.width, 180, "Landscape phone toolbar must dock at the side")
                XCTAssertGreaterThan(scroll.frame.height, scroll.frame.width)
                XCTAssertLessThan(scroll.frame.minX, input.frame.midX)
            }
            XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].isHittable)
            app.buttons[label("Hide Keyboard", "隐藏键盘")].tap()
            XCTAssertFalse(scroll.exists)
            try resetGestureFixture()
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let packets = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
            let down = try XCTUnwrap(packets.first { $0["mask"] == 1 })
            XCTAssertEqual(Double(try XCTUnwrap(down["x"])), 320, accuracy: 5)
            XCTAssertEqual(Double(try XCTUnwrap(down["y"])), 180, accuracy: 5)
            try attachGesturePackets(packets, name: "Toolbar cycle \(cycle) pointer " + language)
        }
        XCTAssertEqual(input.frame, initialBounds, "Toolbar overlays must not resize or remap the desktop")
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let scroll = app.scrollViews["keyboard-toolbar-scroll"]
        func reveal(_ action: String) -> XCUIElement { revealToolbarAction(action, in: app) }
        let repeatRight = reveal("Right Arrow")
        try resetGestureFixture()
        repeatRight.press(forDuration: 1.0)
        let repeated = try waitForFixtureEvents { events in
            events.contains { $0["key"] as? Int == 65363 && $0["down"] as? Int == 0 }
        }.filter { $0["key"] as? Int == 65363 }
        XCTAssertGreaterThanOrEqual(repeated.filter { $0["down"] as? Int == 1 }.count, 3)
        XCTAssertEqual(repeated.filter { $0["down"] as? Int == 0 }.count, 1, "Release once, with no extra tap after a hold")
        let quiet = expectation(description: "No repeat after release")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { quiet.fulfill() }
        wait(for: [quiet], timeout: 1)
        XCTAssertEqual(try fixtureEvents().filter { $0["key"] as? Int == 65363 }.count, repeated.count)
        try resetGestureFixture()
        repeatRight.tap()
        let tapped = try waitForFixtureEvents { events in
            events.contains { $0["key"] as? Int == 65363 && $0["down"] as? Int == 0 }
        }.filter { $0["key"] as? Int == 65363 }
        XCTAssertEqual(tapped.count, 2, "A short tap must remain one down/up pair")
        attachScreenshot(app, name: "Toolbar repeat released " + language)
        try resetGestureFixture()
        reveal("Fn").tap()
        let functionRow = app.scrollViews["keyboard-function-row"]
        XCTAssertTrue(functionRow.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Expanded function toolbar " + language)
        app.buttons["F1"].tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["type"] as? String == "key" && $0["key"] as? Int == 65470 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        reveal("Type").tap()
        let text = app.textFields["keyboard-text-input"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Expanded text and function toolbar " + language)
        text.tap(); text.typeText("QA")
        app.buttons[label("Send", "发送")].tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["type"] as? String == "key" }
            return [81, 65].allSatisfy { key in
                keys.contains { $0["key"] as? Int == key && $0["down"] as? Int == 1 } &&
                keys.contains { $0["key"] as? Int == key && $0["down"] as? Int == 0 }
            }
        }
        app.buttons[label("Close Text Input", "关闭文字输入")].tap()
        XCTAssertFalse(text.exists)
        reveal("Fn").tap()
        XCTAssertFalse(functionRow.exists)
        XCTAssertEqual(input.frame, initialBounds)
        let received = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        received.name = "Toolbar received keys " + language; received.lifetime = .keepAlways; add(received)
        attachScreenshot(app, name: "Collapsed extra toolbar rows " + language)
        let shift = reveal("Shift")
        try resetGestureFixture()
        shift.tap()
        XCTAssertEqual(shift.value as? String, label("Next action", "下一次操作"))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = try waitForFixtureEvents { events in
            let keys = events.filter { $0["type"] as? String == "key" && $0["key"] as? Int == 65505 }
            return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
        }
        XCTAssertEqual(shift.value as? String, label("Inactive", "未启用"))
        attachScreenshot(app, name: "Once modifier after remote click " + language)
        try resetGestureFixture()
        shift.tap(); shift.tap()
        XCTAssertEqual(shift.value as? String, label("Locked", "已锁定"))
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(shift.value as? String, label("Locked", "已锁定"))
        let heldKeys = try fixtureEvents().filter { $0["type"] as? String == "key" && $0["key"] as? Int == 65505 }
        XCTAssertFalse(heldKeys.contains { $0["down"] as? Int == 0 }, "A locked modifier must survive the remote click")
        attachScreenshot(app, name: "Locked modifier after remote click " + language)
        shift.tap()
        _ = try waitForFixtureEvents { events in events.contains { $0["type"] as? String == "key" && $0["key"] as? Int == 65505 && $0["down"] as? Int == 0 } }
        XCTAssertEqual(shift.value as? String, label("Inactive", "未启用"))
        let modifiers = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        modifiers.name = "Locked modifier pointer sequence " + language; modifiers.lifetime = .keepAlways; add(modifiers)
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        XCTAssertTrue(app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")].waitForExistence(timeout: 5))
        let navigationKeys = [("Home", 65360), ("End", 65367), ("Page Up", 65365), ("Page Down", 65366)]
        for (action, _) in navigationKeys {
            let toggle = app.switches["keyboard-visible-" + action]
            for _ in 0..<32 {
                let form = try XCTUnwrap(app.collectionViews.allElementsBoundByIndex.first { $0.isHittable })
                let navigationBar = app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")]
                let visibleTop = max(form.frame.minY, navigationBar.frame.maxY) + 8
                let visibleBottom = form.frame.maxY - 30
                if toggle.exists && toggle.isHittable && toggle.frame.minY >= visibleTop && toggle.frame.maxY <= visibleBottom { break }
                // Short drags cannot skip an entire row on a landscape phone.
                // Reverse if an existing target is covered by the navigation bar.
                let direction: CGFloat = toggle.exists && toggle.frame.minY < visibleTop ? 1 : -1
                form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                    .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6 + direction * 0.25)), withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            XCTAssertTrue(toggle.exists && toggle.isHittable)
            XCTAssertEqual(toggle.value as? String, "0", "Optional navigation controls must default to hidden")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        attachScreenshot(app, name: "Navigation toolbar customization " + language)
        app.buttons[label("Done", "完成")].tap()
        try resetGestureFixture()
        for (action, key) in navigationKeys {
            reveal(action).tap()
            _ = try waitForFixtureEvents { events in
                let keys = events.filter { $0["type"] as? String == "key" && $0["key"] as? Int == key }
                return keys.contains { $0["down"] as? Int == 1 } && keys.contains { $0["down"] as? Int == 0 }
            }
        }
        let navigationPackets = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        navigationPackets.name = "Received navigation toolbar keys " + language; navigationPackets.lifetime = .keepAlways; add(navigationPackets)
        attachScreenshot(app, name: "Navigation keys enabled " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testControlledFirstFrameTimeoutRecovery() throws { try verifyFirstFrameTimeout(language: "en") }
    func testChineseControlledFirstFrameTimeoutRecovery() throws { try verifyFirstFrameTimeout(language: "zh-Hans") }

    private func verifyFirstFrameTimeout(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires controlled fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        defer {
            app.terminate()
            _ = try? gestureFixtureData(path: "reset")
        }
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        replacePort(app.textFields[label("Port", "端口")], with: gestureFixturePort)
        _ = try gestureFixtureData(path: "stall-next")
        app.buttons[label("Connect", "连接")].tap()
        let guidance = app.staticTexts[label("Connected, but no desktop image arrived. Check the remote Mac's Screen Sharing session and retry.", "已连接，但未收到桌面画面。请检查远程 Mac 的屏幕共享会话后重试。")]
        XCTAssertTrue(guidance.waitForExistence(timeout: 30))
        let oldConnection = try lastFixtureConnection()
        attachScreenshot(app, name: "First frame timeout " + language)
        app.buttons[label("Retry Connection", "重试连接")].tap()
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertNotEqual(try lastFixtureConnection(), oldConnection)
        XCTAssertFalse(guidance.exists)
        attachScreenshot(app, name: "First frame retry recovered " + language)
    }

    private func verifyControlledConnectionRecovery(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else { throw XCTSkip("Requires the loopback RFB fixture") }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        try resetGestureFixture()
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let oldConnection = try lastFixtureConnection()
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        input.pinch(withScale: 1.5, velocity: 1)
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        let shift = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Shift")).firstMatch
        XCTAssertTrue(shift.waitForExistence(timeout: 5))
        shift.tap()
        _ = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "key" && $0["key"] as? Int == 65505 && $0["down"] as? Int == 1 } }
        _ = try gestureFixtureData(path: "drop")
        XCTAssertTrue(app.buttons[label("Retry Connection", "重试连接")].waitForExistence(timeout: 10))
        attachScreenshot(app, name: "Controlled Remote Connection Lost " + language)
        app.buttons[label("Retry Connection", "重试连接")].tap()
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let newConnection = try lastFixtureConnection()
        XCTAssertNotEqual(newConnection, oldConnection, "Recovery must establish a new TCP session")
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).tap()
        let events = try waitForFixtureEvents { $0.contains { $0["type"] as? String == "pointer" && $0["connection"] as? Int == newConnection && $0["mask"] as? Int == 1 } }
        let click = try XCTUnwrap(events.first { $0["type"] as? String == "pointer" && $0["connection"] as? Int == newConnection && $0["mask"] as? Int == 1 })
        XCTAssertEqual(Double(try XCTUnwrap(click["x"] as? Int)), 384, accuracy: 5, "Recovery must preserve zoom and touch mode")
        shift.tap()
        let escape = app.buttons["esc"]
        let keyboardScroll = app.scrollViews["keyboard-toolbar-scroll"]
        for _ in 0..<3 {
            let bounds = keyboardScroll.frame
            let center = CGPoint(x: escape.frame.midX, y: escape.frame.midY)
            if bounds.contains(center) { break }
            let direction: CGFloat = center.x > bounds.maxX ? -1 : 1
            let distance = min(bounds.width * 0.4, max(40, abs(center.x - bounds.midX)))
            let startX: CGFloat = direction < 0 ? 0.8 : 0.2
            let start = keyboardScroll.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
            let end = keyboardScroll.coordinate(withNormalizedOffset: CGVector(dx: startX + direction * distance / bounds.width, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(keyboardScroll.frame.contains(CGPoint(x: escape.frame.midX, y: escape.frame.midY)))
        escape.tap()
        _ = try waitForFixtureEvents { events in
            let fresh = events.filter { $0["connection"] as? Int == newConnection && $0["type"] as? String == "key" }
            return fresh.contains { $0["key"] as? Int == 65505 && $0["down"] as? Int == 1 } && fresh.contains { $0["key"] as? Int == 65505 && $0["down"] as? Int == 0 }
        }
        let packets = XCTAttachment(data: try gestureFixtureData(path: "events"), uniformTypeIdentifier: "public.json")
        packets.name = "Received New Session Input " + language
        packets.lifetime = .keepAlways
        add(packets)
        attachScreenshot(app, name: "Controlled Remote Reconnected " + language)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    private func lastFixtureConnection() throws -> Int {
        let events = try fixtureEvents()
        return try XCTUnwrap(events.last { $0["type"] as? String == "ready" }?["connection"] as? Int)
    }

    private func fixtureEvents() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: gestureFixtureData(path: "events")) as? [[String: Any]])
    }

    private func waitForFixtureEvents(_ predicate: ([[String: Any]]) -> Bool) throws -> [[String: Any]] {
        let deadline = Date().addingTimeInterval(3)
        var events = try fixtureEvents()
        while !predicate(events), Date() < deadline { Thread.sleep(forTimeInterval: 0.025); events = try fixtureEvents() }
        XCTAssertTrue(predicate(events), "Expected received packets must reach the new session")
        return events
    }

    private func verifyReceivedNativeGestures(language: String) throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_QA"] == "1" else {
            throw XCTSkip("Requires the loopback gesture RFB fixture")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap(); host.typeText(gestureFixtureHost)
        let port = app.textFields[label("Port", "端口")]
        replacePort(port, with: gestureFixturePort)
        app.buttons[label("Connect", "连接")].tap()
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any)["remote-desktop-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.label, label("Remote desktop canvas", "远程桌面画布"))
        let center = input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        try resetGestureFixture()
        center.tap()
        var events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 1)
        try attachGesturePackets(events, name: "Received Single Click")
        try resetGestureFixture()
        center.doubleTap()
        events = try waitForGesturePointers { $0.filter { $0["mask"] == 1 }.count >= 2 && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 1 }.count, 2, "Double tap must deliver two clicks without triggering zoom")
        try attachGesturePackets(events, name: "Received Double Click")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 1, numberOfTouches: 2)
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 4 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 4 }.count, 1)
        try attachGesturePackets(events, name: "Received Two Finger Right Click")
        try resetGestureFixture()
        input.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 2 } && $0.last?["mask"] == 0 }
        XCTAssertEqual(events.filter { $0["mask"] == 2 }.count, 1)
        try attachGesturePackets(events, name: "Received Three Finger Middle Click")
        try resetGestureFixture()
        let end = input.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        center.press(forDuration: 0.4, thenDragTo: end)
        events = try waitForGesturePointers { $0.filter { $0["mask"] == 1 }.count > 1 && $0.last?["mask"] == 0 }
        XCTAssertGreaterThan(Set(events.filter { $0["mask"] == 1 }.compactMap { $0["x"] }).count, 1, "The server must receive movement while the button remains held")
        try attachGesturePackets(events, name: "Received Held Button Drag")

        app.buttons[label("Input Mode", "输入模式")].tap()
        app.buttons[label("Touch", "触控")].tap()
        let point = input.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
        try resetGestureFixture()
        point.tap()
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let beforeZoom = try XCTUnwrap(events.first { $0["mask"] == 1 }?["x"])
        XCTAssertEqual(Double(beforeZoom), 416, accuracy: 4)
        try attachGesturePackets(events, name: "Received Direct Touch Before Zoom")
        input.pinch(withScale: 1.5, velocity: 1)
        try resetGestureFixture()
        point.tap()
        events = try waitForGesturePointers { $0.contains { $0["mask"] == 1 } && $0.last?["mask"] == 0 }
        let afterZoom = try XCTUnwrap(events.first { $0["mask"] == 1 }?["x"])
        XCTAssertLessThan(afterZoom, beforeZoom - 10, "Pinch must change direct-touch mapping to the enlarged canvas")
        try attachGesturePackets(events, name: "Received Direct Touch After Zoom")
        attachScreenshot(app, name: "Received Gesture Desktop After Pinch")

        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons[label("Observe Only", "仅观看")].tap()
        try resetGestureFixture()
        frame.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(try gesturePointers().isEmpty, "Observe must suppress actual received input")
        XCTAssertFalse(app.buttons[label("Show Keyboard", "显示键盘")].isEnabled)
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    private func replacePort(_ field: XCUIElement, with value: String) {
        // Numeric fields may ignore Command+A. Tap at the trailing caret and
        // delete the existing digits as a person using the number pad would.
        let current = field.value as? String ?? ""
        let app = XCUIApplication()
        // On a landscape iPhone the host keyboard can cover the next row.
        // Scroll within the exposed part of the form before placing the caret.
        for _ in 0..<4 {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists, field.frame.intersects(keyboard.frame) else { break }
            let containers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let form = containers.first(where: { $0.isHittable && $0.frame.intersects(field.frame) }) else { break }
            let bounds = form.frame
            let bottom = min(bounds.maxY, keyboard.frame.minY - 4)
            guard bottom - bounds.minY >= 24 else { break }
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: bounds.width * 0.5, dy: bottom - bounds.minY - 4))
            let end = origin.withOffset(CGVector(dx: bounds.width * 0.5, dy: 4))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        if UIDevice.current.userInterfaceIdiom != .pad {
            field.tap()
        }
        // Place the caret before opening iPad's floating number pad, which
        // otherwise covers the trailing text position.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "The validated fixture port must be entered before connecting")
        let done = app.buttons["dismiss-port-keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private var gestureFixtureHost: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_HOST"] ?? "127.0.0.1"
    }

    private var gestureFixturePort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_RFB_PORT"] ?? "5999"
    }

    private var gestureDisplayFixturePort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_DISPLAY_PORT"] ?? "6000"
    }

    private var gestureInspectionPort: String {
        ProcessInfo.processInfo.environment["AETHERSCREENS_GESTURE_HTTP_PORT"] ?? "8768"
    }

    private func gesturePointers() throws -> [[String: Int]] {
        let value = try JSONSerialization.jsonObject(with: gestureFixtureData(path: "events"))
        return try XCTUnwrap(value as? [[String: Any]]).filter { $0["type"] as? String == "pointer" }.map {
            ["mask": $0["mask"] as? Int ?? -1, "x": $0["x"] as? Int ?? -1, "y": $0["y"] as? Int ?? -1]
        }
    }

    private func resetGestureFixture() throws {
        _ = try gestureFixtureData(path: "reset")
    }

    private func gestureFixtureData(path: String) throws -> Data {
        if ProcessInfo.processInfo.environment["AETHERSCREENS_QA_USB_RELAY"] == "1" {
            let relayDirectory = try XCTUnwrap(ProcessInfo.processInfo.environment["AETHERSCREENS_QA_USB_RELAY_DIR"])
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(relayDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID().uuidString
            try JSONSerialization.data(withJSONObject: ["id": id, "path": path])
                .write(to: directory.appendingPathComponent("request.json"), options: .atomic)
            let deadline = Date().addingTimeInterval(15)
            repeat {
                if let data = try? Data(contentsOf: directory.appendingPathComponent("response-" + id + ".json")),
                   let response = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                   response["id"] == id {
                    guard let encoded = response["payload"], let payload = Data(base64Encoded: encoded) else {
                        throw NSError(domain: "QAUSBRelay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Controlled fixture relay failed"])
                    }
                    return payload
                }
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            } while Date() < deadline
            throw NSError(domain: "QAUSBRelay", code: 2, userInfo: [NSLocalizedDescriptionKey: "Controlled USB relay timed out"])
        }
        let received = expectation(description: "Gesture fixture response")
        let response = GestureFixtureResponse()
        let task = URLSession.shared.dataTask(with: URL(string: "http://" + gestureFixtureHost + ":" + gestureInspectionPort + "/" + path)!) { data, http, error in
            if let error { response.set(.failure(error)) }
            else if let data, (http as? HTTPURLResponse)?.statusCode == 200 { response.set(.success(data)) }
            else { response.set(.failure(URLError(.badServerResponse))) }
            received.fulfill()
        }
        task.resume()
        wait(for: [received], timeout: 3)
        return try XCTUnwrap(response.get()).get()
    }

    private func attachGesturePackets(_ packets: [[String: Int]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: packets, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForGesturePointers(_ predicate: ([[String: Int]]) -> Bool) throws -> [[String: Int]] {
        let deadline = Date().addingTimeInterval(3)
        var events = try gesturePointers()
        while !predicate(events), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
            events = try gesturePointers()
        }
        XCTAssertTrue(predicate(events), "Expected gesture packets must reach the fixture")
        return events
    }

    func testConnectionLinkPreservesQuickConnectDraft() throws {
        guard ProcessInfo.processInfo.environment["AETHERSCREENS_URL_ROUTING_QA"] == "1" else {
            throw XCTSkip("Requires an external simulator URL delivery")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Quick Connect"].tap()
        let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText("draft-qa.invalid")
        print("AETHERSCREENS_URL_QA_READY")
        // The driver delivers a system URL while this form remains open.
        let deliveryWindow = expectation(description: "System URL delivery window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { deliveryWindow.fulfill() }
        wait(for: [deliveryWindow], timeout: 20)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmation = springboard.alerts.firstMatch
        if confirmation.exists {
            XCTAssertTrue(confirmation.label.contains("AetherScreens"))
            let open = confirmation.buttons["Open"].exists ? confirmation.buttons["Open"] : confirmation.buttons["打开"]
            XCTAssertTrue(open.exists)
            open.tap()
        }
        XCTAssertTrue(app.navigationBars["Quick Connect"].exists)
        XCTAssertEqual(host.value as? String, "draft-qa.invalid")
        attachScreenshot(app, name: "Connection Link Preserves Draft")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Observe · Link QA"].exists)
        XCTAssertFalse(app.buttons["Show Keyboard"].isEnabled)
        attachScreenshot(app, name: "Connection Link Observe Session")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Quick Connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Connect to Link QA"].exists)
    }

    func testEnglishMacAccountPrompt() throws { try verifyMacAccountPrompt(language: "en") }
    func testChineseMacAccountPrompt() throws { try verifyMacAccountPrompt(language: "zh-Hans") }

    private func verifyMacAccountPrompt(language: String) throws {
        guard let targetHost = ProcessInfo.processInfo.environment["AETHERSCREENS_MAC_ONLY_HOST"] else {
            throw XCTSkip("Requires an explicitly selected Mac-only authentication server")
        }
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap()
        host.typeText(targetHost)
        app.buttons[label("Connect", "连接")].tap()
        let username = app.textFields[label("Mac Account Username", "Mac 账户用户名")]
        XCTAssertTrue(username.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons[label("Connect", "连接")].isEnabled)
        username.tap()
        username.typeText("qa-placeholder")
        let password = app.secureTextFields[label("Mac Account Password", "Mac 账户密码")]
        password.tap()
        password.typeText("qa-placeholder")
        XCTAssertTrue(app.buttons[label("Connect", "连接")].isEnabled)
        attachScreenshot(app, name: "Mac Account Prompt " + language)
        // Verify the prompt without submitting dummy credentials to the Mac.
        app.buttons[label("Cancel", "取消")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testKeyboardCustomizationOnNarrowSession() {
        verifyKeyboardCustomization(language: "en")
    }

    func testChineseKeyboardCustomizationOnNarrowSession() {
        verifyKeyboardCustomization(language: "zh-Hans")
    }

    private func verifyKeyboardCustomization(language: String) {
        let chinese = language == "zh-Hans"
        func label(_ en: String, _ zh: String) -> String { chinese ? zh : en }
        let app = makeApp(language: language)
        app.launch()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 10))
        app.buttons[label("Quick Connect", "快速连接")].tap()
        let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
        host.tap()
        host.typeText("toolbar-qa.invalid")
        app.buttons[label("Connect", "连接")].tap()
        XCTAssertTrue(app.buttons[label("Disconnect", "断开连接")].waitForExistence(timeout: 10))
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        let reopenedToolbar = app.navigationBars[label("Keyboard Toolbar", "键盘工具栏")]
        if !reopenedToolbar.waitForExistence(timeout: 5) {
            // A transient system banner can consume the menu tap on hardware.
            // Retry only while the original menu item is still visible.
            let menuItem = app.buttons["session-customize-keyboard"]
            if menuItem.exists && menuItem.isHittable { menuItem.tap() }
        }
        XCTAssertTrue(reopenedToolbar.waitForExistence(timeout: 5))
        let position = app.buttons["keyboard-position"]
        XCTAssertTrue(position.exists)
        position.tap()
        app.buttons[label("Top", "顶部")].tap()
        XCTAssertTrue(app.buttons[label("Done", "完成")].exists, "Moving the toolbar must preserve its settings sheet")
        app.buttons["keyboard-size"].tap()
        app.buttons[label("Small", "小")].tap()
        let command = app.switches["keyboard-visible-Cmd"]
        XCTAssertTrue(command.exists)
        command.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(command.value as? String, "0")
        attachScreenshot(app, name: "Narrow Keyboard Customization")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Show Keyboard", "显示键盘")].tap()
        XCTAssertTrue(app.buttons[label("Hide Keyboard", "隐藏键盘")].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cmd")).count, 0)
        attachScreenshot(app, name: "Customized Keyboard Session")
        app.buttons[label("Session Options", "会话选项")].tap()
        app.buttons["session-customize-keyboard"].tap()
        if !reopenedToolbar.waitForExistence(timeout: 5) {
            let menuItem = app.buttons["session-customize-keyboard"]
            if menuItem.exists && menuItem.isHittable { menuItem.tap() }
        }
        XCTAssertTrue(reopenedToolbar.waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["keyboard-visible-Cmd"].value as? String, "0")
        app.buttons[label("Done", "完成")].tap()
        app.buttons[label("Disconnect", "断开连接")].tap()
        XCTAssertTrue(app.buttons[label("Quick Connect", "快速连接")].waitForExistence(timeout: 5))
    }

    func testChineseEnglishSwitchAndPersistence() {
        let app = makeApp(language: "zh-Hans")
        app.launch()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["添加电脑"].exists)
        XCTAssertTrue(app.navigationBars["AetherScreens"].staticTexts["AetherScreens"].exists)
        attachScreenshot(app, name: "Chinese Dashboard")
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.buttons["同步 Tailscale 设备"].exists)
        app.buttons["诊断日志"].tap()
        XCTAssertTrue(app.navigationBars["诊断日志"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        app.buttons["快速连接"].tap()
        XCTAssertTrue(app.navigationBars["快速连接"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["用户名（Mac 账户，可选）"].exists)
        XCTAssertTrue(app.secureTextFields["VNC 密码（可选）"].exists)
        XCTAssertFalse(app.buttons["连接"].isEnabled)
        attachScreenshot(app, name: "Chinese Quick Connect")
        app.buttons["取消"].tap()
        app.buttons["更多操作"].tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["app-language"].tap()
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "Switching language must preserve the open settings sheet")
        attachScreenshot(app, name: "English Settings After Switch")
        app.buttons["Done"].tap()
        app.buttons["Quick Connect"].tap()
        XCTAssertTrue(app.navigationBars["Quick Connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Username (Mac account, optional)"].exists)
        attachScreenshot(app, name: "English Quick Connect After Switch")
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Quick Connect"].waitForExistence(timeout: 10), "Manual selection must survive relaunch")
    }

    func testChineseTemporaryConnectionErrorAndRecovery() {
        let app = makeApp(language: "zh-Hans")
        app.launch()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        app.buttons["快速连接"].tap()
        let host = app.textFields["IP 地址 / 主机名（如 100.80.1.25）"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText("localized-qa.invalid")
        let account = app.textFields["用户名（Mac 账户，可选）"]
        account.tap()
        account.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac 账户密码"].exists)
        app.buttons["连接"].tap()
        XCTAssertTrue(app.buttons["断开连接"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["重试连接"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["连接失败"].exists)
        attachScreenshot(app, name: "Chinese Temporary Connection Error")
        app.buttons["重试连接"].tap()
        XCTAssertTrue(app.buttons["重试连接"].waitForExistence(timeout: 30))
        app.buttons["断开连接"].tap()
        XCTAssertTrue(app.buttons["快速连接"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["连接到 localized-qa.invalid"].exists)
    }

    func testQuickConnectValidationAndTemporarySession() {
        let app = makeApp()
        app.launch()
        let quick = app.buttons["Quick Connect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        quick.tap()
        XCTAssertTrue(app.navigationBars["Quick Connect"].waitForExistence(timeout: 5))
        let connect = app.buttons["Connect"]
        XCTAssertFalse(connect.isEnabled)
        let name = app.textFields["Name (e.g. Studio Mac)"]
        XCTAssertFalse(name.exists)
        let address = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        address.tap()
        address.typeText("quick-qa.invalid")
        let port = app.textFields["Port"]
        port.tap()
        port.typeKey("a", modifierFlags: .command)
        port.typeText("0")
        XCTAssertEqual(port.value as? String, "0")
        XCTAssertFalse(connect.isEnabled)
        port.typeKey("a", modifierFlags: .command)
        port.typeText("5900")
        XCTAssertEqual(port.value as? String, "5900")
        XCTAssertTrue(connect.isEnabled)
        let account = app.textFields["Username (Mac account, optional)"]
        account.tap()
        account.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac Account Password"].exists)
        app.swipeUp()
        let save = app.switches["Save Computer"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(save.value as? String, "0")
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(save.value as? String, "1")
        app.swipeDown()
        XCTAssertTrue(name.exists)
        app.swipeUp()
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertFalse(name.exists)
        attachScreenshot(app, name: "Quick Connect")
        connect.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry Connection"].waitForExistence(timeout: 30))
        attachScreenshot(app, name: "Temporary Connection Error")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Connect to quick-qa.invalid"].exists)
    }

    func testPrimaryScreensOnIPhone() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.buttons["Add Computer"].waitForExistence(timeout: 10))
        app.buttons["Add Computer"].tap()
        XCTAssertTrue(app.navigationBars["Add Computer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Port"].exists)
        let username = app.textFields["Username (Mac account, optional)"]
        XCTAssertTrue(username.exists)
        username.tap()
        username.typeText("qa-user")
        XCTAssertTrue(app.secureTextFields["Mac Account Password"].exists)
        XCTAssertFalse(app.secureTextFields["VNC Password (Optional)"].exists)
        attachScreenshot(app, name: "Add Computer")
        app.buttons["Cancel"].tap()

        app.buttons["More Actions"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Settings")
        app.buttons["Done"].tap()

        app.buttons["More Actions"].tap()
        XCTAssertTrue(app.buttons["Sync Tailscale Devices"].exists)
        app.buttons["Diagnostic Logs"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostic Logs"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Diagnostic Logs")
        app.buttons["Close"].tap()

        let computer = ensureLoopbackComputer(in: app)
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.press(forDuration: 1.0)
        app.buttons["Edit Computer..."].tap()
        XCTAssertTrue(app.navigationBars["Edit Computer"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Edit Computer")
        app.buttons["Cancel"].tap()
    }

    func testSyntheticRemoteSession() {
        let app = makeApp()
        app.launch()
        let computer = ensureLoopbackComputer(in: app)
        if !computer.isHittable { app.swipeUp() }
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 8))
        let loading = app.staticTexts["Loading remote desktop…"]
        XCTAssertTrue(loading.waitForNonExistence(timeout: 10))
        attachScreenshot(app, name: "Synthetic Remote Frame")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
        XCTAssertTrue(app.buttons["Disconnect"].isHittable)
        attachScreenshot(app, name: "Landscape Remote Frame")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.buttons["Hide Keyboard"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Remote Keyboard")
        app.buttons["Disconnect"].tap()
    }

    func testLiveRemoteSession() throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["AETHERSCREENS_LIVE_HOST"],
              let password = env["AETHERSCREENS_LIVE_PASSWORD"] else {
            throw XCTSkip("Set live host and password in the test runner environment")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Add Computer"].tap()
        let name = app.textFields["Name (e.g. Studio Mac)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("QA Live Mac")
        let address = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        address.tap()
        address.typeText(host)
        let username = env["AETHERSCREENS_LIVE_USERNAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let username, !username.isEmpty {
            let account = app.textFields["Username (Mac account, optional)"]
            XCTAssertTrue(account.waitForExistence(timeout: 5))
            account.tap()
            account.typeText(username)
        }
        let secret = app.secureTextFields[(username?.isEmpty == false) ? "Mac Account Password" : "VNC Password (Optional)"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.tap()
        secret.typeText(password)
        app.buttons["Save"].tap()
        let computer = app.buttons["Connect to QA Live Mac"].firstMatch
        XCTAssertTrue(computer.waitForExistence(timeout: 10))
        if !computer.isHittable { app.swipeUp() }
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["remote-desktop-frame"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["Retry Connection"].exists)
        attachScreenshot(app, name: "Live Mac First Frame")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.buttons["Disconnect"].isHittable)
        attachScreenshot(app, name: "Live Mac Landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Show Keyboard"].tap()
        XCTAssertTrue(app.buttons["Hide Keyboard"].waitForExistence(timeout: 5))
        attachScreenshot(app, name: "Live Mac Keyboard")
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Add Computer"].waitForExistence(timeout: 10))
    }

    func testPreviouslyConfiguredMacReceivesRealDesktop() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the previously configured physical-device Mac")
        #endif
        guard let name = ProcessInfo.processInfo.environment["AETHERSCREENS_CONFIGURED_MAC_NAME"] else {
            throw XCTSkip("Requires an explicitly selected saved Mac")
        }
        let app = makeApp()
        app.launch()
        let computer = app.buttons["Connect to " + name].firstMatch
        XCTAssertTrue(computer.waitForExistence(timeout: 15))
        scrollComputerIntoView(computer, in: app)
        computer.tap()
        XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 10))
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        let received = frame.waitForExistence(timeout: 45)
        attachScreenshot(app, name: received ? "Physical Mac Real Desktop" : "Physical Mac Connection Failure")
        XCTAssertTrue(received, "Configured Mac must authenticate and deliver a real framebuffer")
        app.buttons["Disconnect"].tap()
    }

    // Enter the credential on the physical device so it never appears in test
    // arguments, typeText activity logs, source code, or result bundle metadata.
    func testPhysicalTargetMacAccountConnection() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires physical-device credential entry for the authorized LAN Mac")
        #endif
        let env = ProcessInfo.processInfo.environment
        guard let targetHost = env["AETHERSCREENS_LIVE_HOST"], let username = env["AETHERSCREENS_LIVE_USERNAME"] else {
            throw XCTSkip("Requires an explicitly selected physical-device Mac and account")
        }
        let app = makeApp()
        app.launch()
        app.buttons["Quick Connect"].tap()
        let host = app.textFields["Tailscale IP / Host (e.g. 100.80.1.25)"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText(targetHost)
        let account = app.textFields["Username (Mac account, optional)"]
        account.tap()
        app.activate()
        account.tap()
        account.typeText(username)
        let secret = app.secureTextFields["Mac Account Password"]
        secret.tap()
        // The user submits after finishing input. Never infer completion from
        // the first password character or read the secure-field contents.
        let frame = app.descendants(matching: .any)["remote-desktop-frame"].firstMatch
        let received = frame.waitForExistence(timeout: 300)
        attachScreenshot(app, name: received ? "Target Physical Desktop" : "Target Physical Connection Failure")
        XCTAssertTrue(received, "Target Mac must authenticate and deliver a real framebuffer")
        app.buttons["Disconnect"].tap()
    }

    private func makeApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-com.aethernative.aetherscreens.language", language]
        return app
    }

    private func ensureLoopbackComputer(in app: XCUIApplication, language: String = "en") -> XCUIElement {
        func label(_ en: String, _ zh: String) -> String { language == "zh-Hans" ? zh : en }
        let computer = app.buttons[label("Connect to QA Loopback", "连接到 QA Loopback")].firstMatch
        if !computer.exists {
            app.buttons[label("Add Computer", "添加电脑")].tap()
            let name = app.textFields[label("Name (e.g. Studio Mac)", "名称（如 工作室 Mac）")]
            let host = app.textFields[label("Tailscale IP / Host (e.g. 100.80.1.25)", "IP 地址 / 主机名（如 100.80.1.25）")]
            let port = app.textFields[label("Port", "端口")]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("QA Loopback")
            host.tap()
            host.typeText("127.0.0.1")
            replacePort(port, with: "5999")
            XCTAssertEqual(port.value as? String, "5999")
            XCTAssertTrue(app.buttons[label("Save", "保存")].isEnabled)
            app.buttons[label("Save", "保存")].tap()
        }
        XCTAssertTrue(computer.waitForExistence(timeout: 10))
        scrollComputerIntoView(computer, in: app)
        return computer
    }

    private func scrollComputerIntoView(_ computer: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let sessionControl = app.buttons["open-sessions"]
        let safeTop = sessionControl.exists ? max(window.minY + 44, sessionControl.frame.maxY + 8) : window.minY + 120
        // A partially visible card may be hittable while its long-press center
        // sits below the display. Bring the whole card above the safe area first.
        for _ in 0..<5 {
            let frame = computer.frame
            if frame.minY >= safeTop && frame.maxY <= window.maxY - 60 { break }
            let scroll = app.scrollViews.firstMatch
            let surface = scroll.exists ? scroll : app.windows.firstMatch
            let start = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: frame.maxY > window.maxY - 60 ? 0.75 : 0.3))
            let end = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: frame.maxY > window.maxY - 60 ? 0.3 : 0.75))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(computer.frame.minY, safeTop)
        XCTAssertLessThanOrEqual(computer.frame.maxY, window.maxY - 60)
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        // App-only captures crop incorrectly after iPad rotation on the current
        // simulator. Full-screen capture preserves the visible layout.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class GestureFixtureResponse: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    func set(_ value: Result<Data, Error>) { lock.lock(); result = value; lock.unlock() }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return result }
}
