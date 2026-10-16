import XCTest

final class ControlLaunchTests: XCTestCase {
    func testControlIsAvailableInSystemGallery() {
        continueAfterFailure = false
        let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")
        cod.launch()
        XCUIDevice.shared.press(.home)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let start = system.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.01))
        start.press(forDuration: 0.1, thenDragTo: system.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65)))
        print("CONTROL CENTER TREE: \(system.debugDescription)")
        let add = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Controls'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        print("CONTROL EDIT TREE: \(system.debugDescription)")
        let gallery = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add a Control'")).firstMatch
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        gallery.tap()
        let search = system.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Cod")
        let control = system.descendants(matching: .any).matching(NSPredicate(format: "label == 'Float Latest Screenshot'")).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 8), "Cod's control must be registered in the real system gallery: \(system.debugDescription)")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Cod system control in gallery"
        attachment.lifetime = .keepAlways
        self.add(attachment)
        control.tap()
        XCUIDevice.shared.press(.home)
        start.press(forDuration: 0.1, thenDragTo: system.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65)))
        print("INSTALLED CONTROL TREE: \(system.debugDescription)")
        let installed = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Float'")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout: 5))
        installed.tap()
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10), "The system control must launch Cod, not a background widget process")
        let deny = system.alerts.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Don't Allow", "Don’t Allow")).firstMatch
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        XCUIDevice.shared.press(.home)
    }
}
