import XCTest

final class Release18UITests: XCTestCase {
  private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

  override func setUpWithError() throws {
    continueAfterFailure = false
    #if !targetEnvironment(simulator)
      throw XCTSkip("Setup and recovery tests use disposable simulator preferences and files.")
    #endif
    cod.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  override func tearDownWithError() throws { cod.terminate() }

  func testIntroductionCanBeSkippedAndReopenedWithoutGrantingPermissions() {
    cod.launchArguments = ["--show-introduction"]
    cod.launch()
    let open = cod.buttons["open-introduction"]
    XCTAssertTrue(open.waitForExistence(timeout: 8))
    XCTAssertTrue(cod.buttons["choose-photo"].exists, "Setup must not block normal floating")
    open.tap()
    XCTAssertTrue(cod.buttons["skip-introduction"].waitForExistence(timeout: 5))
    XCTAssertTrue(cod.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Try a float'")).firstMatch.exists)
    capture("Optional first-run introduction")
    cod.buttons["skip-introduction"].tap()
    XCTAssertFalse(open.exists)
    cod.terminate()
    cod.launchArguments = []
    cod.launch()
    XCTAssertTrue(cod.buttons["choose-photo"].waitForExistence(timeout: 8))
    XCTAssertFalse(open.exists, "Skipping must persist without requiring Shortcut installation")
    let settings = cod.tabBars.buttons["Settings"]
    if settings.exists { settings.tap() } else { cod.buttons["Settings"].firstMatch.tap() }
    let replay = cod.buttons["reopen-introduction"]
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    replay.tap()
    XCTAssertTrue(cod.buttons["skip-introduction"].waitForExistence(timeout: 5))
    XCTAssertEqual(cod.alerts.count, 0)
  }

  func testIntroductionCompletionAndInstallerRemainReachableWithLargestText() {
    cod.launchArguments = ["--show-introduction", "--large-text-ui-test", "--dark-ui-test"]
    cod.launch()
    let open = cod.buttons["open-introduction"]
    reveal(open)
    open.tap()
    let installer = cod.buttons["intro-install-shortcut"]
    reveal(installer)
    XCTAssertTrue(installer.isHittable)
    capture("Introduction - largest text and optional installer")
    let finish = cod.buttons["finish-introduction"]
    reveal(finish)
    XCTAssertTrue(finish.isHittable)
    capture("Introduction - largest text and finish")
    finish.tap()
    XCTAssertFalse(cod.buttons["open-introduction"].exists)
  }

  func testCancellingFilesDoesNotShowAnImportError() {
    cod.launchArguments = ["--launch-ui-test"]
    cod.launch()
    let files = cod.buttons["choose-file"]
    reveal(files)
    files.tap()
    let cancel = cod.buttons["Cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 8), cod.debugDescription)
    cancel.tap()
    XCTAssertTrue(files.waitForExistence(timeout: 5))
    XCTAssertFalse(cod.staticTexts["media-import-error"].exists)
    XCTAssertFalse(cod.staticTexts["Couldn't open file"].exists)
    capture("Cancelled Files picker - no error")
  }

  func testCorruptPDFShowsRecoveryThenAValidDocumentOpensWithoutSetup() {
    cod.launchArguments = ["--show-introduction"]
    cod.launch()
    XCTAssertTrue(cod.buttons["open-introduction"].waitForExistence(timeout: 8))
    let lab = XCUIApplication()
    lab.launchArguments = ["--invalid-pdf"]
    lab.launch()
    lab.buttons["Open Test PDF In"].tap()
    selectCod(in: lab)
    let failure = cod.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Couldn't open file")).firstMatch
    XCTAssertTrue(failure.waitForExistence(timeout: 8), cod.debugDescription)
    capture("Corrupt PDF - actionable failure")
    lab.terminate()
    lab.launchArguments = []
    lab.launch()
    lab.buttons["Open Test PDF In"].tap()
    selectCod(in: lab)
    XCTAssertTrue(cod.textFields["pdf-page-number"].waitForExistence(timeout: 8))
    XCTAssertTrue(cod.buttons["float-pdf-page"].isEnabled)
    capture("Valid document recovery - no mandatory introduction")
  }

  private func selectCod(in app: XCUIApplication) {
    let cell = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Cod Test'")).firstMatch
    if !cell.waitForExistence(timeout: 5), app.cells["More"].exists { app.cells["More"].tap() }
    XCTAssertTrue(cell.waitForExistence(timeout: 8), app.debugDescription)
    cell.tap()
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<25 {
      if element.exists && element.isHittable { return }
      cod.swipeUp()
    }
    XCTAssertTrue(element.isHittable, cod.debugDescription)
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
