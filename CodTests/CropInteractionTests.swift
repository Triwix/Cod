import XCTest
@testable import Cod

final class CropInteractionTests: XCTestCase {
    func testResizeCollapsingOnTheOppositeCornerRecoversThePreviousCrop() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let original = CGRect(x: 40, y: 30, width: 180, height: 120)
        let collapsed = SelectionHandle.topLeft.resized(original, dx: original.width, dy: original.height)
        XCTAssertTrue(collapsed.isEmpty)
        XCTAssertEqual(CropSelectionPolicy.resolvedSelection(collapsed, previous: original, in: bounds), original)
        let legacyBlock = CGRect(x: 40, y: 30, width: 3, height: 2)
        XCTAssertEqual(CropSelectionPolicy.resolvedSelection(.zero, previous: legacyBlock, in: bounds), legacyBlock)
    }

    func testInvalidCompletionOrCancellationNeverLeavesAnUnusableCrop() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let original = CGRect(x: 40, y: 30, width: 180, height: 120)
        let invalid: [CGRect?] = [nil, .null, .zero, CGRect(x: 10, y: 10, width: 1, height: 2),
                                 CGRect(x: CGFloat.infinity, y: 0, width: 50, height: 50)]
        for crop in invalid {
            XCTAssertEqual(CropSelectionPolicy.resolvedSelection(crop, previous: original, in: bounds), original)
            XCTAssertNil(CropSelectionPolicy.resolvedSelection(crop, previous: nil, in: bounds))
        }
    }

    func testMovingAValidCropOutsideTheViewportDoesNotInvalidateIt() {
        let geometry = SelectionGeometry.fit(imageSize: CGSize(width: 1200, height: 2400),
                                             in: CGSize(width: 390, height: 844), zoom: 4)
        let moved = CGRect(x: 1100, y: 2200, width: 80, height: 100)
        let visible = geometry.viewRect(moved).intersection(CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertTrue(visible.isNull || visible.isEmpty)
        XCTAssertEqual(CropSelectionPolicy.resolvedSelection(moved, previous: nil, in: geometry.imageBounds), moved)
    }

    func testHiddenFloatDisablesItsGestureAfterRelaunchButExplicitShareActionsStillWork() {
        let suite = "Cod.CropGesture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CropTestPreferences()
        let settings = AppSettings(defaults: defaults, sharePreferences: preferences)
        settings.enabledActions.remove(.float)
        let reloaded = AppSettings(defaults: defaults, sharePreferences: preferences)
        XCTAssertFalse(CropInteractionPolicy.allowsDoubleTapFloat(actions: reloaded.visibleActions, primaryTitle: nil))
        XCTAssertTrue(CropInteractionPolicy.allowsDoubleTapFloat(actions: [.float], primaryTitle: nil),
                      "The Share extension supplies its own explicit supported actions")
        reloaded.enabledActions.insert(.float)
        XCTAssertTrue(CropInteractionPolicy.allowsDoubleTapFloat(actions: reloaded.visibleActions, primaryTitle: nil))
        XCTAssertFalse(CropInteractionPolicy.allowsDoubleTapFloat(actions: [.float], primaryTitle: "Apply Crop"))
    }
}

private final class CropTestPreferences: ShareFloatPreferenceStore {
    var oneTapFloat = false
    var useFloatNotification = false
    func setOneTapFloat(_ enabled: Bool) -> Bool { oneTapFloat = enabled; return true }
    func setUseFloatNotification(_ enabled: Bool) -> Bool { useFloatNotification = enabled; return true }
}
