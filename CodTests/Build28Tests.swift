import XCTest
@testable import Cod

/// Build 28: bundled crop Shortcut, iPhone-only 1.0, Translate on by default.
final class Build28Tests: XCTestCase {
    func testTranslateIsVisibleInTheActionBarForNewInstalls() {
        let suite = "Cod.Build28.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, sharePreferences: FixedSharePreferences())
        XCTAssertTrue(settings.enabledActions.contains(.translate))
        XCTAssertTrue(settings.visibleActions.contains(.translate))
        // Annotate stays opt-in; only Translate changed.
        XCTAssertFalse(settings.visibleActions.contains(.annotate))
    }

    func testSavedActionChoicesAreNotOverriddenByTheNewDefault() throws {
        let suite = "Cod.Build28.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AppSettings(defaults: defaults, sharePreferences: FixedSharePreferences())
        first.enabledActions.remove(.translate)
        let reloaded = AppSettings(defaults: defaults, sharePreferences: FixedSharePreferences())
        XCTAssertFalse(reloaded.enabledActions.contains(.translate))
    }

    func testCropShortcutIsBundledAndSigned() throws {
        XCTAssertTrue(FloatShortcut.allCases.contains(.screenshotCrop))
        let url = try XCTUnwrap(FloatShortcut.screenshotCrop.fileURL)
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "Screenshot and Crop with Cod")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(4), Data("AEA1".utf8), "Signed Shortcuts are Apple Encrypted Archives")
    }

    func testAppShipsForIPhoneOnly() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int], [1])
    }
}

private final class FixedSharePreferences: ShareFloatPreferenceStore {
    var oneTapFloat = true
    var useFloatNotification = false
    func setOneTapFloat(_ enabled: Bool) -> Bool { oneTapFloat = enabled; return true }
    func setUseFloatNotification(_ enabled: Bool) -> Bool { useFloatNotification = enabled; return true }
}
