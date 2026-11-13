import StoreKit
import SwiftUI

/// The Cod Pro screen. It only appears when someone taps a Pro feature or
/// opens it from Settings: never at launch, and never as an ad.
struct ProView: View {
  var feature: ProFeature?

  @EnvironmentObject private var coordinator: CaptureCoordinator
  @ObservedObject private var pro = ProStore.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.purchase) private var purchase
  @State private var plan: ProPlan = .yearly
  @State private var isPurchasing = false
  @State private var isRestoring = false
  @State private var message: String?
  @State private var managingSubscription = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header
          if pro.isPro { ownedCard } else { features }
          if !pro.isPro || pro.hasActiveSubscription { plans }
          footer
        }
        .padding(.horizontal, 20).padding(.bottom, 32)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
      }
      .background(Color(.systemGroupedBackground))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }.accessibilityIdentifier("pro-close")
        }
      }
      .task { await pro.loadProducts() }
      .manageSubscriptionsSheet(isPresented: $managingSubscription)
    }
    .accessibilityIdentifier("pro-screen")
  }

  // MARK: Sections

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "pip.enter")
        .font(.title.weight(.semibold)).foregroundStyle(.white)
        .frame(width: 56, height: 56)
        .background(Color.codActionBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
      Text("Cod Pro").font(.largeTitle.weight(.bold))
      Text(subtitle).font(.body).foregroundStyle(.secondary)
        .accessibilityIdentifier("pro-subtitle")
    }
    .padding(.top, 8)
  }

  private var subtitle: String {
    if pro.isPro { return "Everything in Cod is unlocked." }
    if let feature { return "Floating \(feature.phrase) is part of Cod Pro, along with everything below." }
    return "Float anything you're working from, not just images."
  }

  private var features: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(orderedFeatures) { item in
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: item.icon)
            .font(.body.weight(.medium)).foregroundStyle(Color.codActionBackground)
            .frame(width: 28)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.subheadline.weight(.semibold))
            Text(item.detail).font(.footnote).foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pro-feature-\(item.rawValue)")
      }
      Text("Always free: crop and float images and screenshots, the Share and Back Tap Shortcuts, Copy Text, Translate, Scan Code, Recents and Safari Video.")
        .font(.footnote).foregroundStyle(.secondary)
        .padding(.top, 4)
    }
  }

  private var orderedFeatures: [ProFeature] {
    guard let feature else { return ProFeature.allCases }
    return [feature] + ProFeature.allCases.filter { $0 != feature }
  }

  private var ownedCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(pro.access.summary, systemImage: "checkmark.seal.fill")
        .font(.headline).foregroundStyle(.green)
        .accessibilityIdentifier("pro-status")
      if pro.hasActiveSubscription {
        Button("Manage Subscription") { managingSubscription = true }
          .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder private var plans: some View {
    if pro.products.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        if pro.isLoadingProducts {
          ProgressView("Loading plans…")
        } else {
          Text(pro.productsError ?? ProStoreError.unavailable.localizedDescription)
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("pro-plans-unavailable")
          Button("Try Again") { Task { await pro.loadProducts() } }
            .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(spacing: 10) {
        ForEach(availablePlans) { option in planRow(option) }
        if let product = pro.products[plan] {
          Button { Task { await buy(product) } } label: {
            Group {
              if isPurchasing { ProgressView() } else { Text(buyTitle) }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
          }
          .buttonStyle(CodActionStyle())
          .disabled(isPurchasing || isRestoring)
          .accessibilityIdentifier("pro-purchase")
          .padding(.top, 4)
          Text(disclosure(for: product))
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("pro-disclosure")
          if plan == .lifetime, pro.hasActiveSubscription {
            VStack(alignment: .leading, spacing: 8) {
              Text("Buying Lifetime doesn't cancel your subscription or free trial. Cancel it yourself so you aren't charged again.")
                .font(.footnote.weight(.semibold))
              Button("Manage Subscription") { managingSubscription = true }
                .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("pro-lifetime-cancel-note")
          }
        }
        if let message {
          Text(message).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("pro-message")
        }
      }
    }
  }

  /// A subscriber only sees Lifetime as an upgrade.
  private var availablePlans: [ProPlan] {
    let all = ProPlan.allCases.filter { pro.products[$0] != nil }
    return pro.hasActiveSubscription ? all.filter { $0 == .lifetime } : all
  }

  private func planRow(_ option: ProPlan) -> some View {
    let selected = plan == option
    return Button { plan = option; message = nil } label: {
      HStack(spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.title3).foregroundStyle(selected ? Color.codActionBackground : Color.secondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(option.title).font(.headline)
            if option.isSubscription, pro.isTrialEligible {
              Text("7 days free")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .foregroundStyle(Color.codActionBackground)
                .background(Color.codActionBackground.opacity(0.14), in: Capsule())
            }
          }
          Text(priceLine(option)).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(14)
      .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(selected ? Color.codActionBackground : .clear, lineWidth: 2)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("pro-plan-\(option.rawValue)")
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(isRestoring ? "Restoring…" : "Restore Purchases") { Task { await restore() } }
        .disabled(isRestoring || isPurchasing)
        .accessibilityIdentifier("pro-restore")
      HStack(spacing: 16) {
        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        if let privacy = Self.privacyPolicyURL { Link("Privacy Policy", destination: privacy) }
      }
      .font(.footnote)
    }
  }

  // MARK: Copy

  private func priceLine(_ option: ProPlan) -> String {
    guard let product = pro.products[option] else { return "" }
    switch option {
    case .yearly:
      let monthly = (product.price / 12).formatted(product.priceFormatStyle)
      return "\(product.displayPrice) a year (\(monthly) a month)"
    case .monthly: return "\(product.displayPrice) a month"
    case .lifetime: return "\(product.displayPrice) once"
    }
  }

  private var buyTitle: String {
    switch plan {
    case .lifetime: return "Buy Lifetime"
    case .yearly, .monthly: return pro.isTrialEligible ? "Start 7-Day Free Trial" : "Subscribe"
    }
  }

  private func disclosure(for product: Product) -> String {
    let renewal = "Renews automatically until you cancel. Cancel anytime in Settings at least 24 hours before the end of the period."
    switch plan {
    case .lifetime:
      return "One payment of \(product.displayPrice). Pro stays unlocked on your devices and works with Family Sharing."
    case .yearly, .monthly:
      let period = plan == .yearly ? "year" : "month"
      if pro.isTrialEligible {
        return "Free for 7 days, then \(product.displayPrice) a \(period). \(renewal) If you cancel during the trial, you won't be charged."
      }
      return "\(product.displayPrice) a \(period). \(renewal)"
    }
  }

  static var privacyPolicyURL: URL? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CodPrivacyPolicyURL") as? String,
          value.hasPrefix("https://") else { return nil }
    return URL(string: value)
  }

  // MARK: Actions

  private func buy(_ product: Product) async {
    isPurchasing = true
    message = nil
    defer { isPurchasing = false }
    do {
      switch try await pro.complete(try await purchase(product)) {
      case .purchased:
        dismiss()
        coordinator.toast = .info("Cod Pro is on", "Thanks! Everything in Cod is unlocked.")
      case .pending:
        message = "Waiting for approval. Pro turns on as soon as the purchase is approved."
      case .cancelled:
        break
      }
    } catch {
      message = error.localizedDescription
    }
  }

  private func restore() async {
    isRestoring = true
    message = nil
    defer { isRestoring = false }
    do {
      try await pro.restore()
      if pro.isPro {
        dismiss()
        coordinator.toast = .info("Cod Pro restored", pro.access.summary)
      } else {
        message = "No Cod Pro purchase was found for this Apple Account."
      }
    } catch {
      message = error.localizedDescription
    }
  }
}

/// Presents the Pro screen when the coordinator asks for it. Applied at the
/// root and inside route sheets, so it appears over whatever is on top.
struct ProPromptPresenter: ViewModifier {
  @EnvironmentObject private var coordinator: CaptureCoordinator
  var inRoute: Bool

  func body(content: Content) -> some View {
    content.sheet(item: Binding(
      get: { inRoute || coordinator.route == nil ? coordinator.proPrompt : nil },
      set: { coordinator.proPrompt = $0 }
    )) { prompt in
      ProView(feature: prompt.feature).environmentObject(coordinator)
    }
  }
}

extension View {
  func proPrompts(inRoute: Bool = false) -> some View { modifier(ProPromptPresenter(inRoute: inRoute)) }
}
