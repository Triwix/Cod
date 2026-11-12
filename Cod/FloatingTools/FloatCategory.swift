import SwiftUI

/// How the Float tab groups its tools. Each category is a card on Home; the
/// tool editor shows a switcher for the other tools in the same category.
enum FloatCategory: String, CaseIterable, Identifiable {
  case time, system

  var id: String { rawValue }

  var title: String {
    switch self {
    case .time: return "Time"
    case .system: return "System"
    }
  }

  var icon: String {
    switch self {
    case .time: return "clock"
    case .system: return "gauge.with.dots.needle.33percent"
    }
  }

  var tint: Color {
    switch self {
    case .time: return .blue
    case .system: return .green
    }
  }

  var kinds: [FloatingToolKind] {
    switch self {
    case .time: return [.countdown, .stopwatch, .event, .pomodoro, .clock, .worldClock]
    case .system: return [.system]
    }
  }

  static func category(for kind: FloatingToolKind) -> FloatCategory? {
    allCases.first { $0.kinds.contains(kind) }
  }
}

/// Recently floated tools, newest first, for one-tap reuse on Home.
struct RecentFloat: Codable, Identifiable, Equatable {
  var id = UUID()
  var configuration: FloatingToolConfiguration
  var floatedAt = Date()

  var title: String { configuration.kind.title }

  var detail: String {
    switch configuration.kind {
    case .countdown: return FloatingToolConfiguration.time(configuration.duration, roundingUp: true)
    case .pomodoro: return "\(Int(configuration.focusDuration / 60)) / \(Int(configuration.breakDuration / 60)) min"
    case .clock: return WorldClockFormatting.city(configuration.timeZoneIdentifier)
    case .worldClock: return "\(configuration.worldClockZones.count) cities"
    case .event: return configuration.eventTitle.isEmpty ? "Countdown" : configuration.eventTitle
    case .teleprompter:
      return String(configuration.text.prefix(24)).trimmingCharacters(in: .whitespacesAndNewlines)
    default: return ""
    }
  }
}

@MainActor
final class RecentFloats: ObservableObject {
  static let shared = RecentFloats()
  static let limit = 6
  private static let key = "cod.home.recentFloats"
  private let defaults: UserDefaults
  @Published private(set) var items: [RecentFloat]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    items = defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode([RecentFloat].self, from: $0) } ?? []
  }

  /// One entry per tool kind and setup; floating it again moves it to the front.
  func record(_ configuration: FloatingToolConfiguration) {
    var stored = configuration
    // Documents carry generated content that doesn't belong in a recents list.
    guard stored.kind != .document, stored.kind != .slideshow else { return }
    stored.usesSampleText = false
    items.removeAll { $0.configuration == stored }
    items.insert(RecentFloat(configuration: stored), at: 0)
    if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    persist()
  }

  func remove(_ item: RecentFloat) {
    items.removeAll { $0.id == item.id }
    persist()
  }

  func clear() {
    items.removeAll()
    persist()
  }

  private func persist() {
    defaults.set(try? JSONEncoder().encode(items), forKey: Self.key)
  }
}
