import XCTest

/// Window shapes, System Monitor readings, the Speedometer tool and Recents.
final class Build31UITests: XCTestCase {
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

    func testWindowShapeChangesTheFloatingFrame() {
        openTool("countdown")
        let preview = cod.images["Tool preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(preview.frame.width, preview.frame.height, "Timers start wide")
        let portrait = cod.buttons["window-shape-portrait"]
        reveal(portrait)
        portrait.tap()
        XCTAssertTrue(portrait.isSelected)
        reveal(preview, towardTop: true)
        XCTAssertGreaterThan(preview.frame.height, preview.frame.width, "Portrait renders a tall frame")
        capture("31 - Timer - portrait window shape")
        let square = cod.buttons["window-shape-square"]
        reveal(square); square.tap()
        reveal(preview, towardTop: true)
        XCTAssertEqual(preview.frame.width, preview.frame.height, accuracy: 2)
        cod.buttons["window-shape-wide"].tap()
    }

    func testSystemMonitorReadingsAreSwitches() {
        openTool("system")
        let all = ["battery", "temperature", "download", "upload", "connection", "storage", "memory", "cpu", "lowPower"]
        for metric in all {
            XCTAssertTrue(cod.switches["metric-\(metric)"].exists, "Missing \(metric) switch")
        }
        XCTAssertFalse(cod.switches["system-speed"].exists, "Speed moved to its own tool")
        // Needing at least one reading is covered by NewToolsTests.
        let cpu = cod.switches["metric-cpu"]
        setSwitch(cpu, on: true)
        capture("31 - System Monitor - reading switches")
        setSwitch(cpu, on: false)
        XCTAssertTrue(cod.buttons["float-tool"].isEnabled)
    }

    func testSpeedometerIsItsOwnToolNextToSystemMonitor() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        openTool("speedometer")
        // Opening the Speedometer asks for location the first time.
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let allow = alert.buttons["Allow While Using App"]
            (allow.exists ? allow : alert.buttons.element(boundBy: 0)).tap()
        }
        XCTAssertTrue(cod.navigationBars["Speedometer"].waitForExistence(timeout: 5))
        XCTAssertTrue(cod.segmentedControls["speed-units"].exists || cod.buttons["km/h"].exists)
        let toMonitor = cod.buttons["switch-system"]
        XCTAssertTrue(toMonitor.exists, "The switcher pairs Speedometer with System Monitor")
        capture("31 - Speedometer")
        toMonitor.tap()
        XCTAssertTrue(cod.navigationBars["System Monitor"].waitForExistence(timeout: 5))
    }

    func testStarredToolSetupsPinToTheTopOfRecents() {
        openTool("stopwatch")
        let float = cod.buttons["float-tool"]
        reveal(float, towardTop: true)
        float.tap()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.cod.staticTexts["Not available here"].exists || self.cod.staticTexts["Floating"].exists
        }, object: nil)
        _ = XCTWaiter.wait(for: [settled], timeout: 15)
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        openRecents()
        let row = cod.buttons["recents-tool-stopwatch"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), cod.debugDescription)
        let star = starButton(beside: row)
        if star.label == "Unstar" { star.tap() }
        XCTAssertEqual(star.label, "Star")
        star.tap()
        XCTAssertEqual(star.label, "Unstar")
        let starredHeading = cod.staticTexts["library-favorites-heading"]
        XCTAssertTrue(starredHeading.waitForExistence(timeout: 5))
        let recentHeading = cod.staticTexts["library-history-heading"]
        if recentHeading.exists {
            XCTAssertLessThan(row.frame.minY, recentHeading.frame.minY, "Starred rows sit above Recent")
        }
        capture("31 - Recents - starred tool pinned")
        cod.segmentedControls["library-filter"].buttons["Starred"].tap()
        XCTAssertTrue(row.exists)
        cod.segmentedControls["library-filter"].buttons["All"].tap()
        starButton(beside: row).tap()
    }

    func testMultiPagePDFsOpenReadyToFlipPagesPaused() {
        let lab = XCUIApplication()
        lab.launch()
        defer { lab.terminate() }
        lab.buttons["Open Test PDF In"].tap()
        let cell = lab.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Cod Test'")).firstMatch
        if !cell.waitForExistence(timeout: 5), lab.cells["More"].exists { lab.cells["More"].tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 8)); cell.tap()
        let mode = cod.segmentedControls["pdf-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10), cod.debugDescription)
        XCTAssertTrue(mode.buttons["Flip Pages"].isSelected, "Multi-page PDFs open in Flip Pages")
        XCTAssertTrue(cod.textFields["flip-first-page"].exists)
        XCTAssertTrue(cod.textFields["flip-last-page"].exists)
        XCTAssertTrue(cod.images["First page preview"].waitForExistence(timeout: 5))
        let float = cod.buttons["float-pdf-pages"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: float)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        capture("31 - PDF - flip pages")
        float.tap()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.cod.staticTexts["Not available here"].exists || self.cod.staticTexts["Floating"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 15), .completed, cod.debugDescription)
        // The paged set never auto-plays: its playback control offers Resume.
        let playPause = cod.buttons["tool-play-pause"]
        if playPause.waitForExistence(timeout: 5) {
            XCTAssertEqual(playPause.label, "Resume", "Pages open paused")
        }
    }

    // MARK: Helpers

    private func openTool(_ kind: String) {
        let tab = cod.tabBars.buttons["Float"]
        if tab.exists { tab.tap() }
        let tile = cod.buttons["tool-\(kind)"]
        reveal(tile)
        tile.tap()
    }

    private func openRecents() {
        cod.tabBars.buttons["Recents"].tap()
        XCTAssertTrue(cod.navigationBars["Recents"].waitForExistence(timeout: 5))
    }

    /// The star button on the same row as a Recents entry.
    private func starButton(beside row: XCUIElement) -> XCUIElement {
        let stars = cod.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'star-'"))
        let match = stars.allElementsBoundByIndex.first { abs($0.frame.midY - row.frame.midY) < 8 }
        XCTAssertNotNil(match, cod.debugDescription)
        return match.map { cod.buttons[$0.identifier] } ?? stars.firstMatch
    }

    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        reveal(toggle)
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        }
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 3), .completed, toggle.debugDescription)
    }

    private func reveal(_ element: XCUIElement, towardTop: Bool = false) {
        let list = cod.collectionViews.firstMatch
        for attempt in 0..<16 where !(element.exists && element.isHittable && inView(element)) {
            let target = list.exists ? list : cod
            // Head toward a visible element; otherwise search one way, then back.
            let down: Bool
            if element.exists, !element.frame.isEmpty {
                down = element.frame.midY < cod.windows.firstMatch.frame.midY
            } else {
                down = towardTop != (attempt >= 8)
            }
            // Short drags in the list's margin: swipes fling past rows in a
            // short settings list, and a drag over a switch could flip it.
            let from = target.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.3 : 0.7))
            let to = target.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.6 : 0.4))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.isHittable, cod.debugDescription)
    }

    /// Inside the visible part of the scrolling list: below a pinned preview
    /// or the navigation bar, and above the floating tab bar.
    private func inView(_ element: XCUIElement) -> Bool {
        let window = cod.windows.firstMatch.frame
        let list = cod.collectionViews.firstMatch
        let pinned = ["float-tool", "Tool preview"].contains(element.identifier) || element.label == "Tool preview"
        let top = list.exists && !pinned ? max(window.minY + 110, list.frame.minY + 12) : window.minY + 110
        return element.frame.minY > top && element.frame.maxY < window.maxY - 100
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
