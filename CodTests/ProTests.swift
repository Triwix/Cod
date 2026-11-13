import StoreKit
import StoreKitTest
import XCTest
@testable import Cod

/// Cod Pro: access rules, the float gate, and purchases against the local
/// StoreKit configuration (StoreKit/CodPro.storekit).
@MainActor
final class ProTests: XCTestCase {
  private var defaults: UserDefaults!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "ProTests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    super.tearDown()
  }

  // MARK: Access rules

  func testAccessResolvesLifetimeOverSubscriptionsAndIgnoresRefunds() {
    let later = Date(timeIntervalSinceNow: 86_400 * 30)
    XCTAssertEqual(ProAccess.resolve([]), .free)
    XCTAssertEqual(ProAccess.resolve([.init(plan: .lifetime, isRevoked: true)]), .free)
    XCTAssertEqual(ProAccess.resolve([
      .init(plan: .monthly, expiresAt: later), .init(plan: .lifetime),
    ]), .lifetime)
    XCTAssertEqual(ProAccess.resolve([.init(plan: .yearly, expiresAt: later, isTrial: true)]),
                   .subscribed(.yearly, expiresAt: later, trial: true))
    let sooner = Date(timeIntervalSinceNow: 86_400)
    XCTAssertEqual(ProAccess.resolve([
      .init(plan: .monthly, expiresAt: sooner), .init(plan: .yearly, expiresAt: later),
    ]), .subscribed(.yearly, expiresAt: later, trial: false))
    XCTAssertFalse(ProAccess.free.isPro)
    XCTAssertTrue(ProAccess.lifetime.isPro)
  }

  func testPlansAndFeaturesMapToProductsAndTools() {
    for plan in ProPlan.allCases { XCTAssertEqual(ProPlan(productID: plan.productID), plan) }
    XCTAssertNil(ProPlan(productID: "cod.other"))
    XCTAssertEqual(ProPlan.yearly.productID, "cod.pro.yearly")
    XCTAssertFalse(ProPlan.lifetime.isSubscription)
    XCTAssertEqual(ProFeature.forTool(.countdown), .tools)
    XCTAssertEqual(ProFeature.forTool(.speedometer), .tools)
    XCTAssertEqual(ProFeature.forTool(.teleprompter), .teleprompter)
    XCTAssertEqual(ProFeature.forTool(.document), .pdf)
    XCTAssertEqual(ProFeature.forTool(.slideshow), .imageSets)
    for feature in ProFeature.allCases {
      XCTAssertFalse(feature.title.isEmpty); XCTAssertFalse(feature.phrase.isEmpty)
    }
  }

  func testLastAccessIsRememberedForTheNextLaunch() async {
    defaults.set("lifetime", forKey: "cod.pro.lastAccess")
    XCTAssertTrue(ProStore(defaults: defaults).access.isPro)
    XCTAssertFalse(ProStore(defaults: UserDefaults(suiteName: "ProTests-empty-\(UUID())")!).access.isPro)
  }

  // MARK: Gate

  func testFreeTierAsksForProInsteadOfFloatingTools() throws {
    let coordinator = makeCoordinator()
    coordinator.floatOnlyLaunch = true
    coordinator.floatTool(FloatingToolSession(configuration: .init(kind: .countdown)))
    XCTAssertEqual(coordinator.proPrompt?.feature, .tools)
    XCTAssertFalse(coordinator.isWorking, "Nothing starts floating")
    XCTAssertFalse(coordinator.floatOnlyLaunch, "The app shows itself so the Pro screen is visible")

    coordinator.proPrompt = nil
    var prompter = FloatingToolConfiguration(kind: .teleprompter)
    prompter.text = "Hello there"
    coordinator.floatTool(FloatingToolSession(configuration: prompter))
    XCTAssertEqual(coordinator.proPrompt?.feature, .teleprompter)

    coordinator.proPrompt = nil
    coordinator.floatTool(FloatingToolSession(configuration: .init(kind: .clock)), feature: .pdf)
    XCTAssertEqual(coordinator.proPrompt?.feature, .pdf, "Callers can name the feature")

    coordinator.proPrompt = nil
    XCTAssertFalse(coordinator.unlocks(.video))
    XCTAssertEqual(coordinator.proPrompt?.feature, .video)
  }

  func testInvalidToolsReportTheProblemBeforeAskingForPro() {
    let coordinator = makeCoordinator()
    var monitor = FloatingToolConfiguration(kind: .system)
    monitor.systemMetrics = []
    coordinator.floatTool(FloatingToolSession(configuration: monitor))
    XCTAssertNil(coordinator.proPrompt)
    XCTAssertNotNil(coordinator.toast)
  }

  // MARK: StoreKit

  func testProductsLoadWithAFreeTrialOnBothSubscriptions() async throws {
    let session = try await makeSession()
    defer { session.clearTransactions() }
    let store = ProStore(defaults: defaults)
    await store.loadProducts()
    XCTAssertEqual(Set(store.products.keys), Set(ProPlan.allCases))
    XCTAssertEqual(store.products[.yearly]?.displayPrice, "$11.99")
    XCTAssertEqual(store.products[.monthly]?.displayPrice, "$1.99")
    XCTAssertEqual(store.products[.lifetime]?.displayPrice, "$19.99")
    for plan in [ProPlan.yearly, .monthly] {
      let offer = try XCTUnwrap(store.products[plan]?.subscription?.introductoryOffer)
      XCTAssertEqual(offer.paymentMode, .freeTrial)
      XCTAssertEqual(offer.period.unit, .week)
      XCTAssertEqual(offer.period.value, 1)
    }
    XCTAssertTrue(store.isTrialEligible)
    XCTAssertFalse(store.access.isPro)
  }

  func testStartingTheTrialUnlocksProAndUsesUpTheTrial() async throws {
    let session = try await makeSession()
    defer { session.clearTransactions() }
    let store = ProStore(defaults: defaults)
    await store.loadProducts()
    _ = try await session.buyProduct(identifier: ProPlan.yearly.productID)
    await store.refresh()
    guard case let .subscribed(plan, expiresAt, trial) = store.access else {
      return XCTFail("Expected a subscription, got \(store.access)")
    }
    XCTAssertEqual(plan, .yearly)
    XCTAssertTrue(trial)
    XCTAssertNotNil(expiresAt)
    XCTAssertTrue(store.hasActiveSubscription)
    XCTAssertFalse(store.isTrialEligible, "One trial per subscription group")
    XCTAssertEqual(defaults.string(forKey: "cod.pro.lastAccess"), "subscribed")

    try session.expireSubscription(productIdentifier: ProPlan.yearly.productID)
    await store.refresh()
    XCTAssertEqual(store.access, .free)
  }

  func testLifetimeUnlocksProAndARefundTakesItAway() async throws {
    let session = try await makeSession()
    defer { session.clearTransactions() }
    let store = ProStore(defaults: defaults)
    let transaction = try await session.buyProduct(identifier: ProPlan.lifetime.productID)
    await store.refresh()
    XCTAssertEqual(store.access, .lifetime)
    XCTAssertFalse(store.hasActiveSubscription)

    try session.refundTransaction(identifier: UInt(transaction.id))
    await store.refresh()
    XCTAssertEqual(store.access, .free)
    XCTAssertEqual(defaults.string(forKey: "cod.pro.lastAccess"), "free")
  }

  // MARK: Helpers

  /// A local StoreKit session, or a skip when this simulator can't run one.
  /// Xcode 27.2 with the iOS 26.3/26.5 simulator runtimes can't reach the
  /// StoreKit test service (SKInternalErrorDomain 3), much like PiP there.
  private func makeSession() async throws -> SKTestSession {
    let session = try SKTestSession(configurationFileNamed: "CodPro")
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
    let probe = try? await Product.products(for: [ProPlan.lifetime.productID])
    if probe?.isEmpty ?? true {
      throw XCTSkip("This simulator can't run local StoreKit tests. Run them on an iPhone or a newer simulator runtime.")
    }
    return session
  }

  private func makeCoordinator() -> CaptureCoordinator {
    CaptureCoordinator(store: .shared, settings: AppSettings(defaults: defaults), pip: PiPPinController(),
                       pro: ProStore(defaults: defaults))
  }
}
