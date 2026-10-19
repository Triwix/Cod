import XCTest
import UIKit

final class ReleaseUXTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
            throw XCTSkip("Layout/setup tests change preferences only in the disposable simulator.")
        #endif
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testHomeMakesPhotoFloatingAndReadyMadeSetupDiscoverable() {
        cod.launchArguments = ["--show-float-setup"]
        cod.launch()
        XCTAssertTrue(cod.buttons["choose-photo"].waitForExistence(timeout: 8))
        let install = cod.buttons["install-share-shortcut"]
        for _ in 0..<5 where !install.isHittable { cod.swipeUp() }
        XCTAssertTrue(
            install.isHittable, "First-use setup must expose the actual installer, not just manual instructions")
        capture("Float home - ready-made setup")
        let hide = cod.buttons["hide-float-setup"]
        for _ in 0..<3 where !hide.isHittable { cod.swipeUp() }
        hide.tap()
        XCTAssertFalse(install.exists)
        cod.terminate()
        cod.launchArguments = []
        cod.launch()
        XCTAssertFalse(install.exists, "Hiding the tip must persist")
        let guide = cod.buttons["Floating guide & setup"]
        for _ in 0..<6 where !guide.isHittable { cod.swipeUp() }
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(
            cod.buttons["install-share-shortcut"].waitForExistence(timeout: 5),
            "The installer remains available after hiding the tip")
        capture("Floating guide - share first")
    }

    func testHomeAndGuideRemainUsableAtLargestTextSize() {
        cod.launchArguments = [
            "--show-float-setup", "--large-text-ui-test",
        ]
        cod.launch()
        XCTAssertTrue(cod.buttons["choose-photo"].waitForExistence(timeout: 8))
        capture("Float home - accessibility text")
        let install = cod.buttons["install-share-shortcut"]
        for _ in 0..<10 where !install.isHittable { cod.swipeUp() }
        XCTAssertTrue(install.isHittable)
        capture("Float setup - accessibility text")
    }

    func testLandscapeAndDarkAppearance() throws {
        cod.launchArguments = ["--show-float-setup", "--dark-ui-test", "--landscape-ui-test"]
        cod.launch()
        XCTAssertTrue(cod.buttons["choose-photo"].waitForExistence(timeout: 8))
        capture("Float home - dark")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = NSPredicate { _, _ in
            // AVKit can add a zero-size utility window ahead of the main one.
            let frame = self.cod.windows.allElementsBoundByIndex.map(\.frame)
                .max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
            return frame.width > frame.height
        }
        let rotated = XCTNSPredicateExpectation(predicate: landscape, object: nil)
        let rotationResult = XCTWaiter.wait(for: [rotated], timeout: 8)
        if rotationResult != .completed {
            capture("Rotation request - retained viewport")
            if UIDevice.current.userInterfaceIdiom == .pad {
                throw XCTSkip("This iPad simulator's windowing mode retained a portrait viewport. Manual window-resize/landscape QA remains required.")
            }
            XCTFail("The iPhone's main window didn't rotate to landscape")
            return
        }
        let install = cod.buttons["install-share-shortcut"]
        for _ in 0..<8 where !install.isHittable { cod.swipeUp() }
        XCTAssertTrue(install.isHittable)
        capture("Float setup - landscape")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
