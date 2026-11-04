import XCTest

/// Capture the actual interface with authored sample content. These aren't
/// evidence of a visible native PiP picture or final approved store branding.
final class SubmissionScreenshotTests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Screenshot drafts use disposable simulator text only")
        #endif
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        cod.terminate()
    }

    func testCaptureThirteenInchIPadScreenshots() throws {
        cod.launchArguments = ["--launch-ui-test"]
        cod.launch()
        XCTAssertTrue(cod.navigationBars["Cod"].waitForExistence(timeout: 8))
        reveal(cod.buttons["choose-photo"])
        try capture("22-iPad-01-Float")

        let text = cod.buttons["tool-text"]
        reveal(text); text.tap()
        let prompter = cod.switches["text-teleprompter"]
        XCTAssertTrue(prompter.waitForExistence(timeout: 5))
        if prompter.value as? String == "1" {
            prompter.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        }
        let clear = cod.buttons["clear-text"]
        reveal(clear); if clear.isEnabled { clear.tap() }
        let editor = cod.textViews["floating-text-editor"]
        reveal(editor); editor.tap()
        editor.typeText("Keep the details in view\n\nMeeting notes\n• Confirm the next milestone\n• Review the latest design\n• Share the finished work")
        cod.toolbars.buttons["Done"].tap()
        XCTAssertTrue(cod.buttons["float-text"].isHittable)
        try capture("22-iPad-02-Text")
        cod.navigationBars.buttons.element(boundBy: 0).tap()

        let timer = cod.buttons["tool-countdown"]
        reveal(timer); timer.tap()
        XCTAssertTrue(cod.buttons["float-tool"].waitForExistence(timeout: 5))
        try capture("22-iPad-03-Timer")
        cod.navigationBars.buttons.element(boundBy: 0).tap()

        let clock = cod.buttons["tool-clock"]
        reveal(clock); clock.tap()
        XCTAssertTrue(cod.buttons["float-tool"].waitForExistence(timeout: 5))
        try capture("22-iPad-04-Current-Time")
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 where !element.isHittable { cod.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String) throws {
        let screenshot = cod.screenshot()
        let image = try XCTUnwrap(screenshot.image.cgImage)
        XCTAssertEqual(image.width, 2064)
        XCTAssertEqual(image.height, 2752)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
