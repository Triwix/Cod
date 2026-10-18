import XCTest

final class ShortcutFlowTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Installer tests replace disposable simulator Shortcuts; never replace a person's phone workflows.")
        #endif
    }

    func testSignedShareShortcutImportsAndDeliversColdAndWarmImages() {
        continueAfterFailure = false
        install("Add Share-Sheet Shortcut")
        cod.terminate() // The Shortcut must launch Cod; never activate it for the assertion.
        let lab = XCUIApplication()
        lab.launch()
        runShareShortcut(in: lab, button: "Share Test Image", expectedSize: "300x200")
        lab.launch()
        runShareShortcut(in: lab, button: "Share Second Image", expectedSize: "148x92")
    }

    func testSignedScreenshotShortcutImportsAndCapturesTheScreen() {
        continueAfterFailure = false
        install("Add Screenshot Shortcut")
        cod.terminate()
        let play = shortcuts.buttons.matching(NSPredicate(format: "label IN {'Run Shortcut', 'play', 'Run'}")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 8), shortcuts.debugDescription)
        play.tap()
        finishSystemHandoff()
        cod.tabBars.buttons["Capture"].tap()
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 8))
        XCTAssertFalse(cod.buttons["cancel-selection"].exists)
        print("SCREENSHOT SHORTCUT RECEIPT: \(cod.staticTexts["received-image-size"].label)")
    }

    private func install(_ button: String) {
        cod.launch()
        cod.tabBars.buttons["Settings"].tap()
        let guide = cod.buttons["Set up fast floating"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        guide.tap()
        let install = cod.buttons[button]
        for _ in 0..<8 where !install.isHittable { cod.swipeUp() }
        XCTAssertTrue(install.exists, "The signed file must be bundled, not manual instructions")
        XCTAssertTrue(install.isHittable)
        install.tap()
        let target = cod.cells.matching(NSPredicate(format: "label == 'Shortcuts'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        target.tap()
        let inCod = cod.buttons["Add Shortcut"]
        let inShortcuts = shortcuts.buttons["Add Shortcut"]
        let available = NSPredicate { _, _ in inCod.exists || inShortcuts.exists }
        expectation(for: available, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        if inCod.exists { inCod.tap() } else { inShortcuts.tap() }
        // Only replaces the diagnostic Shortcut installed by this test.
        if shortcuts.buttons["Replace"].waitForExistence(timeout: 2) {
            shortcuts.buttons["Replace"].tap()
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Signed Float with Cod installation"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func runShareShortcut(in lab: XCUIApplication, button: String, expectedSize: String) {
        lab.buttons[button].tap()
        let action = lab.cells.matching(NSPredicate(format: "label == 'Float with Cod'")).firstMatch
        for _ in 0..<6 where !action.isHittable { lab.swipeUp() }
        XCTAssertTrue(action.waitForExistence(timeout: 5), lab.debugDescription)
        action.tap()
        // iOS owns first-run prompts; don't mistake an untested prompt for a
        // successful handoff or manually launch the destination app here.
        finishSystemHandoff()
        cod.tabBars.buttons["Capture"].tap()
        let receipt = cod.staticTexts["received-image-size"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "label == %@", "Received image \(expectedSize)"), evaluatedWith: receipt)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(cod.buttons["cancel-selection"].exists)
    }

    private func finishSystemHandoff() {
        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.ShortcutsUI")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let surfaces = [systemUI, springboard, shortcuts, XCUIApplication()]
        let ready = NSPredicate { _, _ in
            self.cod.state == .runningForeground || surfaces.contains { $0.buttons["Allow Once"].exists }
        }
        expectation(for: ready, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        if cod.state != .runningForeground {
            let allow = surfaces.compactMap { app -> XCUIElement? in
                let button = app.buttons["Allow Once"]
                return button.exists ? button : nil
            }.first
            XCTAssertNotNil(allow, "Expected the native image-sharing permission, not a file picker")
            print("FIRST-RUN SHORTCUT PROMPT: allow sharing this test image with Cod Test")
            allow?.tap()
        }
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 12), "A Shortcut must launch Cod without manual activation")
    }
}
