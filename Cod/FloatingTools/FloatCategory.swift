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
    case .system: return [.system, .speedometer]
    }
  }

  static func category(for kind: FloatingToolKind) -> FloatCategory? {
    allCases.first { $0.kinds.contains(kind) }
  }
}

/// Recently floated tools, newest first, for one-tap reuse on Home and in
/// the Recents tab.
struct RecentFloat: Codable, Identifiable, Equatable {
  var id = UUID()
  var configuration: FloatingToolConfiguration
  var floatedAt = Date()
  /// Optional so lists saved by build 29 still decode.
  var starred: Bool?
  var isStarred: Bool { starred ?? false }

  var title: String {
    switch configuration.kind {
    case .slideshow: return configuration.setName ?? "Image Set"
    case .document: return configuration.text.isEmpty ? configuration.kind.title : configuration.text
    default: return configuration.kind.title
    }
  }

  /// The setup's own detail, plus the window shape when it isn't the
  /// default, so two setups never look identical in the list.
  var detail: String {
    let shape = configuration.windowShape == .wide || configuration.kind == .document
      ? nil : configuration.windowShape.ratio
    return [baseDetail, shape].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
  }

  private var baseDetail: String? {
    switch configuration.kind {
    case .countdown: return FloatingToolConfiguration.time(configuration.duration, roundingUp: true)
    case .pomodoro: return "\(Int(configuration.focusDuration / 60)) / \(Int(configuration.breakDuration / 60)) min"
    case .clock: return WorldClockFormatting.city(configuration.timeZoneIdentifier)
    case .worldClock: return "\(configuration.worldClockZones.count) cities"
    case .event: return configuration.eventTitle.isEmpty ? "Countdown" : configuration.eventTitle
    case .teleprompter:
      let firstLine = configuration.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
      return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(48))
    case .system:
      let count = configuration.systemMetrics.count
      return count == 1 ? configuration.systemMetrics[0].title : "\(count) readings"
    case .speedometer: return configuration.usesMetricSpeed ? "km/h" : "mph"
    case .stopwatch: return configuration.showsHundredths ? "Hundredths" : nil
    case .slideshow:
      let count = configuration.slideNames.count
      return configuration.startsPaused ? "\(count) pages" : "\(count) images · every \(Int(configuration.slideInterval)) s"
    case .document: return "Auto-scroll · \(configuration.documentPages.count) pages"
    }
  }
}

@MainActor
final class RecentFloats: ObservableObject {
  static let shared = RecentFloats()
  /// Unstarred entries kept; starred ones stay until removed.
  static let limit = 30
  private static let key = "cod.home.recentFloats"
  private let defaults: UserDefaults
  @Published private(set) var items: [RecentFloat]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let saved = defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode([RecentFloat].self, from: $0) } ?? []
    // Lists saved before build 36 could hold the same setup twice, once per
    // light/dark mode. Keep the newest, and its star if either had one.
    var merged: [RecentFloat] = []
    for var item in saved {
      item.configuration = Self.normalized(item.configuration)
      if let index = merged.firstIndex(where: { $0.configuration == item.configuration }) {
        if item.isStarred { merged[index].starred = true }
      } else {
        merged.append(item)
      }
    }
    items = merged
  }

  /// What makes two setups the same. Light/dark mode is applied when a setup
  /// floats, so it isn't part of the setup.
  static func normalized(_ configuration: FloatingToolConfiguration) -> FloatingToolConfiguration {
    var stored = configuration
    stored.usesSampleText = false
    stored.interfaceStyle = .unspecified
    return stored
  }

  /// One entry per tool setup; floating it again moves it to the front and
  /// keeps its star. Image sets, PDF pages and auto-scroll documents are
  /// included; their images live with the image sets.
  func record(_ configuration: FloatingToolConfiguration) {
    let stored = Self.normalized(configuration)
    if stored.kind == .document, stored.documentPages.isEmpty { return }
    if stored.kind == .slideshow, stored.slideNames.isEmpty { return }
    let wasStarred = items.contains { $0.configuration == stored && $0.isStarred }
    items.removeAll { $0.configuration == stored }
    items.insert(RecentFloat(configuration: stored, starred: wasStarred ? true : nil), at: 0)
    trim()
    persist()
  }

  /// Home shows starred setups first, then the newest.
  var forHome: [RecentFloat] {
    Array((items.filter(\.isStarred) + items.filter { !$0.isStarred }).prefix(8))
  }

  func toggleStar(_ id: RecentFloat.ID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].starred = items[index].isStarred ? nil : true
    trim()
    persist()
  }

  func remove(_ item: RecentFloat) {
    items.removeAll { $0.id == item.id }
    persist()
  }

  /// Keeps starred setups.
  func clearUnstarred() {
    items.removeAll { !$0.isStarred }
    persist()
  }

  func clear() {
    items.removeAll()
    persist()
  }

  private func trim() {
    var unstarred = 0
    items.removeAll { item in
      guard !item.isStarred else { return false }
      unstarred += 1
      return unstarred > Self.limit
    }
  }

  private func persist() {
    defaults.set(try? JSONEncoder().encode(items), forKey: Self.key)
  }
}
