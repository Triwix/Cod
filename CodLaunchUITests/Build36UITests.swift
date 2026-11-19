import XCTest

/// Video speed and sections, web video links, and Recents without duplicates.
final class Build36UITests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("These checks use disposable simulator data.")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        cod.terminate()
        cod.launchArguments = ["--launch-ui-test"]
        cod.launch()
        XCTAssertTrue(cod.navigationBars["Cod"].waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws { cod.terminate() }

    func testVideoOffersSpeedAndASectionToRepeat() {
        let lab = XCUIApplication()
        lab.launch()
        defer { lab.terminate() }
        lab.buttons["Open Test Video In"].tap()
        let cell = lab.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Cod Test'")).firstMatch
        if !cell.waitForExistence(timeout: 5), lab.cells["More"].exists { lab.cells["More"].tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 8)); cell.tap()
        XCTAssertTrue(cod.buttons["float-video"].waitForExistence(timeout: 10), cod.debugDescription)
        let speed = cod.buttons["video-speed"]
        reveal(speed)
        XCTAssertTrue(speed.exists, cod.debugDescription)
        speed.tap()
        cod.buttons["1.5×"].tap()
        XCTAssertTrue(cod.buttons["video-speed"].label.contains("1.5×"), cod.buttons["video-speed"].label)
        let section = cod.switches["video-section"]
        reveal(section)
        if section.exists {
            section.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
            XCTAssertTrue(cod.sliders["video-section-start"].waitForExistence(timeout: 3))
            XCTAssertTrue(cod.sliders["video-section-end"].exists)
        }
        capture("36 - Video - speed and section")
        cod.buttons["Close"].tap()
    }

    func testVideoLinkScreenOpensAPage() {
        let row = cod.buttons["open-web-video"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let address = cod.textFields["web-address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), cod.debugDescription)
        XCTAssertTrue(cod.otherElements["web-empty"].exists || cod.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Paste a link'")).firstMatch.exists)
        XCTAssertFalse(cod.buttons["web-float"].isEnabled, "Nothing to float before a page opens")
        address.typeText("example.com\n")
        let float = cod.buttons["web-float"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: float)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        capture("36 - Web video - page open")
        cod.navigationBars.buttons["Close"].tap()
    }

    private func reveal(_ element: XCUIElement) {
        let list = cod.collectionViews.firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
            let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.4))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
