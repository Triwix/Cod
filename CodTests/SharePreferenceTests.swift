import Security
import XCTest
@testable import Cod

final class SharePreferenceTests: XCTestCase {
    func testNativeFloatingControlsDefaultAndExplicitPreferencePersistence() {
        let suite = "Cod.FloatingControlsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorySharePreferenceStore()
        let settings = AppSettings(defaults: defaults, sharePreferences: store)
        XCTAssertFalse(settings.hideFloatingControls)
        settings.hideFloatingControls = true
        #if COD_PERSONAL
        XCTAssertTrue(AppSettings(defaults: defaults, sharePreferences: store).hideFloatingControls)
        #else
        XCTAssertFalse(AppSettings(defaults: defaults, sharePreferences: store).hideFloatingControls)
        XCTAssertFalse(AppSettings(defaults: defaults, sharePreferences: store).returnAfterFloating)
        #endif
        settings.hideFloatingControls = false
        XCTAssertFalse(AppSettings(defaults: defaults, sharePreferences: store).hideFloatingControls)
    }

    func testMissingOrMalformedPreferenceDefaultsToCrop() {
        for data in [nil, Data(), Data([0]), Data([2]), Data([1, 0])] {
            XCTAssertFalse(SharePreferences.decode(data))
        }
        XCTAssertTrue(SharePreferences.decode(Data([1])))
    }

    func testSettingDefaultsOffAndPersistsBothDirections() {
        let store = MemorySharePreferenceStore()
        let defaults = UserDefaults(suiteName: "Cod.SharePreferenceTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults, sharePreferences: store)
        XCTAssertFalse(settings.oneTapFloat)
        settings.setOneTapFloat(true)
        XCTAssertTrue(store.oneTapFloat)
        XCTAssertTrue(AppSettings(defaults: defaults, sharePreferences: store).oneTapFloat)
        settings.setOneTapFloat(false)
        XCTAssertFalse(AppSettings(defaults: defaults, sharePreferences: store).oneTapFloat)
    }

    func testFailedWriteRollsBackTheSwitchAndShowsAnError() {
        let store = MemorySharePreferenceStore()
        store.allowWrites = false
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "Cod.SharePreferenceTests.\(UUID().uuidString)")!,
            sharePreferences: store
        )
        settings.setOneTapFloat(true)
        XCTAssertFalse(settings.oneTapFloat)
        XCTAssertFalse(store.oneTapFloat)
        XCTAssertNotNil(settings.sharePreferenceError)
        store.allowWrites = true
        settings.setOneTapFloat(true)
        XCTAssertTrue(settings.oneTapFloat)
        XCTAssertNil(settings.sharePreferenceError)
    }

    func testSharedKeychainPreferenceRoundTripBetweenSeparateReaders() {
        let group = Bundle.main.object(forInfoDictionaryKey: "CodShareSettingsAccessGroup") as? String
        XCTAssertNotNil(group)
        let service = "com.josh.cod.share-preferences.tests.\(UUID().uuidString)"
        let account = "oneTapFloat"
        var cleanup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        if let group { cleanup[kSecAttrAccessGroup as String] = group }
        defer { SecItemDelete(cleanup as CFDictionary) } // This test's unique item only.
        let writer = SharePreferences(accessGroup: group, service: service, account: account)
        let reader = SharePreferences(accessGroup: group, service: service, account: account)
        #if COD_PERSONAL
        XCTAssertFalse(reader.oneTapFloat)
        XCTAssertEqual(SharePreferences.defaultAccount, "oneTapFloat")
        #else
        XCTAssertTrue(reader.oneTapFloat, "The public fast-flow build defaults to whole-image Float")
        XCTAssertEqual(SharePreferences.defaultAccount, "quickFloatWholeImage")
        #endif
        XCTAssertTrue(writer.setOneTapFloat(true))
        XCTAssertTrue(reader.oneTapFloat)
        XCTAssertTrue(writer.setOneTapFloat(false))
        XCTAssertFalse(reader.oneTapFloat)
    }
}

private final class MemorySharePreferenceStore: ShareFloatPreferenceStore {
    var oneTapFloat = false
    var allowWrites = true
    func setOneTapFloat(_ enabled: Bool) -> Bool {
        guard allowWrites else { return false }
        oneTapFloat = enabled
        return true
    }
}
