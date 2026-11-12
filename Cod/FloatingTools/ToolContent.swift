import Foundation

/// Teleprompter "Lines" mode: the current line large, the next lines dimmed
/// below it, and a position counter. Each line gets reading time in proportion
/// to its word count, so long lines stay up longer than short ones.
struct LinePresentation: Equatable {
  struct Frame: Equatable {
    var current: String
    var upcoming: [String]
    var index: Int
    var count: Int
  }

  let lines: [String]
  private let starts: [TimeInterval]
  let duration: TimeInterval

  init(text: String, wordsPerMinute: Double) {
    let pace = wordsPerMinute.isFinite ? min(80_000, max(1, wordsPerMinute)) : 180
    lines = Self.split(text)
    var starts: [TimeInterval] = []
    var clock: TimeInterval = 0
    for line in lines {
      starts.append(clock)
      let words = max(1, line.split(whereSeparator: \.isWhitespace).count)
      clock += Double(words) * 60 / pace
    }
    self.starts = starts
    duration = clock
  }

  /// Hard line breaks first. A long paragraph is split at sentence ends, then
  /// at about twelve words, so one line never fills the whole window.
  static func split(_ text: String, maximumWords: Int = 12) -> [String] {
    var result: [String] = []
    for paragraph in text.components(separatedBy: .newlines) {
      let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      var sentence: [String] = []
      for word in trimmed.split(whereSeparator: \.isWhitespace).map(String.init) {
        sentence.append(word)
        let ends = word.last.map { ".!?".contains($0) } ?? false
        if ends || sentence.count >= maximumWords {
          result.append(sentence.joined(separator: " "))
          sentence.removeAll()
        }
      }
      if !sentence.isEmpty { result.append(sentence.joined(separator: " ")) }
    }
    return result
  }

  func frame(at elapsed: TimeInterval, upcomingCount: Int = 2) -> Frame {
    guard !lines.isEmpty else { return Frame(current: "", upcoming: [], index: 0, count: 0) }
    let safe = elapsed.isFinite ? max(0, elapsed) : 0
    let index = max(0, (starts.lastIndex { $0 <= safe }) ?? 0)
    let next = lines[(index + 1)..<min(lines.count, index + 1 + upcomingCount)]
    return Frame(current: lines[index], upcoming: Array(next), index: index, count: lines.count)
  }
}

/// One row in a multi-row tool (World Clock, System Monitor).
struct FloatingToolRow: Equatable {
  var label: String
  var value: String
  var note = ""
}

enum WorldClockFormatting {
  static let maximumZones = 4

  static func city(_ identifier: String) -> String {
    identifier.split(separator: "/").last.map(String.init)?
      .replacingOccurrences(of: "_", with: " ") ?? identifier
  }

  /// "+1 day" style note relative to the device's own calendar day.
  static func dayNote(for date: Date, zone: TimeZone, home: TimeZone = .autoupdatingCurrent) -> String {
    var homeCalendar = Calendar(identifier: .gregorian)
    homeCalendar.timeZone = home
    var zoneCalendar = Calendar(identifier: .gregorian)
    zoneCalendar.timeZone = zone
    let homeDay = homeCalendar.dateComponents([.year, .month, .day], from: date)
    let zoneDay = zoneCalendar.dateComponents([.year, .month, .day], from: date)
    guard let a = homeCalendar.date(from: homeDay), let b = homeCalendar.date(from: zoneDay) else { return "" }
    let days = homeCalendar.dateComponents([.day], from: a, to: b).day ?? 0
    switch days {
    case 0: return ""
    case 1: return "Tomorrow"
    case -1: return "Yesterday"
    default: return days > 0 ? "+\(days) days" : "\(days) days"
    }
  }

  static func rows(zones: [String], date: Date, uses24Hour: Bool, home: TimeZone = .autoupdatingCurrent) -> [FloatingToolRow] {
    zones.prefix(maximumZones).compactMap { identifier in
      guard let zone = TimeZone(identifier: identifier) else { return nil }
      let formatter = DateFormatter()
      formatter.locale = .autoupdatingCurrent
      formatter.timeZone = zone
      formatter.dateFormat = uses24Hour ? "HH:mm" : "h:mm a"
      return FloatingToolRow(
        label: city(identifier), value: formatter.string(from: date),
        note: dayNote(for: date, zone: zone, home: home))
    }
  }
}

enum EventCountdownFormatting {
  /// "3d 04:12:09", "04:12:09" or "12:09" until the event; nil once it's past.
  static func remaining(until target: Date, from now: Date) -> String? {
    let seconds = target.timeIntervalSince(now)
    guard seconds.isFinite, seconds > 0 else { return nil }
    let total = Int(min(Double(Int32.max), ceil(seconds)))
    let days = total / 86_400
    let clock = total % 86_400
    let time =
      clock >= 3_600 || days > 0
      ? String(format: "%02d:%02d:%02d", clock / 3_600, clock / 60 % 60, clock % 60)
      : String(format: "%02d:%02d", clock / 60, clock % 60)
    return days > 0 ? "\(days)d \(time)" : time
  }
}
