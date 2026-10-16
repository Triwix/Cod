import XCTest

final class NotificationFlowTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testShareNotificationLaunchesCodWithTheCorrectImage() {
        exerciseNotification(cold: false, crop: false)
    }

    func testColdNotificationLaunchesCodWithTheCorrectImage() {
        exerciseNotification(cold: true, crop: false)
    }

    func testCropBeforeNotificationDoesNotCropAgainInCod() {
        exerciseNotification(cold: false, crop: true)
    }

    private func exerciseNotification(cold: Bool, crop: Bool) {
        continueAfterFailure = false
        cod.launch()
        cod.tabBars.buttons["Settings"].tap()
        let wholeImage = cod.switches["One tap float"]
        XCTAssertTrue(wholeImage.waitForExistence(timeout: 5))
        if (wholeImage.value as? String == "1") == crop {
            wholeImage.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let toggle = cod.switches["Tap notification to float"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 3) {
                springboard.alerts.buttons["Allow"].tap()
            }
        }
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        cod.tabBars.buttons["Capture"].tap()
        if cold { cod.terminate() }

        let lab = XCUIApplication()
        lab.launch()
        lab.buttons["Share Test Image"].tap()
        let codCell = lab.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Cod Test'")).firstMatch
        XCTAssertTrue(codCell.waitForExistence(timeout: 8))
        codCell.tap()
        if crop {
            XCTAssertTrue(lab.buttons["cancel-selection"].waitForExistence(timeout: 8))
            lab.buttons["Float"].tap()
        }
        let notification = springboard.staticTexts["Your image is ready to float"].firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 10), "Notification must actually be delivered by the share extension, not just scheduled by the app")
        notification.tap()
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 10))
        XCTAssertEqual(cod.staticTexts["received-image-size"].label, "Received image 300x200")
        XCTAssertFalse(cod.buttons["cancel-selection"].exists)
    }

    override func tearDownWithError() throws {
        cod.activate()
        if cod.tabBars.buttons["Settings"].waitForExistence(timeout: 5) {
            cod.tabBars.buttons["Settings"].tap()
            let toggle = cod.switches["Tap notification to float"]
            if toggle.waitForExistence(timeout: 5), toggle.value as? String == "1" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            let wholeImage = cod.switches["One tap float"]
            if wholeImage.exists, wholeImage.value as? String != "1" {
                wholeImage.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
        }
    }
}
