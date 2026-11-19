import Foundation
import StoreKit

/// What Cod Pro unlocks. Setting up and previewing is always free; only
/// floating asks for Pro, and the Pro screen leads with what was tapped.
enum ProFeature: String, Identifiable, CaseIterable {
  case tools, teleprompter, textCards, video, pdf, imageSets, savedCards

  var id: String { rawValue }

  var title: String {
    switch self {
    case .tools: return "Live tools"
    case .teleprompter: return "Teleprompter"
    case .textCards: return "Text cards"
    case .video: return "Videos & GIFs"
    case .pdf: return "PDFs & documents"
    case .imageSets: return "Image sets"
    case .savedCards: return "Saved cards & presets"
    }
  }

  /// "Floating … is part of Cod Pro."
  var phrase: String {
    switch self {
    case .tools: return "live tools"
    case .teleprompter: return "the teleprompter"
    case .textCards: return "text cards"
    case .video: return "videos and GIFs"
    case .pdf: return "PDFs and documents"
    case .imageSets: return "image sets"
    case .savedCards: return "saved cards and presets"
    }
  }

  var detail: String {
    switch self {
    case .tools: return "Timers, clocks, Pomodoro, Countdown To, System Monitor and Speedometer, in any window shape"
    case .teleprompter: return "Scripts that scroll, or step by word or line"
    case .textCards: return "Notes and text read from photos"
    case .video: return "Videos, GIFs and web video links: crop, change speed, repeat a section"
    case .pdf: return "PDFs, Word, PowerPoint, Excel and iWork files: one page, flip pages or auto-scroll"
    case .imageSets: return "Step through several photos"
    case .savedCards: return "One tap from widgets, Control Center and Shortcuts"
    }
  }

  var icon: String {
    switch self {
    case .tools: return "timer"
    case .teleprompter: return "text.alignleft"
    case .textCards: return "note.text"
    case .video: return "film"
    case .pdf: return "doc.richtext"
    case .imageSets: return "photo.stack"
    case .savedCards: return "star.square.on.square"
    }
  }

  static func forTool(_ kind: FloatingToolKind) -> ProFeature {
    switch kind {
    case .teleprompter: return .teleprompter
    case .document: return .pdf
    case .slideshow: return .imageSets
    default: return .tools
    }
  }
}

/// The three ways to buy Pro. The two subscriptions share one group, so
/// people can move between them; Lifetime is a one-time purchase.
enum ProPlan: String, CaseIterable, Identifiable {
  case yearly, monthly, lifetime

  var id: String { rawValue }
  var productID: String { "cod.pro.\(rawValue)" }
  var isSubscription: Bool { self != .lifetime }

  init?(productID: String) {
    guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
    self = plan
  }

  var title: String {
    switch self {
    case .yearly: return "Yearly"
    case .monthly: return "Monthly"
    case .lifetime: return "Lifetime"
    }
  }
}

extension ProPlan {
  /// Plans the Pro screen offers: all loaded ones, or only Lifetime as an
  /// upgrade for someone with an active subscription or trial.
  static func offered(loaded: Set<ProPlan>, hasActiveSubscription: Bool) -> [ProPlan] {
    let all = allCases.filter(loaded.contains)
    return hasActiveSubscription ? all.filter { $0 == .lifetime } : all
  }

  /// The plan the purchase button acts on: the tapped one if it's offered,
  /// otherwise the first offered plan. Never a plan that isn't shown.
  static func selection(chosen: ProPlan?, offered: [ProPlan]) -> ProPlan? {
    if let chosen, offered.contains(chosen) { return chosen }
    return offered.first
  }
}

/// A free trial's length, worded for the Pro screen. Weeks read as days
/// ("7 days"), the way trials are usually described.
struct TrialLength: Equatable {
  enum Unit: Equatable {
    case day, week, month, year

