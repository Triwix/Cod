import XCTest

/// Cod Pro: the free tier sets up tools freely and only floating asks for Pro.
/// UI tests have no App Store products, so plan rows aren't checked here;
/// purchases are covered by ProTests against the local StoreKit file.
final class Build32UITests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("These checks use disposable simulator data.")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        cod.terminate()
        cod.launchArguments = ["--launch-ui-test", "--free-tier-ui-test"]
        cod.launch()
        XCTAssertTrue(cod.navigationBars["Cod"].waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        // Leave the remembered test tier on Pro for Launch Lab tests that
        // cold-launch Cod without arguments.
        cod.terminate()
        cod.launchArguments = ["--launch-ui-test"]
        cod.launch()
        cod.terminate()
    }

    func testFreeTierPreviewsToolsAndAsksForProOnlyWhenFloating() {
        let tile = cod.buttons["tool-countdown"]
        reveal(tile)
        XCTAssertEqual(tile.value as? String, "Pro", "Pro tools carry a badge")
        tile.tap()
        XCTAssertTrue(cod.images["Tool preview"].waitForExistence(timeout: 5), "Setting up stays free")
        let float = cod.buttons["float-tool"]
        XCTAssertTrue(float.waitForExistence(timeout: 5))
        float.tap()
        let subtitle = cod.staticTexts["pro-subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5), cod.debugDescription)
        XCTAssertTrue(subtitle.label.contains("live tools"), subtitle.label)
        XCTAssertTrue(cod.otherElements["pro-feature-tools"].exists || cod.staticTexts["Live tools"].exists)
        XCTAssertTrue(cod.buttons["pro-restore"].exists)
        XCTAssertTrue(cod.links["Terms of Use"].exists || cod.buttons["Terms of Use"].exists)
        XCTAssertFalse(cod.staticTexts["Floating"].exists, "Nothing floated")
        capture("32 - Pro screen from a timer")
        cod.buttons["pro-close"].tap()
        XCTAssertFalse(subtitle.waitForExistence(timeout: 2))
        XCTAssertTrue(float.exists, "Closing returns to the editor")
    }

    func testSettingsOffersProAndRestorePurchases() {
        cod.tabBars.buttons["Settings"].tap()
        let row = cod.buttons["settings-pro"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(cod.buttons["settings-restore"].exists)
        capture("32 - Settings - Cod Pro")
        row.tap()
        let subtitle = cod.staticTexts["pro-subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        XCTAssertTrue(cod.otherElements["pro-feature-savedCards"].exists || cod.staticTexts["Saved cards & presets"].exists)
        cod.buttons["pro-close"].tap()
    }

    // MARK: Helpers

    private func reveal(_ element: XCUIElement) {
        let list = cod.collectionViews.firstMatch
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            list.swipeUp(velocity: XCUIGestureVelocity(rawValue: 400))
        }
        XCTAssertTrue(element.isHittable, cod.debugDescription)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
