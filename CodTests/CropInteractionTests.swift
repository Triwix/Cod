import XCTest
@testable import Cod

final class CropInteractionTests: XCTestCase {
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