    init(_ unit: Product.SubscriptionPeriod.Unit) {
      switch unit {
      case .day: self = .day
      case .week: self = .week
      case .month: self = .month
      case .year: self = .year
      @unknown default: self = .day
      }
    }
  }

  var value: Int
  var unit: Unit

  private var normalized: (count: Int, word: String) {
    switch unit {
    case .day: return (value, "day")
    case .week: return (value * 7, "day")
    case .month: return (value, "month")
    case .year: return (value, "year")
    }
  }

  /// "7 days", "1 month"
  var phrase: String {
    let (count, word) = normalized
    return "\(count) \(word)\(count == 1 ? "" : "s")"
  }

  /// "7-Day", for "Start 7-Day Free Trial"
  var title: String {
    let (count, word) = normalized
    return "\(count)-\(word.prefix(1).uppercased())\(word.dropFirst())"
  }
}

/// One verified transaction from StoreKit, reduced to what decides access.
struct ProEntitlement: Equatable {
  var plan: ProPlan
  var expiresAt: Date?
  var isRevoked = false
  var isTrial = false
}

enum ProAccess: Equatable {
  case free
  case subscribed(ProPlan, expiresAt: Date?, trial: Bool)
  case lifetime

  var isPro: Bool { self != .free }

  /// StoreKit's current entitlements already leave out expired
  /// subscriptions and keep ones in a billing grace period, so only
  /// refunds are filtered here. Lifetime wins over a subscription.
  static func resolve(_ entitlements: [ProEntitlement]) -> ProAccess {
    let valid = entitlements.filter { !$0.isRevoked }
    if valid.contains(where: { $0.plan == .lifetime }) { return .lifetime }
    let subscription = valid.filter(\.plan.isSubscription)
      .max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
    guard let subscription else { return .free }
    return .subscribed(subscription.plan, expiresAt: subscription.expiresAt, trial: subscription.isTrial)
  }

  /// Short status for Settings.
  var summary: String {
    switch self {
    case .free: return "Free"
    case .lifetime: return "Lifetime"
    case let .subscribed(plan, expiresAt, trial):
      let date = expiresAt?.formatted(date: .abbreviated, time: .omitted)
      if trial { return date.map { "Free trial until \($0)" } ?? "Free trial" }
      return date.map { "\(plan.title), renews or ends \($0)" } ?? plan.title
    }
  }

  fileprivate var cacheValue: String {
    switch self {
    case .free: return "free"
    case .lifetime: return "lifetime"
    case .subscribed: return "subscribed"
    }
  }
}

enum ProStoreError: LocalizedError {
  case unavailable, unverified

  var errorDescription: String? {
    switch self {
    case .unavailable: return "Plans couldn't be loaded from the App Store. Check your connection and try again."
    case .unverified: return "The App Store couldn't verify this purchase."
    }
  }
}

/// Cod Pro purchases with StoreKit 2: products, purchase, restore and the
/// live entitlement. All access decisions go through `isPro`.
@MainActor
final class ProStore: ObservableObject {
  static let shared = ProStore()

  enum PurchaseOutcome: Equatable { case purchased, pending, cancelled }

  @Published private(set) var access: ProAccess
  @Published private(set) var products: [ProPlan: Product] = [:]
  /// The free trial this Apple Account can still start, from App Store
  /// Connect's introductory offer; nil when there's none or it was used.
  @Published private(set) var trial: TrialLength?
  var isTrialEligible: Bool { trial != nil }
  @Published private(set) var isLoadingProducts = false
  @Published private(set) var productsError: String?

