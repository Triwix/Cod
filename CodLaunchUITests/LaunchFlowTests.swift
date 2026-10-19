import XCTest

final class LaunchFlowTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")
    private var lab: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        cod.launchArguments = ["--launch-ui-test", "-autoCopyOnCapture", "NO"]
        cod.launch() // Seed UI-test arguments, then background it.
        setOneTapFloat(true)
        lab = XCUIApplication()
        lab.launch()
    }

    func testShareAutomaticallyPreparesAndAppActivationNeedsNoFloatTap() {
        lab.buttons["Share Test Image"].tap()
        selectCod()
        waitForShareToFinish()
        XCTAssertFalse(lab.buttons["Save to Cod"].exists)
        XCTAssertNotEqual(cod.state, .runningForeground, "A Share extension must not launch its containing app")
        cod.activate()
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
        XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image 300x200")
    }

    func testDocumentOpenRoute() {
        lab.buttons["Open Test Image In"].tap()
        let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initial.name = "Document opening choices"
        initial.lifetime = .keepAlways
        add(initial)
        selectCod()
        let launched = cod.wait(for: .runningForeground, timeout: 10)
        print("PUBLIC DOCUMENT OPEN FOREGROUND RESULT: \(launched)")
        if launched {
            XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
            XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image 300x200")
        } else {
            // iOS may show the Share extension even for this public Open In
            // menu. Record that distinction; don't label it a direct launch.
            waitForShareToFinish()
            cod.activate()
            XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
        }
    }

    func testSettingsExplainThatTheActionBarOnlyAppliesInsideCod() {
        cod.launch()
        let settingsTab = tab("Settings")
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: settingsTab)
        waitForExpectations(timeout: 5)
        settingsTab.tap()
        let actionBar = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Action bar'")).firstMatch
        for _ in 0..<6 where !actionBar.isHittable { cod.swipeUp() }
        XCTAssertTrue(actionBar.isHittable, cod.debugDescription)
        let explanation = cod.staticTexts["Choose actions for Cod's own crop editor. The share-sheet crop screen only offers Float."]
        for _ in 0..<3 where !explanation.exists { cod.swipeUp() }
        XCTAssertTrue(explanation.exists)
        actionBar.tap()
        let detail = cod.staticTexts["These actions appear in Cod's crop editor, not in the share sheet. Drag to reorder."]
        for _ in 0..<6 where !detail.exists { cod.swipeUp() }
        XCTAssertTrue(detail.exists)
    }

    func testShareWithOneTapOffOpensCropAndDoesNotReplayAfterCancel() {
        cod.launch()
        setOneTapFloat(false)
        lab.launch()
        lab.buttons["Share Test Image"].tap()
        selectCod()
        waitForShareToFinish()
        cod.launch()
        let cancel = cod.buttons["cancel-selection"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The shared setting must open cropping, not auto-PiP")
        cancel.tap()
        lab.launch()
        cod.launch()
        XCTAssertFalse(cancel.exists, "Cancelled images must not replay on activation")
        XCTAssertTrue(cod.buttons["Try Floating Again"].waitForExistence(timeout: 5))
        setOneTapFloat(true)
    }


    func testHistoryDeletionRequiresConfirmationAndCancelKeepsImages() {
        cod.launch()
        setOneTapFloat(false)
        lab.launch()
        lab.buttons["Share Test Image"].tap()
        selectCod()
        waitForShareToFinish()
        cod.activate()
        XCTAssertTrue(cod.buttons["cancel-selection"].waitForExistence(timeout: 8), cod.debugDescription)
        cod.buttons["Pin"].tap() // Real fixture ingestion, no clipboard read/write.
        cod.buttons["cancel-selection"].tap()
        tab("Settings").tap()
        let clear = cod.buttons["clear-history"]
        for _ in 0..<8 where !clear.isHittable { cod.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        XCTAssertTrue(clear.isEnabled)
        clear.tap()
        XCTAssertTrue(cod.staticTexts["Clear saved history?"].waitForExistence(timeout: 5))
        dismissConfirmation(titled: "Clear saved history?")

        let limit = cod.buttons["history-limit"]
        for _ in 0..<3 where !limit.isHittable { cod.swipeDown() }
        limit.tap()
        cod.buttons["Off"].tap()
        XCTAssertTrue(cod.staticTexts["Remove older saved images?"].waitForExistence(timeout: 5))
        dismissConfirmation(titled: "Remove older saved images?")

        // Remove only the disposable in-app pin so it can't cover a thumbnail.
        let closePin = cod.buttons["Close pin"]
        closePin.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: closePin)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(cod.staticTexts["Clear saved history?"].exists, "Closing a pin must not tap through to the underlying setting")
        let library = tab("Library")
        if !library.isHittable {
            print("AFTER HISTORY CANCEL: \(cod.debugDescription)")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "History after cancellation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: library)
        waitForExpectations(timeout: 5)
        library.tap()
        let saved = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved '")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), cod.debugDescription)
        saved.tap()
        let floatImage = cod.buttons["Float Image"]
        XCTAssertTrue(floatImage.waitForExistence(timeout: 5))
        floatImage.tap()
        // Simulator PiP is unavailable, but the Library handoff and dismissal
        // must still reach the launch UI without leaving its detail sheet up.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: floatImage)
        waitForExpectations(timeout: 5)
        if cod.buttons["Back to Cod"].exists { cod.buttons["Back to Cod"].tap() }
        cod.launch()
        setOneTapFloat(true)
    }

    private func dismissConfirmation(titled title: String) {
        let cancel = cod.sheets.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            // Popover-style confirmation dialogs omit Cancel. Dismiss outside
            // the popover; an unrelated pin can also have a Close button.
            let outside = cod.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(outside.exists)
            outside.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cod.staticTexts[title])
        waitForExpectations(timeout: 5)
    }

    private func setOneTapFloat(_ enabled: Bool) {
        let settings = tab("Settings")
        if !settings.isHittable { print("TAB NAVIGATION STATE: \(cod.debugDescription)") }
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: settings)
        waitForExpectations(timeout: 5)
        settings.tap()
        let notification = cod.switches["Tap notification to float"]
        if notification.waitForExistence(timeout: 5), notification.value as? String == "1" {
            notification.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let toggle = cod.switches["One tap float"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != enabled {
            // SwiftUI exposes a row-wide switch; its center can be the label,
            // not the actual thumb. Tap the trailing native control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "value == %@", enabled ? "1" : "0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        tab("Float").tap()
    }

    private func tab(_ title: String) -> XCUIElement {
        let bottomTab = cod.tabBars.buttons[title]
        // Modern iPadOS exposes top tabs outside the bottom TabBar hierarchy.
        if bottomTab.exists { return bottomTab }
        let matches = cod.buttons.matching(NSPredicate(format: "label == %@", title))
        return matches.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? matches.firstMatch
    }

    private func selectCod() {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "Cod Test")
        let button = lab.cells.matching(predicate).firstMatch
        if !button.waitForExistence(timeout: 5) {
            let more = lab.cells["More"]
            if more.exists { more.tap() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Cod Test must be offered for the fixture image. UI: \(lab.debugDescription)")
        button.tap()
    }

    private func waitForShareToFinish() {
        // A background button still "exists" behind an extension. Require
        // the system's presented sheet to have actually disappeared.
        let sharingUI = XCUIApplication(bundleIdentifier: "com.apple.SharingUIService")
        let completed = NSPredicate { _, _ in
            self.lab.sheets.count == 0 && sharingUI.state != .runningForeground
                && self.lab.buttons["Share Test Image"].isHittable
                && !self.lab.staticTexts["Loading image…"].exists
                && !self.lab.staticTexts["Preparing image…"].exists
                && !self.lab.buttons["cancel-selection"].exists
        }
        expectation(for: completed, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        XCTAssertFalse(lab.buttons["Try Again"].exists, "Import should succeed without a retry")
    }
}
