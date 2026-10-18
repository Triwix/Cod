import XCTest

final class LaunchFlowTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")
    private var lab: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        cod.launchArguments = ["--launch-ui-test"]
        cod.launch() // Seed UI-test arguments, then background it.
        #if !COD_LAUNCH_PROBE
        setOneTapFloat(true)
        #endif
        lab = XCUIApplication()
        lab.launch()
    }

    func testShareAutomaticallyPreparesAndAppActivationNeedsNoFloatTap() {
        lab.buttons["Share Test Image"].tap()
        selectCod()
        #if COD_LAUNCH_PROBE
        let probe = lab.buttons["test-system-float"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        probe.tap()
        let launched = cod.wait(for: .runningForeground, timeout: 8)
        print("PUBLIC SHARE INTENT FOREGROUND RESULT: \(launched)")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Public intent result"
        shot.lifetime = .keepAlways
        add(shot)
        // This is a diagnostic, not an assertion that this surface is supported.
        #elseif COD_FAST_SHARE
        assertAutomaticLaunch(size: "300x200")
        #else
        waitForShareToFinish()
        XCTAssertFalse(lab.buttons["Save to Cod"].exists)
        cod.activate()
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
        XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image 300x200")
        #endif
    }

    func testDocumentOpenRoute() {
        lab.buttons["Open Test Image In"].tap()
        let initial = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initial.name = "Document opening choices"
        initial.lifetime = .keepAlways
        add(initial)
        selectCod()
        #if COD_FAST_SHARE
        assertAutomaticLaunch(size: "300x200")
        #else
        let launched = cod.wait(for: .runningForeground, timeout: 10)
        print("PUBLIC DOCUMENT OPEN FOREGROUND RESULT: \(launched)")
        if launched {
            XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
            XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image 300x200")
        } else {
            // iOS may show the Share extension even for this public Open In
            // menu. Record that distinction; don't label it a direct launch.
            #if COD_LAUNCH_PROBE
            XCTAssertTrue(lab.buttons["test-system-float"].waitForExistence(timeout: 10))
            #else
            waitForShareToFinish()
            cod.activate()
            XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
            #endif
        }
        #endif
    }

    #if !COD_LAUNCH_PROBE
    func testSettingsExplainThatTheActionBarOnlyAppliesInsideCod() {
        cod.launch()
        let settingsTab = cod.tabBars.buttons["Settings"]
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
        #if COD_FAST_SHARE
        let cancel = lab.buttons["cancel-selection"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Cropping must happen in the share extension")
        cancel.tap()
        #else
        waitForShareToFinish()
        cod.launch()
        let cancel = cod.buttons["cancel-selection"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The shared setting must open cropping, not auto-PiP")
        cancel.tap()
        #endif
        lab.launch()
        cod.launch()
        XCTAssertFalse(cancel.exists, "Cancelled images must not replay on activation")
        #if !COD_FAST_SHARE
        XCTAssertTrue(cod.buttons["Try Floating Again"].waitForExistence(timeout: 5))
        #endif
        setOneTapFloat(true)
    }

    #if COD_FAST_SHARE
    func testColdShareLaunchesWithoutOpeningCodManually() {
        cod.terminate()
        lab.buttons["Share Test Image"].tap()
        selectCod()
        assertAutomaticLaunch(size: "300x200")
    }

    func testSecondShareUsesTheNewImageWithoutAnotherAppOpen() {
        lab.buttons["Share Test Image"].tap()
        selectCod()
        assertAutomaticLaunch(size: "300x200")
        lab.launch()
        lab.buttons["Share Second Image"].tap()
        selectCod()
        assertAutomaticLaunch(size: "148x92")
    }

    func testCropThenFloatLaunchesWithoutCroppingTwice() {
        cod.launch()
        setOneTapFloat(false)
        lab.launch()
        lab.buttons["Share Test Image"].tap()
        selectCod()
        XCTAssertTrue(lab.buttons["cancel-selection"].waitForExistence(timeout: 10))
        lab.buttons["Float"].tap()
        assertAutomaticLaunch(size: "300x200")
        XCTAssertFalse(cod.buttons["cancel-selection"].exists)
        setOneTapFloat(true)
    }

    private func assertAutomaticLaunch(size: String) {
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10), "Share must launch Cod; the test must NOT activate it manually")
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
        XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image \(size)")
    }
    #endif

    private func setOneTapFloat(_ enabled: Bool) {
        let settings = cod.tabBars.buttons["Settings"]
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: settings)
        waitForExpectations(timeout: 5)
        settings.tap()
        let toggle = cod.switches["One tap float"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != enabled {
            // SwiftUI exposes a row-wide switch; its center can be the label,
            // not the actual thumb. Tap the trailing native control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "value == %@", enabled ? "1" : "0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        cod.tabBars.buttons["Capture"].tap()
    }
    #endif

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
        let completed = NSPredicate { _, _ in self.lab.sheets.count == 0 }
        expectation(for: completed, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        XCTAssertFalse(lab.buttons["Try Again"].exists, "Import should succeed without a retry")
    }
}
