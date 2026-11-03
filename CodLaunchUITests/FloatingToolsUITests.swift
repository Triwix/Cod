import XCTest
import UIKit

final class FloatingToolsUITests: XCTestCase {
    private let cod = XCUIApplication(bundleIdentifier: "com.josh.cod.store")

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Tool UI tests use disposable simulator drafts and documents.")
        #endif
        cod.terminate()
        XCUIDevice.shared.orientation = .portrait
        cod.launchArguments = ["--launch-ui-test"]
        cod.launch()
        clearPreviousSimulatorAlarms()
    }

    override func tearDownWithError() throws {
        cod.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testTextDraftPreviewAndFloatAction() {
        openTextEditor(prompter: false)
        let editor = cod.textViews["floating-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let clear = cod.buttons["clear-text"]
        reveal(clear)
        if clear.isEnabled { clear.tap() }
        editor.tap()
        editor.typeText("Actual reference: Gate 7 at 14:30")
        cod.toolbars.buttons["Done"].tap()
        let float = cod.buttons["float-text"]
        reveal(float)
        XCTAssertTrue(float.isEnabled)
        capture("Floating text preview")
        float.tap()
        XCTAssertTrue(cod.buttons["tool-text"].waitForExistence(timeout: 5), "Float should leave the editor, not trap users in it")
    }

    func testTimerValidationAndAllLiveEditorsAreDiscoverable() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry)
        entry.tap()
        XCTAssertTrue(cod.pickers["timer-minutes"].pickerWheels.firstMatch.waitForExistence(timeout: 5))
        let button = cod.buttons["float-tool"]
        reveal(button)
        XCTAssertTrue(button.isEnabled)
        capture("Timer setup")
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        for kind in ["stopwatch", "clock", "pomodoro"] {
            let entry = cod.buttons["tool-\(kind)"]
            reveal(entry)
            entry.tap()
        XCTAssertTrue(cod.buttons["float-tool"].waitForExistence(timeout: 5))
            capture("\(kind) setup")
            cod.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testPrompterRequiresScriptAndProvidesControls() {
        openTextEditor(prompter: true)
        let editor = cod.textViews["floating-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(cod.buttons["float-tool"].isEnabled, "An empty draft can float its sample")
        editor.tap()
        if let old = editor.value as? String, !old.isEmpty { editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        editor.typeText("First line of a real script.\nSecond line stays readable.\nThird line for the floating prompter.")
        cod.toolbars.buttons["Done"].tap()
        let float = cod.buttons["float-tool"]
        reveal(float)
        capture("Teleprompter setup")
        XCTAssertTrue(float.isEnabled)
        float.tap()
        reveal(cod.buttons["tool-play-pause"])
        XCTAssertTrue(cod.buttons["tool-play-pause"].waitForExistence(timeout: 5))
        XCTAssertTrue(cod.buttons["Restart"].exists)
        capture("Teleprompter playback controls")
    }

    func testSharedTextUsesSupportedManualOpenAndDoesNotLaunchCod() {
        // Match the existing supported Share route, but with real plain text.
        setManualShare()
        let lab = XCUIApplication()
        lab.launch()
        lab.buttons["Share Test Text"].tap()
        selectCod(in: lab)
        let finished = NSPredicate { _, _ in lab.buttons["Share Test Text"].isHittable && lab.sheets.count == 0 }
        expectation(for: finished, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        XCTAssertNotEqual(cod.state, .runningForeground)
        cod.activate()
        XCTAssertTrue(cod.staticTexts["received-image-size"].waitForExistence(timeout: 8))
        XCTAssertTrue(cod.staticTexts["received-image-size"].label.contains("900x"), "Shared text must reach the real text renderer")
    }

    func testPDFDocumentOpeningPageSelectionAndCrop() {
        let lab = XCUIApplication()
        lab.launch()
        lab.buttons["Open Test PDF In"].tap()
        selectCod(in: lab)
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10))
        let stepper = cod.steppers["pdf-page"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 8), cod.debugDescription)
        XCTAssertTrue(cod.staticTexts["floating-preview-label"].isHittable)
        capture("PDF first page")
        stepper.buttons["pdf-page-Increment"].tap()
        expectation(for: NSPredicate(format: "value == '2'"), evaluatedWith: cod.textFields["pdf-page-number"])
        waitForExpectations(timeout: 5)
        capture("PDF second page")
        let crop = cod.buttons["crop-pdf-region"]
        reveal(crop)
        crop.tap()
        XCTAssertTrue(cod.buttons["cancel-selection"].waitForExistence(timeout: 5))
        capture("PDF crop surface")
        cod.buttons["Zoom in"].tap()
        cod.buttons["Zoom in"].tap()
        XCTAssertEqual(cod.buttons["crop-zoom-level"].value as? String, "200%")
        let canvas = cod.descendants(matching: .any).matching(identifier: "crop-canvas").firstMatch
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.25, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.7, dy: 0.55)))
        capture("PDF zoomed region selection")
        cod.buttons["Move image"].tap()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.7)))
        cod.buttons["Select region"].tap()
        cod.buttons["Fit whole image"].tap()
        XCTAssertEqual(cod.buttons["crop-zoom-level"].value as? String, "100%")
        cod.buttons["cancel-selection"].tap()
    }

    private func openTextEditor(prompter: Bool) {
        openTools()
        let entry = cod.buttons["tool-text"]
        reveal(entry); entry.tap()
        let toggle = cod.switches["text-teleprompter"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        reveal(toggle, towardTop: true)
        if toggle.value as? String != (prompter ? "1" : "0") {
            toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        }
    }

    private func openTools() {
        tapMainTab("Float")
        XCTAssertFalse(cod.tabBars.buttons["Tools"].exists, "All floating choices belong on one Float tab")
    }

    private func tapMainTab(_ title: String) {
        // iPadOS exposes nested duplicate tab buttons; use the actual hittable
        // child, and wait for any presented editor/PiP dismissal to settle.
        let bottom = cod.tabBars.buttons[title]
        let matches = cod.buttons.matching(NSPredicate(format: "label == %@", title))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if bottom.exists { return bottom.isHittable }
            return matches.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, cod.debugDescription)
        if bottom.exists { bottom.tap() }
        else { matches.allElementsBoundByIndex.last(where: { $0.isHittable })?.tap() }
    }

    func testToolFormsRemainUsableWithLargeTextAndDarkAppearance() {
        cod.terminate()
        cod.launchArguments = ["--large-text-ui-test", "--dark-ui-test"]
        cod.launch()
        openTools()
        let pomodoro = cod.buttons["tool-pomodoro"]
        reveal(pomodoro)
        pomodoro.tap()
        let float = cod.buttons["float-tool"]
        reveal(float)
        XCTAssertTrue(float.isEnabled)
        capture("Pomodoro - largest text and dark appearance")
    }

    func testCurrentTimeHasNoMeaninglessResumeOrRestartControls() {
        openTools()
        let entry = cod.buttons["tool-clock"]
        reveal(entry)
        XCTAssertTrue(entry.label.contains("Current Time"))
        entry.tap()
        let float = cod.buttons["float-tool"]
        reveal(float)
        float.tap()
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        let controls = cod.buttons["Playback controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 12))
        reveal(controls)
        controls.tap()
        XCTAssertFalse(cod.buttons["tool-play-pause"].exists)
        XCTAssertFalse(cod.buttons["Restart"].exists)
        capture("Current Time - no resume or restart")
    }

    func testStopwatchExposesPauseInItsEditor() {
        openTools()
        let entry = cod.buttons["tool-stopwatch"]
        reveal(entry)
        entry.tap()
        let float = cod.buttons["float-tool"]
        reveal(float)
        float.tap()
        let toggle = cod.buttons["tool-play-pause"]
        reveal(toggle)
        if toggle.label == "Resume" { toggle.tap() }
        XCTAssertEqual(toggle.label, "Pause")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Resume")
        capture("Stopwatch pause - in editor")
    }

    func testAllColorCapableEditorsHaveNativeColorSelectors() {
        openTools()
        for kind in ["text", "countdown", "stopwatch", "clock", "pomodoro", "teleprompter"] {
            let entry = cod.buttons["tool-\(kind)"]
            reveal(entry)
            entry.tap()
            XCTAssertEqual(cod.staticTexts["floating-preview-label"].label, "Preview")
            for identifier in ["floating-background-color", "floating-text-color"] {
                let selector = cod.descendants(matching: .any).matching(identifier: identifier).firstMatch
                reveal(selector)
            }
            capture("\(kind) - color selectors")
            cod.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testNativeColorPickerKeepsPreviewVisibleAndAllowsLiveChanges() throws {
        openTools()
        let entry = cod.buttons["tool-text"]
        reveal(entry); entry.tap()
        let preset = cod.buttons["floating-preset"]
        reveal(preset); preset.tap()
        cod.buttons["Dark"].tap()
        let clear = cod.buttons["clear-text"]
        reveal(clear); if clear.isEnabled { clear.tap() }
        let background = cod.buttons["floating-background-color"]
        reveal(background)
        XCTAssertTrue(cod.staticTexts["floating-preview-label"].isHittable)
        let preview = cod.images["Floating text preview"]
        let original = try previewPixels(preview)
        capture("Color picker - preview before presentation")
        background.tap()
        let done = cod.buttons["floating-color-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), cod.debugDescription)
        capture("Color picker - native colors with undimmed preview")
        XCTAssertTrue(cod.staticTexts["floating-preview-label"].exists)
        XCTAssertLessThan(preview.frame.maxY, done.frame.minY, "The picker must leave the preview exposed")
        // Native UIColorPicker marks its full-screen accessibility container
        // modal even for an undimmed sheet. Compare the real preview pixels,
        // not isHittable, to catch the user's actual dimming complaint.
        XCTAssertTrue(try previewPixels(preview) == original, "Opening colors must not fade or dim the preview")
        let white = cod.otherElements["white 100"]
        XCTAssertTrue(white.exists); white.tap()
        XCTAssertTrue(try previewPixels(preview) != original, "Native selection must update the actual preview while the sheet stays open")
        capture("Color picker - live background update")
        done.tap()
        XCTAssertFalse(done.exists)
        let reset = cod.buttons["Reset colors to preset"]
        reveal(reset)
        XCTAssertTrue(reset.isHittable)
        let foreground = cod.buttons["floating-text-color"]
        reveal(foreground); foreground.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        let beforeText = try previewPixels(preview)
        let red = cod.otherElements["red 51"]
        XCTAssertTrue(red.exists); red.tap()
        XCTAssertTrue(try previewPixels(preview) != beforeText, "Text color must also update immediately")
        capture("Color picker - text color with undimmed preview")
        done.tap()
        reveal(reset); reset.tap()
        XCTAssertFalse(reset.exists)
    }

    private func previewPixels(_ preview: XCUIElement) throws -> Data {
        let screenshot = XCUIScreen.main.screenshot().image
        let rect = preview.frame.insetBy(dx: 6, dy: 6)
            .applying(CGAffineTransform(scaleX: screenshot.scale, y: screenshot.scale))
        let cropped = try XCTUnwrap(screenshot.cgImage?.cropping(to: rect))
        return try XCTUnwrap(UIImage(cgImage: cropped).pngData())
    }

    func testHomeHasNoRecentItemsWhileLibraryRetainsHistory() {
        openLibrary()
        if cod.buttons["enable-history"].exists { cod.buttons["enable-history"].tap() }
        cod.segmentedControls["library-filter"].buttons["All"].tap()
        openTools()
        let entry = cod.buttons["tool-text"]
        reveal(entry); entry.tap()
        cod.buttons["float-text"].tap()
        let stop = cod.buttons["Stop Floating"]
        if stop.waitForExistence(timeout: 12) { reveal(stop); stop.tap() }
        openLibrary()
        let saved = cod.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-capture-'"))
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(cod.staticTexts["library-history-heading"].exists)
        capture("Library - history remains available")
        openTools()
        let guide = cod.buttons["Floating guide & setup"]
        reveal(guide)
        XCTAssertFalse(cod.staticTexts["Recent items"].exists)
        XCTAssertFalse(cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open saved '")).firstMatch.exists)
        capture("Float home - no duplicated recent items")
    }

    func testTimerAlarmUsesSystemPermissionAndCanBeCancelled() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry)
        entry.tap()
        let alarm = cod.switches["timer-alarm-enabled"]
        reveal(alarm)
        if alarm.value as? String != "1" { alarm.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        let float = cod.buttons["float-tool"]
        reveal(float)
        float.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = system.alerts.firstMatch
        if permission.waitForExistence(timeout: 5), permission.buttons["Allow"].exists {
            capture("Timer alarm - real system permission")
            permission.buttons["Allow"].tap()
        }
        let scheduled = cod.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Alarm: '")).firstMatch
        for _ in 0..<6 where !scheduled.exists { cod.swipeUp() }
        XCTAssertTrue(scheduled.waitForExistence(timeout: 8), cod.debugDescription)
        capture("Timer alarm - system schedule confirmed")
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        let cancel = cod.buttons["cancel-timer-alarm"]
        // Navigation restores the Float list near the selected Timer row.
        // Alarm rows are ABOVE that position, not farther down the list.
        for _ in 0..<10 where !cancel.isHittable { cod.swipeDown() }
        XCTAssertTrue(cancel.isHittable, cod.debugDescription)
        cancel.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: cancel)
        waitForExpectations(timeout: 8)
        capture("Timer alarm - cancelled from unified Float list")
    }

    func testTimerAlarmFiresAfterCodIsClosed() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry)
        entry.tap()
        let minutes = cod.pickers["timer-minutes"].pickerWheels.firstMatch
        reveal(minutes)
        cod.pickers["timer-hours"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "0")
        minutes.adjust(toPickerWheelValue: "1")
        cod.pickers["timer-seconds"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "0")
        let alarm = cod.switches["timer-alarm-enabled"]
        reveal(alarm)
        if alarm.value as? String != "1" { alarm.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        let float = cod.buttons["float-tool"]
        reveal(float)
        float.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = system.alerts.firstMatch
        if permission.waitForExistence(timeout: 3), permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
        let scheduled = cod.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Alarm: '")).firstMatch
        for _ in 0..<6 where !scheduled.exists { cod.swipeUp() }
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        cod.terminate()
        let title = system.staticTexts["Timer finished"]
        XCTAssertTrue(title.waitForExistence(timeout: 80), system.debugDescription)
        capture("Timer alarm - delivered with Cod terminated")
        let stop = system.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), system.debugDescription)
        stop.tap()
        cod.launch()
        XCTAssertFalse(cod.buttons["cancel-timer-alarm"].exists, "A system-dismissed alarm must not remain in Cod's alarm list")
    }
    private func reveal(_ element: XCUIElement, towardTop: Bool = false) {
        // In landscape, iOS can report a clipped lazy-list row as hittable
        // even with its center ABOVE the navigation bar. Check real geometry.
        func viewport() -> CGRect {
            let window = cod.windows.allElementsBoundByIndex.map(\.frame).max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
            let scroll = cod.collectionViews.firstMatch
            let pinned = element.exists && ["float-tool", "float-text", "float-pdf-page", "crop-pdf-region"].contains(element.identifier)
            let bounds = scroll.exists && !pinned ? scroll.frame.intersection(window) : window
            var top = max(window.minY + 80, bounds.minY + 8)
            let bottomInset: CGFloat = cod.tabBars.firstMatch.exists ? 80 : 32
            var bottom = min(window.maxY - bottomInset, bounds.maxY - 8)
            if cod.keyboards.firstMatch.exists { bottom = min(bottom, cod.keyboards.firstMatch.frame.minY - 8) }
            if bottom <= top { top = bounds.minY; bottom = bounds.maxY }
            return CGRect(x: bounds.minX, y: top, width: bounds.width, height: max(1, bottom - top))
        }
        func visible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let bounds = viewport()
            return element.frame.midY > bounds.minY && element.frame.midY < bounds.maxY
        }
        for _ in 0..<14 {
            if visible() { return }
            let scroll = cod.collectionViews.firstMatch
            let down = towardTop || (element.exists && !element.frame.isEmpty && element.frame.midY < viewport().midY)
            if scroll.exists {
                let bounds = viewport()
                // Drag the list gutter, not a wheel, slider or switch. A
                // center drag can edit the control instead of scrolling.
                let x = bounds.minX + 8
                let first = CGPoint(x: x, y: down ? bounds.minY + bounds.height * 0.25 : bounds.minY + bounds.height * 0.75)
                let last = CGPoint(x: x, y: down ? bounds.minY + bounds.height * 0.65 : bounds.minY + bounds.height * 0.35)
                let origin = scroll.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: first.x - scroll.frame.minX, dy: first.y - scroll.frame.minY))
                let end = origin.withOffset(CGVector(dx: last.x - scroll.frame.minX, dy: last.y - scroll.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.15)
            } else {
                if down { cod.swipeDown() } else { cod.swipeUp() }
            }
        }
        XCTAssertTrue(visible(), cod.debugDescription)
    }

    func testTimerWheelsRememberDurationAfterRelaunch() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry); entry.tap()
        let minutes = cod.pickers["timer-minutes"].pickerWheels.firstMatch
        reveal(minutes)
        cod.pickers["timer-hours"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "1")
        minutes.adjust(toPickerWheelValue: "2")
        cod.pickers["timer-seconds"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "3")
        capture("Timer - hour minute second wheels")
        cod.terminate(); cod.launch(); openTools()
        reveal(entry); entry.tap(); reveal(minutes)
        XCTAssertEqual(cod.pickers["timer-hours"].pickerWheels.firstMatch.value as? String, "1")
        XCTAssertEqual(minutes.value as? String, "2")
        XCTAssertEqual(cod.pickers["timer-seconds"].pickerWheels.firstMatch.value as? String, "3")
    }

    func testPhotoAndScreenshotActionsAreCompactHorizontalPairs() {
        openTools()
        let photo = cod.buttons["choose-photo"]
        let cropPhoto = cod.buttons["crop-photo"]
        reveal(photo)
        XCTAssertTrue(cropPhoto.isHittable)
        XCTAssertEqual(photo.frame.midY, cropPhoto.frame.midY, accuracy: 2)
        let float = cod.buttons["float-latest-screenshot"]
        let crop = cod.buttons["crop-latest-screenshot"]
        reveal(float)
        XCTAssertTrue(crop.isHittable)
        XCTAssertEqual(float.frame.midY, crop.frame.midY, accuracy: 2)
        XCTAssertLessThan(abs(photo.frame.midY - float.frame.midY), 120)
        capture("Images - compact explicit Float and Crop pairs")
    }

    func testUnifiedMediaAndFileChoicesReplaceSeparateVideoAndPDFRows() {
        openTools()
        XCTAssertTrue(cod.buttons["choose-photo"].label.contains("Video"))
        let file = cod.buttons["choose-file"]
        reveal(file)
        XCTAssertFalse(cod.buttons["choose-video"].exists)
        XCTAssertFalse(cod.buttons["tool-pdf"].exists)
        XCTAssertTrue(cod.buttons["tool-text"].exists)
        XCTAssertFalse(cod.buttons["tool-teleprompter"].exists)
        XCTAssertFalse(cod.buttons["scroll-photo"].exists)
        XCTAssertFalse(cod.buttons["read-photo-text"].exists)
        capture("Unified media, documents, text and reading")
        file.tap()
        XCTAssertTrue(cod.staticTexts["Recents"].firstMatch.waitForExistence(timeout: 5) || cod.navigationBars["Browse"].exists || cod.buttons["Browse"].exists, cod.debugDescription)
        let cancel = cod.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() }
    }

    func testPinnedTimerPreviewAndClosePreferenceSurviveScrollingAndRelaunch() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry); entry.tap()
        let float = cod.buttons["float-tool"]
        XCTAssertTrue(float.isHittable)
        let originalY = float.frame.midY
        let keep = cod.switches["timer-keep-running"]
        reveal(keep)
        XCTAssertTrue(float.isHittable)
        XCTAssertEqual(float.frame.midY, originalY, accuracy: 2)
        if keep.value as? String != "0" { keep.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        reveal(cod.descendants(matching: .any).matching(identifier: "floating-background-color").firstMatch)
        XCTAssertTrue(float.isHittable)
        capture("Timer - pinned circular preview while adjusting appearance")
        cod.terminate(); cod.launch(); openTools(); reveal(entry); entry.tap(); reveal(keep)
        XCTAssertEqual(keep.value as? String, "0")
        keep.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
    }

    func testStopwatchHundredthsPreviewAndPreference() {
        openTools()
        let entry = cod.buttons["tool-stopwatch"]
        reveal(entry); entry.tap()
        let toggle = cod.switches["stopwatch-hundredths"]
        reveal(toggle)
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertTrue(cod.buttons["float-tool"].isHittable)
        capture("Stopwatch - hundredths preview")
        cod.terminate(); cod.launch(); openTools(); reveal(entry); entry.tap(); reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testNativeTimerCloseHonorsBothKeepRunningChoices() {
        for keepRunning in [false, true] {
            openTools()
            let entry = cod.buttons["tool-countdown"]
            reveal(entry); entry.tap()
            let minutes = cod.pickers["timer-minutes"].pickerWheels.firstMatch
            reveal(minutes)
            cod.pickers["timer-hours"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "0")
            minutes.adjust(toPickerWheelValue: "1")
            cod.pickers["timer-seconds"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "0")
            let alarm = cod.switches["timer-alarm-enabled"]
            reveal(alarm)
            if alarm.value as? String != "1" { alarm.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
            let keep = cod.switches["timer-keep-running"]
            reveal(keep)
            if (keep.value as? String == "1") != keepRunning { keep.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
            cod.buttons["float-tool"].tap()
            let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let permission = system.alerts.firstMatch
            if permission.waitForExistence(timeout: 2), permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
            let controls = cod.buttons["Playback controls"]
            reveal(controls); controls.tap()
            let stop = cod.buttons["Stop Floating"]
            XCTAssertTrue(stop.waitForExistence(timeout: 25), cod.debugDescription)
            stop.tap()
            let playback = cod.buttons["tool-play-pause"]
            let expected = keepRunning ? "Pause" : "Resume"
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: playback)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
            capture("Timer close - keep running \(keepRunning)")
            if keepRunning { playback.tap() }
            cod.navigationBars.buttons.element(boundBy: 0).tap()
            cod.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    func testPinnedTextPreviewLeavesEditorUsableWithKeyboardAndLargeText() {
        cod.terminate(); cod.launchArguments = ["--large-text-ui-test", "--dark-ui-test"]; cod.launch()
        openTextEditor(prompter: false)
        let editor = cod.textViews["floating-text-editor"]
        reveal(editor); editor.tap(); editor.typeText("Pinned preview test")
        XCTAssertTrue(cod.buttons["float-text"].isHittable)
        capture("Text - pinned preview with keyboard and accessibility text")
        cod.toolbars.buttons["Done"].tap()
        reveal(cod.sliders["Text size"])
        XCTAssertTrue(cod.buttons["float-text"].isHittable)
    }

    func testPinnedPreviewAdaptsToPhoneLandscape() {
        cod.terminate(); cod.launchArguments = ["--landscape-ui-test", "--dark-ui-test"]; cod.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = self.cod.windows.allElementsBoundByIndex.map(\.frame).max(by: { $0.width * $0.height < $1.width * $1.height }) ?? .zero
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        openTools()
        let entry = cod.buttons["tool-pomodoro"]
        reveal(entry); entry.tap()
        let float = cod.buttons["float-tool"]
        capture("Phone landscape - opened tool editor")
        XCTAssertTrue(float.waitForExistence(timeout: 5), cod.debugDescription); XCTAssertTrue(float.isHittable)
        let appearance = cod.descendants(matching: .any).matching(identifier: "floating-text-color").firstMatch
        reveal(appearance)
        XCTAssertTrue(float.isHittable)
        capture("Pinned circular preview - phone landscape and dark appearance")
    }

    func testLibraryFavoritesStayAboveNewHistoryAndClearChoicesAreExplicit() {
        openLibrary()
        if cod.buttons["enable-history"].exists { cod.buttons["enable-history"].tap() }
        if cod.buttons["library-options"].exists {
            cod.buttons["library-options"].tap(); cod.buttons["Clear Library…"].tap()
            cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete Everything, Including Favorites'")).firstMatch.tap()
        }
        let lab = XCUIApplication()
        lab.launch(); lab.buttons["Open Test Video In"].tap(); selectCod(in: lab)
        XCTAssertTrue(cod.buttons["float-video"].waitForExistence(timeout: 10))
        cod.buttons["float-video"].tap()
        let stop = cod.buttons["stop-video-float"]
        // Library persistence is independent of native PiP availability. Close
        // the preview after the import; don't make storage QA require real PiP.
        if stop.waitForExistence(timeout: 4) { stop.tap() }
        cod.buttons["Close"].tap()
        openLibrary()
        let cells = cod.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-capture-'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 8))
        cells.firstMatch.tap()
        let star = cod.buttons["favorite-capture"]
        if star.label == "Favorite" { star.tap() }
        cod.buttons["Done"].tap()
        let favorite = cells.firstMatch
        let favoriteID = favorite.identifier
        lab.activate(); lab.buttons["Open Test Video In"].tap(); selectCod(in: lab)
        let floatAgain = cod.buttons["float-video"]
        XCTAssertTrue(floatAgain.waitForExistence(timeout: 10)); floatAgain.tap()
        if stop.waitForExistence(timeout: 4) { stop.tap() }
        cod.buttons["Close"].tap()
        openLibrary()
        XCTAssertTrue(cod.staticTexts["library-favorites-heading"].waitForExistence(timeout: 5))
        let saved = cod.buttons[favoriteID]
        XCTAssertTrue(saved.exists)
        XCTAssertEqual(cells.firstMatch.identifier, favoriteID)
        XCTAssertTrue(cod.staticTexts["library-history-heading"].exists)
        capture("Library - favorites stay above new history")
        cod.buttons["library-options"].tap()
        cod.buttons["Clear Library…"].tap()
        let recent = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Clear Recent History ('")).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); recent.tap()
        XCTAssertTrue(saved.exists)
        XCTAssertFalse(cod.staticTexts["library-history-heading"].exists)
        cod.buttons["library-options"].tap(); cod.buttons["Clear Library…"].tap()
        let all = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete Everything, Including Favorites'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5)); capture("Library - explicit delete everything confirmation"); all.tap()
        XCTAssertFalse(saved.exists)
        XCTAssertFalse(cod.staticTexts["library-favorites-heading"].exists)
    }

    private func openLibrary() {
        tapMainTab("Library")
        XCTAssertTrue(cod.navigationBars["Library"].waitForExistence(timeout: 5), cod.debugDescription)
    }

    func testTwoSecondAlarmAlertsWhileCodStaysForeground() {
        assertShortAlarmWhileMusicPlays(seconds: 2)
    }

    func testOneSecondAlarmAlertsWhileCodStaysForeground() {
        assertShortAlarmWhileMusicPlays(seconds: 1)
    }

    private func assertShortAlarmWhileMusicPlays(seconds: Int) {
        let lab = XCUIApplication()
        lab.launch()
        XCTAssertTrue(lab.buttons["Play Test Music"].waitForExistence(timeout: 5))
        lab.buttons["Play Test Music"].tap()
        defer { lab.terminate() }
        XCTAssertTrue(lab.buttons["Stop Test Music"].waitForExistence(timeout: 3), "The separate audio player must actually start, not merely receive a tap")
        cod.activate()
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry); entry.tap()
        let minutes = cod.pickers["timer-minutes"].pickerWheels.firstMatch
        reveal(minutes)
        cod.pickers["timer-hours"].pickerWheels.firstMatch.adjust(toPickerWheelValue: "0")
        minutes.adjust(toPickerWheelValue: "0")
        cod.pickers["timer-seconds"].pickerWheels.firstMatch.adjust(toPickerWheelValue: String(seconds))
        let alarm = cod.switches["timer-alarm-enabled"]
        reveal(alarm)
        if alarm.value as? String != "1" { alarm.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        let float = cod.buttons["float-tool"]
        for _ in 0..<8 where !float.isHittable { cod.swipeDown() }
        XCTAssertTrue(float.isHittable); float.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permission = system.alerts.firstMatch
        if permission.waitForExistence(timeout: 2), permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
        XCTAssertTrue(system.staticTexts["Timer finished"].waitForExistence(timeout: 35), system.debugDescription)
        capture("\(seconds)-second timer - system alert with Cod foreground")
        let stop = system.buttons["Stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
    }

    func testLibraryCanEnableHistoryDirectly() {
        cod.tabBars.buttons["Settings"].tap()
        let limit = cod.buttons["history-limit"]
        reveal(limit); limit.tap()
        cod.buttons["Off"].tap()
        let remove = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove ' AND label ENDSWITH ' Images'")).firstMatch
        if remove.waitForExistence(timeout: 2) { remove.tap() }
        let library = cod.tabBars.buttons["Library"]
        for _ in 0..<3 where !library.isSelected {
            library.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.3)).tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: library)
            _ = XCTWaiter.wait(for: [selected], timeout: 2)
        }
        XCTAssertTrue(library.isSelected, "The system tab bar must switch to Library")
        let enable = cod.buttons["enable-history"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5), cod.debugDescription)
        enable.tap()
        XCTAssertFalse(enable.exists)
        cod.tabBars.buttons["Settings"].tap(); reveal(limit)
        XCTAssertTrue(limit.label.contains("10") || limit.value as? String == "10", cod.debugDescription)
        capture("Library - one-tap history enabling")
    }

    func testSamplePlaceholdersClearAndWordsMode() {
        openTextEditor(prompter: false)
        let clear = cod.buttons["clear-text"]
        reveal(clear)
        if clear.isEnabled { clear.tap() }
        XCTAssertEqual(cod.textViews["floating-text-editor"].value as? String, "")
        for _ in 0..<5 where !cod.buttons["float-text"].isHittable { cod.swipeDown() }
        XCTAssertTrue(cod.buttons["float-text"].isEnabled)
        capture("Text - sample is not editable draft")
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        openTextEditor(prompter: true)
        let clearScript = cod.buttons["clear-text"]
        reveal(clearScript)
        if clearScript.isEnabled { clearScript.tap() }
        XCTAssertEqual(cod.textViews["floating-text-editor"].value as? String, "")
        let mode = cod.segmentedControls["prompter-mode"]
        reveal(mode); mode.buttons["Words"].tap()
        reveal(cod.steppers["prompter-word-count"])
        XCTAssertTrue(cod.sliders["Words per minute"].exists)
        XCTAssertFalse(cod.sliders["Scroll speed"].exists)
        capture("Teleprompter - centered words mode")
    }

    func testVideoDocumentImportNativePiPAndLibraryFavorite() {
        let lab = XCUIApplication()
        lab.launch()
        let open = lab.buttons["Open Test Video In"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap(); selectCod(in: lab)
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10))
        let float = cod.buttons["float-video"]
        XCTAssertTrue(float.waitForExistence(timeout: 10), cod.debugDescription)
        XCTAssertTrue(cod.staticTexts["floating-preview-label"].isHittable)
        capture("Video - actual imported movie")
        float.tap()
        let stop = cod.buttons["stop-video-float"]
        XCTAssertTrue(stop.waitForExistence(timeout: 35), cod.debugDescription)
        capture("Video - native PiP active")
        stop.tap()
        let close = cod.buttons["Close"]
        let canClose = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in close.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [canClose], timeout: 8), .completed)
        close.tap()
        openLibrary()
        let saved = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved imported'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8), cod.debugDescription)
        saved.tap()
        let favorite = cod.buttons["favorite-capture"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        if favorite.label == "Favorite" { favorite.tap() }
        XCTAssertEqual(favorite.label, "Remove Favorite")
        capture("Library - reusable favorite video")
        cod.buttons["Done"].tap()
        cod.segmentedControls["library-filter"].buttons["Favorites"].tap()
        XCTAssertTrue(saved.exists)
    }

    private func clearPreviousSimulatorAlarms() {
        // Only disposable simulator alarms created by this test suite. A
        // failed assertion mustn't leave a ringing alarm in later UI tests.
        let matches = cod.buttons.matching(identifier: "cancel-timer-alarm")
        for _ in 0..<8 {
            let cancel = matches.firstMatch
            guard cancel.exists else { return }
            if !cancel.isHittable { cod.swipeDown() }
            guard cancel.isHittable else { return }
            let count = matches.count
            cancel.tap()
            let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in matches.count < count }, object: nil)
            _ = XCTWaiter.wait(for: [removed], timeout: 4)
        }
    }

    func testVideoRepeatsByDefaultWithNativePiPAndCanBeSwitchedOff() {
        let lab = XCUIApplication()
        lab.launchArguments = ["--short-video"]
        lab.launch()
        defer { lab.terminate() }
        lab.buttons["Open Test Video In"].tap(); selectCod(in: lab)
        let repeatToggle = cod.switches["video-repeat"]
        XCTAssertTrue(repeatToggle.waitForExistence(timeout: 10), cod.debugDescription)
        XCTAssertEqual(repeatToggle.value as? String, "1")
        XCTAssertEqual(cod.switches["Video sound"].value as? String, "0")
        cod.buttons["float-video"].tap()
        let stop = cod.buttons["stop-video-float"]
        XCTAssertTrue(stop.waitForExistence(timeout: 25), cod.debugDescription)
        let counter = cod.staticTexts["video-repeat-count"]
        let repeated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard counter.exists, let count = Int(counter.label.split(separator: " ").last ?? "") else { return false }
            return count >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [repeated], timeout: 15), .completed)
        XCTAssertTrue(stop.exists, "The native PiP window must survive multiple movie repeats")
        capture("Video - real three-second movie repeats in native PiP")
        repeatToggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(repeatToggle.value as? String, "0")
        if stop.exists { stop.tap() }
        cod.buttons["Close"].tap()
        lab.activate(); lab.buttons["Open Test Video In"].tap(); selectCod(in: lab)
        XCTAssertTrue(repeatToggle.waitForExistence(timeout: 10))
        XCTAssertEqual(repeatToggle.value as? String, "1", "Newly opened videos default to repeating")
        capture("Video - repeat is on for a newly selected video")
        cod.buttons["Close"].tap()
    }

    func testPomodoroNumbersCanBeTypedAndInvalidInputCannotFloat() {
        openTools()
        let entry = cod.buttons["tool-pomodoro"]
        reveal(entry); entry.tap()
        func replace(_ field: XCUIElement, with text: String) {
            reveal(field); field.tap()
            let value = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + text)
            XCTAssertEqual(field.value as? String, text, cod.debugDescription)
        }
        replace(cod.textFields["pomodoro-focus"], with: "125")
        cod.toolbars.buttons["Done"].tap()
        replace(cod.textFields["pomodoro-break"], with: "17")
        cod.toolbars.buttons["Done"].tap()
        replace(cod.textFields["pomodoro-sessions"], with: "9")
        cod.toolbars.buttons["Done"].tap()
        XCTAssertTrue(cod.buttons["float-tool"].isEnabled)
        capture("Pomodoro - directly typed focus break and session values")
        replace(cod.textFields["pomodoro-focus"], with: "0")
        XCTAssertFalse(cod.buttons["float-tool"].isEnabled)
        cod.toolbars.buttons["Done"].tap()
        reveal(cod.staticTexts["pomodoro-validation"])
        replace(cod.textFields["pomodoro-focus"], with: "30")
        cod.toolbars.buttons["Done"].tap()
        XCTAssertTrue(cod.buttons["float-tool"].isEnabled)
    }

    func testPlainTextPreviewsRoundTheImageAndNotTheLetterbox() {
        openTools()
        XCTAssertTrue(cod.buttons["Paste Image from Clipboard"].exists)
        let entry = cod.buttons["tool-text"]
        reveal(entry); entry.tap()
        let clear = cod.buttons["clear-text"]
        reveal(clear); if clear.isEnabled { clear.tap() }
        capture("Plain text - rounded sample preview")
        let editor = cod.textViews["floating-text-editor"]
        editor.tap(); editor.typeText("A short reference")
        cod.toolbars.buttons["Done"].tap()
        capture("Plain text - rounded short wide preview")
        clear.tap(); editor.tap()
        editor.typeText(String(repeating: "A useful reference line.\n", count: 6))
        cod.toolbars.buttons["Done"].tap()
        XCTAssertTrue(cod.buttons["float-text"].isEnabled)
        capture("Plain text - rounded taller preview")
    }

    func testTimerAlarmCloseWordingIsClear() {
        openTools()
        let entry = cod.buttons["tool-countdown"]
        reveal(entry); entry.tap()
        let toggle = cod.switches["timer-keep-running"]
        reveal(toggle)
        XCTAssertTrue(toggle.label.contains("Keep alarm running when PiP closes"))
        capture("Timer - alarm close wording")
    }

    func testClockLineTogglesSizesAndPersistence() {
        openTools()
        let entry = cod.buttons["tool-clock"]
        reveal(entry); entry.tap()
        func set(_ id: String, _ value: Bool) {
            let toggle = cod.switches[id]
            reveal(toggle)
            if (toggle.value as? String == "1") != value {
                toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
            }
        }
        set("clock-show-location", true)
        set("clock-show-zone", true)
        set("clock-show-date", true)
        for title in ["Location text size", "Time text size", "Date text size"] {
            let slider = cod.sliders[title]
            reveal(slider); slider.adjust(toNormalizedSliderPosition: 0.65)
        }
        XCTAssertTrue(cod.staticTexts["floating-preview-label"].isHittable)
        capture("Current Time - location abbreviation date and independent sizes")
        cod.collectionViews["float-settings"].swipeDown()
        cod.collectionViews["float-settings"].swipeDown()
        set("clock-show-location", false)
        XCTAssertFalse(cod.switches["clock-show-zone"].exists)
        set("clock-show-date", false)
        capture("Current Time - time only")
        cod.terminate(); cod.launch(); openTools(); reveal(entry); entry.tap()
        reveal(cod.switches["clock-show-location"])
        XCTAssertEqual(cod.switches["clock-show-location"].value as? String, "0")
        XCTAssertEqual(cod.switches["clock-show-date"].value as? String, "0")
        set("clock-show-location", true); set("clock-show-date", true)
    }

    func testPDFPageCanBeTypedAndInvalidPagesCannotFloat() {
        let lab = XCUIApplication()
        lab.launch(); lab.buttons["Open Test PDF In"].tap(); selectCod(in: lab)
        let page = cod.textFields["pdf-page-number"]
        XCTAssertTrue(page.waitForExistence(timeout: 10), cod.debugDescription)
        func replace(_ input: String) {
            reveal(page); page.tap()
            page.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (page.value as? String ?? "").count) + input)
            cod.toolbars.buttons["Done"].tap()
        }
        replace("2")
        XCTAssertEqual(page.value as? String, "2")
        XCTAssertEqual(cod.textFields["pdf-page-number"].value as? String, "2")
        XCTAssertTrue(cod.buttons["float-pdf-page"].isEnabled)
        capture("PDF - directly entered page two")
        replace("9")
        XCTAssertTrue(cod.staticTexts["pdf-page-validation"].exists)
        XCTAssertFalse(cod.buttons["float-pdf-page"].exists && cod.buttons["float-pdf-page"].isEnabled)
        replace("1")
        XCTAssertTrue(cod.buttons["float-pdf-page"].isEnabled)
        capture("PDF - invalid page corrected")
    }

    func testFinitePrompterCountdownAndRealNativeRewind() {
        openTextEditor(prompter: true)
        let clear = cod.buttons["clear-text"]
        reveal(clear); if clear.isEnabled { clear.tap() }
        let countdown = cod.switches["prompter-countdown"]
        reveal(countdown)
        if countdown.value as? String != "1" { countdown.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        let delay = cod.steppers["prompter-delay"]
        XCTAssertTrue(delay.exists)
        XCTAssertTrue(delay.label.contains("3 seconds"), "Fresh countdown defaults to three seconds")
        delay.buttons["prompter-delay-Increment"].tap()
        XCTAssertTrue(delay.label.contains("4 seconds"))
        delay.buttons["prompter-delay-Decrement"].tap()
        capture("Teleprompter - three-second countdown and finite duration")
        cod.buttons["float-tool"].tap()
        reveal(cod.buttons["prompter-rewind"])
        XCTAssertTrue(cod.buttons["prompter-rewind"].waitForExistence(timeout: 5))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let pipWindow = system.windows["PIP-SBInteractionPassThroughView"]
        XCTAssertTrue(pipWindow.waitForExistence(timeout: 10), "A real native PiP window must be running")
        capture("Teleprompter - native playing before seeking")
        let position = cod.sliders["Script position"]
        reveal(position); position.adjust(toNormalizedSliderPosition: 0.5)
        let pause = cod.buttons["tool-play-pause"]
        if pause.label == "Pause" { pause.tap() }
        pipWindow.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        capture("Teleprompter - finite PiP and playback position")
        let before = Int(cod.staticTexts["prompter-position"].value as? String ?? "-100") ?? -100
        // The simulator renders these standard AVKit buttons but omits them
        // from SpringBoard's accessibility tree. Use the observed native
        // window-relative back-button position, never an application hook.
        pipWindow.coordinate(withNormalizedOffset: .init(dx: 0.265, dy: 0.5)).tap()
        let after = Int(cod.staticTexts["prompter-position"].value as? String ?? "-100") ?? -100
        XCTAssertGreaterThan(before, 10)
        XCTAssertEqual(before - after, 10, "The native ten-second rewind must seek the actual script")
        pipWindow.coordinate(withNormalizedOffset: .init(dx: 0.08, dy: 0.75)).tap()
        capture("Teleprompter - rewind changes real script position")
        let stop = cod.buttons["Stop Floating"]
        if stop.exists { stop.tap() }
    }

    func testTimeZoneSearchIsVisibleWithoutScrollingAndSelectsTheResult() {
        openTools()
        let clock = cod.buttons["tool-clock"]
        reveal(clock); clock.tap()
        let zone = cod.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Time zone,'")).firstMatch
        reveal(zone); zone.tap()
        let search = cod.searchFields["Search time zones"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable, "Search must be visible on entry without pulling the list down")
        capture("Time zones - immediately visible search")
        search.tap(); search.typeText("Tokyo")
        let tokyo = cod.buttons["Asia/Tokyo"]
        XCTAssertTrue(tokyo.waitForExistence(timeout: 5)); tokyo.tap()
        XCTAssertTrue(cod.buttons.matching(NSPredicate(format: "label CONTAINS 'Time zone, Asia/Tokyo'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testClockPreviewTicksAndSizesCanBeResetWithoutChangingAppearance() {
        openTools()
        let clock = cod.buttons["tool-clock"]
        reveal(clock); clock.tap()
        let preview = cod.images["Tool preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let initial = preview.value as? String
        XCTAssertFalse(initial?.isEmpty ?? true)
        let ticked = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (preview.value as? String) != initial
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ticked], timeout: 4), .completed, "The preview must tick without changing a setting")
        let reset = cod.buttons["clock-reset-sizes"]
        let size = cod.sliders["Time text size"]
        reveal(size)
        if reset.exists { reveal(reset); reset.tap() }
        reveal(size); size.adjust(toNormalizedSliderPosition: 0.9)
        reveal(reset); XCTAssertTrue(reset.isHittable)
        capture("Current Time - live preview and conditional reset sizes")
        reset.tap()
        XCTAssertFalse(reset.exists)
        cod.terminate(); cod.launch(); openTools(); reveal(clock); clock.tap()
        reveal(cod.sliders["Time text size"])
        XCTAssertFalse(reset.exists, "Reset sizes must be remembered")
    }

    func testSystemAppearanceIsTheDefaultAndFixedPresetsRemainAvailable() {
        cod.terminate()
        cod.launchArguments = ["--dark-ui-test"]
        cod.launch(); openTools()
        let text = cod.buttons["tool-text"]
        reveal(text); text.tap()
        let preset = cod.buttons["floating-preset"]
        reveal(preset)
        XCTAssertTrue(preset.label.contains("System"), preset.label)
        capture("System preset - dark device appearance")
        preset.tap(); cod.buttons["Light"].tap()
        XCTAssertTrue(preset.label.contains("Light"))
        capture("Light preset overrides dark device appearance")
        preset.tap(); cod.buttons["Yellow"].tap()
        XCTAssertTrue(preset.label.contains("Yellow"))
        preset.tap(); cod.buttons["System"].tap()
        XCTAssertTrue(preset.label.contains("System"))
    }
    private func setManualShare() {
        cod.tabBars.buttons["Settings"].tap()
        let toggle = cod.switches["One tap float"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let notifications = cod.switches["Tap notification to float"]
        if notifications.exists, notifications.value as? String == "1" { notifications.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        cod.tabBars.buttons["Float"].tap()
        XCTAssertTrue(cod.buttons["choose-photo"].waitForExistence(timeout: 5))
    }
    func testSavedEditableTextCardPersistsAndCanBeUpdated() {
        openTextEditor(prompter: false)
        let editor = cod.textViews["floating-text-editor"]
        let clear = cod.buttons["clear-text"]; reveal(clear); if clear.isEnabled { clear.tap() }
        reveal(editor, towardTop: true); editor.tap()
        editor.typeText("Saved reference: Gate 7 at 14:30")
        cod.toolbars.buttons["Done"].tap()
        let name = "UI Card \(UUID().uuidString.prefix(8))"
        let nameField = cod.textFields["reference-name"]; reveal(nameField); nameField.tap(); nameField.typeText(name)
        let save = cod.buttons["save-reference"]; reveal(save); save.tap()
        XCTAssertTrue(cod.staticTexts["Saved in Library → Saved cards & presets."].waitForExistence(timeout: 5))
        cod.navigationBars.buttons.element(boundBy: 0).tap()
        tapMainTab("Library"); cod.buttons["saved-references"].tap()
        let row = cod.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(cod.textViews["floating-text-editor"].waitForExistence(timeout: 5))
        XCTAssertEqual(cod.textViews["floating-text-editor"].value as? String, "Saved reference: Gate 7 at 14:30")
        let reopened = cod.textViews["floating-text-editor"]
        reveal(clear); if clear.isEnabled { clear.tap() }
        reveal(reopened, towardTop: true); reopened.tap()
        reopened.typeText("Updated reference: Gate 9")
        cod.toolbars.buttons["Done"].tap()
        reveal(save); XCTAssertEqual(save.label, "Update Saved Reference"); save.tap()
        capture("Saved editable text card")
        cod.terminate(); cod.launch(); tapMainTab("Library"); cod.buttons["saved-references"].tap()
        XCTAssertTrue(cod.staticTexts[name].waitForExistence(timeout: 5))
        cod.staticTexts[name].tap()
        XCTAssertEqual(cod.textViews["floating-text-editor"].value as? String, "Updated reference: Gate 9")
    }

    func testPrompterGuideLayoutAndTargetDurationCanBeSaved() {
        openTextEditor(prompter: true)
        let guide = cod.switches["prompter-reading-guide"]; reveal(guide); XCTAssertTrue(guide.waitForExistence(timeout: 5))
        if guide.value as? String != "1" { guide.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        let timed = cod.switches["prompter-timed-reading"]; reveal(timed)
        timed.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(timed.value as? String, "1", cod.debugDescription)
        let minutes = cod.descendants(matching: .any).matching(identifier: "timer-minutes").firstMatch
        reveal(minutes)
        XCTAssertTrue(cod.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(cod.buttons["float-tool"].isHittable)
        capture("Prompter reading guide and target duration")
        let field = cod.textFields["reference-name"]; reveal(field); field.tap(); field.typeText("UI Timed Script \(UUID().uuidString.prefix(6))")
        let save = cod.buttons["save-reference"]; reveal(save); save.tap()
        XCTAssertTrue(cod.staticTexts["Saved in Library → Saved cards & presets."].waitForExistence(timeout: 5))
    }

    func testPDFPageRangeCreatesScrollableFinitePlayback() {
        let lab = XCUIApplication(); lab.launch(); lab.buttons["Open Test PDF In"].tap(); selectCod(in: lab)
        let scroll = cod.switches["auto-scroll-pdf"]; XCTAssertTrue(scroll.waitForExistence(timeout: 8)); reveal(scroll)
        if scroll.value as? String != "1" { scroll.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertFalse(cod.buttons["crop-pdf-region"].exists)
        XCTAssertFalse(cod.textFields["pdf-page-number"].exists)
        let last = cod.textFields["scroll-last-page"]; XCTAssertTrue(last.waitForExistence(timeout: 5))
        // Scoped UIKit focus handling selects the current page number.
        last.coordinate(withNormalizedOffset: .init(dx: 0.98, dy: 0.5)).tap()
        last.typeText("2")
        XCTAssertEqual(last.value as? String, "2", cod.debugDescription)
        let done = cod.toolbars.buttons["Done"]
        if done.exists && done.isHittable { done.tap() }
        XCTAssertFalse(cod.buttons["prepare-scrolling-pdf"].exists)
        let float = cod.buttons["float-scrolling-reference"]
        XCTAssertTrue(float.waitForExistence(timeout: 8), cod.debugDescription)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: float)
        waitForExpectations(timeout: 12)
        XCTAssertTrue(float.isHittable)
        capture("Scrolling PDF page range preview")
        float.tap()
        let rewind = cod.buttons["prompter-rewind"]; reveal(rewind)
        XCTAssertTrue(rewind.waitForExistence(timeout: 10))
        capture("Scrolling PDF finite playback controls")
    }

    func testGIFPhotosPickerPreservesMotionAndHandlesPiPAvailability() {
        // Seeded with the harness's red/blue GIF via simctl addmedia. This tests
        // the real Photos route; Open In may offer the Share extension instead.
        cod.buttons["choose-photo"].tap()
        let chooser = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        let predicate = NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Animated' OR label BEGINSWITH 'GIF'")
        let candidates = [cod, chooser]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in candidates.contains { $0.images.matching(predicate).firstMatch.exists } }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, cod.debugDescription + chooser.debugDescription)
        let asset = candidates.first(where: { $0.images.matching(predicate).firstMatch.exists })?.images.matching(predicate).firstMatch
        XCTAssertNotNil(asset); asset?.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let float = cod.buttons["float-video"]
        XCTAssertTrue(float.waitForExistence(timeout: 15), cod.debugDescription)
        XCTAssertTrue(cod.switches["video-repeat"].exists)
        capture("Animated GIF imported as video")
        float.tap()
        let unavailable = cod.staticTexts["Picture in Picture isn't available on this device."]
        if unavailable.waitForExistence(timeout: 2) {
            capture("GIF import retained; native PiP unsupported by this simulator")
            XCTAssertTrue(float.isEnabled)
            return
        }
        let stop = cod.buttons["stop-video-float"]
        XCTAssertTrue(stop.waitForExistence(timeout: 35), cod.debugDescription)
        capture("Animated GIF native PiP")
        stop.tap()
    }

    func testVideoRegionCropKeepsTheOriginalAndUpdatesThePreview() {
        let lab = XCUIApplication(); lab.launch(); lab.buttons["Open Test Video In"].tap(); selectCod(in: lab)
        let crop = cod.buttons["crop-video-region"]; XCTAssertTrue(crop.waitForExistence(timeout: 10)); reveal(crop); crop.tap()
        let canvas = cod.descendants(matching: .any).matching(identifier: "crop-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.45)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: .init(dx: 0.7, dy: 0.55)))
        capture("Video region selection")
        cod.buttons["Apply Crop"].tap()
        let reset = cod.buttons["Reset to Original Video"]
        XCTAssertTrue(reset.waitForExistence(timeout: 30), cod.debugDescription)
        XCTAssertTrue(cod.buttons["float-video"].isEnabled)
        capture("Cropped video ready to float")
        reset.tap()
        XCTAssertFalse(reset.exists)
    }

    func testSavedReferenceControlCanSelectAndLaunchItsCard() {
        openTextEditor(prompter: false)
        let clear = cod.buttons["clear-text"]; reveal(clear); if clear.isEnabled { clear.tap() }
        let name = "Control Card \(UUID().uuidString.prefix(6))"
        let field = cod.textFields["reference-name"]; reveal(field); field.tap(); field.typeText(name)
        let save = cod.buttons["save-reference"]; reveal(save); save.tap()
        XCTAssertTrue(cod.staticTexts["Saved in Library → Saved cards & presets."].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func openCenter() {
            system.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.01)).press(forDuration: 0.1, thenDragTo: system.coordinate(withNormalizedOffset: .init(dx: 0.8, dy: 0.65)))
        }
        openCenter()
        let edit = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Controls'")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let gallery = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add a Control'")).firstMatch
        XCTAssertTrue(gallery.waitForExistence(timeout: 5)); gallery.tap()
        let search = system.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Cod")
        let item = system.descendants(matching: .any).matching(NSPredicate(format: "label == 'Float Saved Reference'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 8)); item.tap()
        let tile = system.icons.matching(identifier: "Float Saved Reference").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), system.debugDescription)
        tile.tap()
        let unconfigured = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Choose a reference'")).firstMatch
        if unconfigured.waitForExistence(timeout: 3) { unconfigured.tap() }
        let referenceRow = system.cells.containing(.staticText, identifier: "Reference").firstMatch
        let referenceChoice = referenceRow.buttons.firstMatch
        XCTAssertTrue(referenceChoice.waitForExistence(timeout: 5), system.debugDescription)
        referenceChoice.tap()
        let selection = system.staticTexts[name]
        XCTAssertTrue(selection.waitForExistence(timeout: 8), system.debugDescription); selection.tap()
        capture("Saved card selected in native control configuration")
        // Close the configuration popover before leaving Control Center's edit mode.
        system.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.8)).tap()
        let editing = system.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add a Control'")).firstMatch
        if editing.exists {
            system.otherElements["cc-root-folder-view"].coordinate(withNormalizedOffset: .init(dx: 0.85, dy: 0.75)).tap()
        }
        XCUIDevice.shared.press(.home); openCenter()
        let control = system.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 8), system.debugDescription); control.tap()
        XCTAssertTrue(cod.wait(for: .runningForeground, timeout: 10), "The saved control must open Cod through OpenIntent")
        // Receipt lives on the Float list. A warm intent doesn't discard the
        // editor that was open before it ran (especially when PiP is unavailable).
        let close = cod.buttons["Close"]
        if close.exists && close.isHittable { close.tap() }
        let receipt = cod.staticTexts["received-image-size"]
        // The lazy Float list may retain its pre-editor scroll offset.
        for _ in 0..<3 where !receipt.exists { cod.swipeDown() }
        XCTAssertTrue(receipt.waitForExistence(timeout: 8), cod.debugDescription)
        XCTAssertTrue(receipt.label.contains("900x"))
        capture("Saved reference control delivered the selected card")
    }

    func testUnifiedTextModesPreserveTheSameEditableSource() {
        openTextEditor(prompter: false)
        let clear = cod.buttons["clear-text"]; reveal(clear); if clear.isEnabled { clear.tap() }
        let editor = cod.textViews["floating-text-editor"]; reveal(editor); editor.tap()
        let content = "One shared reference, kept when switching modes."
        editor.typeText(content); cod.toolbars.buttons["Done"].tap()
        let toggle = cod.switches["text-teleprompter"]
        reveal(toggle, towardTop: true); toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(cod.buttons["float-tool"].isEnabled)
        reveal(editor); XCTAssertEqual(editor.value as? String, content)
        let mode = cod.segmentedControls["prompter-mode"]; reveal(mode); mode.buttons["Words"].tap()
        reveal(cod.steppers["prompter-word-count"])
        XCTAssertTrue(cod.steppers["prompter-word-count"].exists)
        reveal(toggle, towardTop: true); toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(cod.buttons["float-text"].isEnabled)
        reveal(editor); XCTAssertEqual(editor.value as? String, content)
        XCTAssertFalse(cod.segmentedControls["prompter-mode"].exists)
        reveal(toggle, towardTop: true); toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        reveal(mode); XCTAssertTrue(mode.buttons["Words"].isSelected)
        capture("One text editor, optional teleprompter, source retained")
    }

    func testPDFScrollingToggleReplacesSinglePageControlsWithoutNavigation() {
        let lab = XCUIApplication(); lab.launch(); lab.buttons["Open Test PDF In"].tap(); selectCod(in: lab)
        let page = cod.textFields["pdf-page-number"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        let stepper = cod.steppers["pdf-page"]
        XCTAssertLessThan(abs(page.frame.midY - stepper.frame.midY), 5, "Page entry and stepper must share one row")
        XCTAssertFalse(cod.staticTexts["Go to page"].exists)
        let toggle = cod.switches["auto-scroll-pdf"]; reveal(toggle)
        toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(cod.textFields["scroll-first-page"].waitForExistence(timeout: 5))
        XCTAssertFalse(page.exists)
        XCTAssertFalse(stepper.exists)
        XCTAssertFalse(cod.buttons["crop-pdf-region"].exists)
        XCTAssertFalse(cod.buttons["prepare-scrolling-pdf"].exists)
        let float = cod.buttons["float-scrolling-reference"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: float)
        waitForExpectations(timeout: 10)
        capture("Inline PDF auto-scroll settings")
        reveal(toggle); toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.value as? String, "1")
        XCTAssertTrue(cod.buttons["crop-pdf-region"].exists)
        XCTAssertFalse(cod.textFields["scroll-first-page"].exists)
        capture("Single PDF page row with crop restored")
    }

    func testPhotoImportAndOriginalScrollingAreInsideText() {
        openTextEditor(prompter: false)
        let clear = cod.buttons["clear-text"]; reveal(clear); if clear.isEnabled { clear.tap() }
        let photo = cod.buttons["read-photo-text"]; reveal(photo); photo.tap()
        let chooser = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        let predicate = NSPredicate(format: "label BEGINSWITH 'Photo,' OR label BEGINSWITH 'Animated' OR label BEGINSWITH 'GIF'")
        let surfaces = [cod, chooser]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in surfaces.contains { $0.images.matching(predicate).firstMatch.exists } }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        let image = surfaces.compactMap { $0.images.matching(predicate).allElementsBoundByIndex.first }.first
        XCTAssertNotNil(image); image?.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        if cod.buttons["Replace"].waitForExistence(timeout: 2) { cod.buttons["Replace"].tap() }
        let toggle = cod.switches["text-teleprompter"]
        reveal(toggle, towardTop: true)
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), cod.debugDescription)
        toggle.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        let layout = cod.switches["text-image-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 15)); reveal(layout)
        layout.coordinate(withNormalizedOffset: .init(dx: 0.93, dy: 0.5)).tap()
        let float = cod.buttons["float-scrolling-reference"]
        XCTAssertTrue(float.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: float)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(cod.segmentedControls["prompter-mode"].exists)
        capture("Photo import and original-layout scrolling in Text")
    }

    private func selectCod(in lab: XCUIApplication) {
        let cell = lab.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Cod Test'")).firstMatch
        if !cell.waitForExistence(timeout: 5), lab.cells["More"].exists { lab.cells["More"].tap() }
        XCTAssertTrue(cell.waitForExistence(timeout: 8), lab.debugDescription)
        cell.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
