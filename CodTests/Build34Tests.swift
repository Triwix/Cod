import XCTest
import UIKit
@testable import Cod

/// Build 34 audit fixes: the Pro screen's plan choice and trial wording, and
/// Pro for text shared from the Share sheet.
@MainActor
final class Build34Tests: XCTestCase {
  // MARK: A1 plan selection

  func testSubscribersAreOnlyOfferedLifetimeAndTheButtonActsOnIt() {
    let loaded = Set(ProPlan.allCases)
    let subscriber = ProPlan.offered(loaded: loaded, hasActiveSubscription: true)
    XCTAssertEqual(subscriber, [.lifetime])
    XCTAssertEqual(ProPlan.selection(chosen: nil, offered: subscriber), .lifetime,
                   "Upgrade to Lifetime starts on Lifetime, not Yearly")
    XCTAssertEqual(ProPlan.selection(chosen: .yearly, offered: subscriber), .lifetime,
                   "A plan that isn't shown is never bought")
  }

  func testFreeUsersStartOnYearlyAndKeepTheirChoice() {
    let offered = ProPlan.offered(loaded: Set(ProPlan.allCases), hasActiveSubscription: false)
    XCTAssertEqual(offered, [.yearly, .monthly, .lifetime])
    XCTAssertEqual(ProPlan.selection(chosen: nil, offered: offered), .yearly)
    XCTAssertEqual(ProPlan.selection(chosen: .monthly, offered: offered), .monthly)
    let partial = ProPlan.offered(loaded: [.monthly, .lifetime], hasActiveSubscription: false)
    XCTAssertEqual(ProPlan.selection(chosen: nil, offered: partial), .monthly, "Only loaded plans")
    XCTAssertNil(ProPlan.selection(chosen: .yearly, offered: []))
  }

  // MARK: A6 trial length

  func testTrialWordingFollowsTheOfferPeriod() {
    XCTAssertEqual(TrialLength(value: 1, unit: .week).phrase, "7 days")
    XCTAssertEqual(TrialLength(value: 1, unit: .week).title, "7-Day")
    XCTAssertEqual(TrialLength(value: 2, unit: .week).phrase, "14 days")
    XCTAssertEqual(TrialLength(value: 3, unit: .day).title, "3-Day")
    XCTAssertEqual(TrialLength(value: 1, unit: .month).phrase, "1 month")
    XCTAssertEqual(TrialLength(value: 1, unit: .month).title, "1-Month")
    XCTAssertEqual(TrialLength(value: 1, unit: .year).phrase, "1 year")
  }

  // MARK: A2 shared text

  func testSharedTextIsMarkedAndOlderRecordsReadAsImages() throws {
    let (handoff, directory) = try makeHandoff()
    defer { try? FileManager.default.removeItem(at: directory) }
    try handoff.store(Self.image, mode: .float, isText: true)
    XCTAssertEqual(try handoff.claim()?.isText, true)
    try handoff.store(Self.image, mode: .crop)
    XCTAssertEqual(try handoff.claim()?.isText, false, "No flag means an image")
  }

  func testFreeTierAsksForProBeforeFloatingSharedText() throws {
    let (handoff, directory) = try makeHandoff()
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "Build34-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let coordinator = CaptureCoordinator(
      store: .shared, settings: AppSettings(defaults: defaults), pip: PiPPinController(),
      pro: ProStore(defaults: defaults), quickHandoff: handoff)

    let text = try handoff.store(Self.image, mode: .crop, isText: true)
    XCTAssertTrue(coordinator.receiveQuickShare(expectedID: text))
    XCTAssertEqual(coordinator.proPrompt?.feature, .textCards)
    XCTAssertNil(coordinator.pending, "Cropping shared text would float it as an image")
    XCTAssertFalse(coordinator.isWorking)

    coordinator.proPrompt = nil
    let image = try handoff.store(Self.image, mode: .crop)
    XCTAssertTrue(coordinator.receiveQuickShare(expectedID: image))
    XCTAssertNil(coordinator.proPrompt, "Shared images stay free")
    XCTAssertNotNil(coordinator.pending)
  }

  // MARK: Helpers

  private func makeHandoff() throws -> (QuickFloatHandoff, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Build34-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (QuickFloatHandoff(container: { directory }), directory)
  }

  private static let image: UIImage = {
    UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24)).image { context in
      UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
    }
  }()
}
