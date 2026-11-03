import XCTest

final class Redesign21UITests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Redesign checks use disposable simulator drafts and pending test shares")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        cod.terminate()
    }

    override func tearDownWithError() throws { cod.terminate() }

    func testHomeTargetsLibraryGroupingAndOptionalSharingExplanation() {
        launch()
        for identifier in ["choose-photo", "crop-photo", "float-latest-screenshot", "crop-latest-screenshot"] {
            let button = cod.buttons[identifier]
            reveal(button)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
        }
        capture("21 - Home - actions first")
        selectTab("Library")
        XCTAssertTrue(cod.buttons["saved-references"].waitForExistence(timeout: 5))
        XCTAssertTrue(cod.segmentedControls["library-filter"].exists)
        capture("21 - Library - grouped references and filters")

        selectTab("Settings")
        let explanation = cod.buttons["share-route-explanation"]
        reveal(explanation)
        let details = cod.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The Cod app icon runs a Share extension.")).firstMatch
        XCTAssertFalse(details.exists, "Long guidance is optional, not competing with the switches")
        capture("21 - Settings - concise guidance")
        explanation.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
    }

    func testShortTextPreviewFitsItsContentAndFloatRemainsPinned() {
        launch()
        let text = cod.buttons["tool-text"]
        reveal(text); text.tap()
        let prompter = cod.switches["text-teleprompter"]
        XCTAssertTrue(prompter.waitForExistence(timeout: 5))
        if prompter.value as? String == "1" {
            prompter.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        }
        let clear = cod.buttons["clear-text"]
        reveal(clear)
        if clear.isEnabled { clear.tap() }
        let editor = cod.textViews["floating-text-editor"]
        reveal(editor, towardTop: true)
        editor.tap(); editor.typeText("Gate 7 at 14:30")
        cod.toolbars.buttons["Done"].tap()
        let preview = cod.images["Floating text preview"]
        let float = cod.buttons["float-text"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(float.isHittable)
        let tight = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let gap = float.frame.minY - preview.frame.maxY
            return gap >= 0 && gap <= 32
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [tight], timeout: 5), .completed,
                       "Short cards must not reserve an empty video-height area")
        capture("21 - Text - fitted preview and clear Float action")
        let original = float.frame.minY
        let settings = cod.descendants(matching: .any).matching(identifier: "float-settings").firstMatch
        settings.swipeUp()
        XCTAssertTrue(float.isHittable)
        XCTAssertEqual(float.frame.minY, original, accuracy: 2)
    }

    func testDarkLargestTextKeepsPrimaryActionWithinTheViewport() {
        launch(extra: ["--dark-ui-test", "--large-text-ui-test"])
        let timer = cod.buttons["tool-countdown"]
        reveal(timer); timer.tap()
        let float = cod.buttons["float-tool"]
        XCTAssertTrue(float.waitForExistence(timeout: 5))
        XCTAssertTrue(float.isHittable)
        let bounds = cod.windows.allElementsBoundByIndex.map(\.frame)
            .max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
        XCTAssertGreaterThanOrEqual(float.frame.minX, bounds.minX)
        XCTAssertLessThanOrEqual(float.frame.maxX, bounds.maxX)
        XCTAssertGreaterThanOrEqual(float.frame.height, 44)
        capture("21 - Timer - dark and largest text")
    }

    private func launch(extra: [String] = []) {
        cod.launchArguments = ["--launch-ui-test"] + extra
        cod.launch()
        XCTAssertTrue(cod.navigationBars["Cod"].waitForExistence(timeout: 8))
        // This simulator's earlier Share fixtures can remain after unsupported
        // native PiP. Remove only that pending test share through its own UI.
        if cod.staticTexts["Shared image ready to retry"].exists, cod.buttons["Remove"].isHittable {
            cod.buttons["Remove"].tap()
        }
        // Large-type List rows are lazy and can start below the first viewport.
        reveal(cod.buttons["choose-photo"])
    }

    private func selectTab(_ title: String) {
        let bottom = cod.tabBars.buttons[title]
        let button = bottom.exists ? bottom : cod.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        let barTitle = title == "Float" ? "Cod" : title
        if !cod.navigationBars[barTitle].waitForExistence(timeout: 3) { button.tap() }
        XCTAssertTrue(cod.navigationBars[barTitle].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, towardTop: Bool = false) {
        for _ in 0..<18 where !element.isHittable {
            if towardTop { cod.swipeDown() } else { cod.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, cod.debugDescription)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