  private let defaults: UserDefaults
  private var updates: Task<Void, Never>?
  private static let cacheKey = "cod.pro.lastAccess"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    // Remember the last answer so a Pro user never sees a lock while
    // StoreKit reads its entitlements at launch.
    access = defaults.string(forKey: Self.cacheKey) == "lifetime" ? .lifetime
      : defaults.string(forKey: Self.cacheKey) == "subscribed" ? .subscribed(.yearly, expiresAt: nil, trial: false)
      : .free
  }

  var isPro: Bool {
    #if DEBUG && targetEnvironment(simulator)
    if let override = Self.testOverride { return override }
    #endif
    return access.isPro
  }

  var hasActiveSubscription: Bool {
    if case .subscribed = access { return true }
    return false
  }

  /// Listens for renewals, refunds, Ask to Buy approvals and purchases made
  /// on other devices, then reads the current entitlements.
  func start() {
    guard updates == nil else { return }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        if case .verified(let transaction) = result { await transaction.finish() }
        await self?.refresh()
      }
    }
    // Load products too, so Settings can offer the trial before the Pro
    // screen has ever been opened.
    Task { await refresh(); await loadProducts() }
  }

  func refresh() async {
    var entitlements: [ProEntitlement] = []
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
            let plan = ProPlan(productID: transaction.productID) else { continue }
      entitlements.append(.init(
        plan: plan, expiresAt: transaction.expirationDate,
        isRevoked: transaction.revocationDate != nil,
        isTrial: transaction.offerType == .introductory))
    }
    access = .resolve(entitlements)
    defaults.set(access.cacheValue, forKey: Self.cacheKey)
    await updateTrialEligibility()
  }

  func loadProducts() async {
    guard !isLoadingProducts else { return }
    isLoadingProducts = true
    defer { isLoadingProducts = false }
    do {
      let loaded = try await Product.products(for: ProPlan.allCases.map(\.productID))
      var byPlan: [ProPlan: Product] = [:]
      for product in loaded { if let plan = ProPlan(productID: product.id) { byPlan[plan] = product } }
      products = byPlan
      productsError = byPlan.isEmpty ? ProStoreError.unavailable.localizedDescription : nil
      await updateTrialEligibility()
    } catch {
      productsError = ProStoreError.unavailable.localizedDescription
    }
  }

  /// Finishes a purchase made with SwiftUI's purchase action.
  func complete(_ result: Product.PurchaseResult) async throws -> PurchaseOutcome {
    switch result {
    case .success(let verification):
      guard case .verified(let transaction) = verification else { throw ProStoreError.unverified }
      await transaction.finish()
      await refresh()
      return .purchased
    case .pending:
      return .pending
    case .userCancelled:
      return .cancelled
    @unknown default:
      return .cancelled
    }
  }

  /// Restore Purchases: asks the App Store to sync, which can show a sign-in.
  func restore() async throws {
    try await AppStore.sync()
    await refresh()
  }

  /// A free trial is offered once per subscription group, so the yearly
  /// plan's eligibility answers for both subscriptions.
  private func updateTrialEligibility() async {
    guard let subscription = (products[.yearly] ?? products[.monthly])?.subscription,
          let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial else {
      trial = nil
      return
    }
    let length = TrialLength(value: offer.period.value, unit: .init(offer.period.unit))
    trial = await subscription.isEligibleForIntroOffer ? length : nil
  }

  #if DEBUG && targetEnvironment(simulator)
  /// UI tests run without App Store products. `--launch-ui-test` floats as
  /// Pro; `--free-tier-ui-test` checks the free tier. The choice is kept so
  /// Launch Lab tests that cold-launch Cod by opening a file behave the same.
  /// Unit tests always see the real StoreKit answer.
  static var testOverride: Bool? = {
    let process = ProcessInfo.processInfo
    guard process.environment["XCTestConfigurationFilePath"] == nil else { return nil }
    let key = "cod.pro.uiTestOverride"
    if process.arguments.contains("--free-tier-ui-test") {
      UserDefaults.standard.set(false, forKey: key); return false
    }
    if process.arguments.contains("--launch-ui-test") {
      UserDefaults.standard.set(true, forKey: key); return true
    }
    return UserDefaults.standard.object(forKey: key) as? Bool
  }()
  #endif
}
