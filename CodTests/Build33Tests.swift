import XCTest
@testable import Cod

/// Pre-launch audit fixes: OCR follows the device's languages, and System
/// Monitor names its thermal reading honestly.
final class Build33Tests: XCTestCase {
  private let supported = ["en-US", "fr-FR", "it-IT", "de-DE", "es-ES", "pt-BR", "zh-Hans", "zh-Hant",
                           "ja-JP", "ko-KR", "ru-RU", "uk-UA"]

  func testOCRDefaultsFollowTheDevicesLanguages() {
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["en-US"], supported: supported), ["en-US"])
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["fr-CA", "en-CA"], supported: supported),
                   ["fr-FR", "en-US"], "Same language, any region")
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["pt-BR"], supported: supported), ["pt-BR"])
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["zh-TW"], supported: supported), ["zh-Hant"],
                   "Traditional Chinese regions match the Hant script")
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["zh-Hans-US"], supported: supported), ["zh-Hans"])
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["ja-JP", "ja", "ko-KR", "de-DE", "es-ES"],
                                                   supported: supported),
                   ["ja-JP", "ko-KR", "de-DE"], "No duplicates, at most three")
    XCTAssertEqual(AppSettings.defaultOCRLanguages(preferred: ["tlh"], supported: supported), ["en-US"],
                   "Falls back to English")
  }

  func testUnsetOCRLanguagesUseTheDefaultAndChoicesPersist() {
    let suite = "Build33-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    XCTAssertFalse(settings.ocrLanguages.isEmpty)
    settings.ocrLanguages = ["de-DE"]
    XCTAssertEqual(AppSettings(defaults: defaults).ocrLanguages, ["de-DE"])
  }

  func testThermalReadingIsNotCalledATemperature() {
    XCTAssertEqual(SystemMetric.temperature.title, "Thermal State")
    XCTAssertEqual(SystemMetric.temperature.label, "Thermal")
    XCTAssertEqual(SystemMetrics().text(for: .temperature), "Cool")
  }
}
