import Foundation

struct PomodoroValues: Equatable {
  static let focusRange = 1...180
  static let breakRange = 1...60
  static let sessionRange = 1...12
  let focus: Int
  let rest: Int
  let sessions: Int

  init?(focus: String, rest: String, sessions: String) {
    guard let focus = Self.number(focus, in: Self.focusRange),
      let rest = Self.number(rest, in: Self.breakRange),
      let sessions = Self.number(sessions, in: Self.sessionRange)
    else { return nil }
    self.focus = focus
    self.rest = rest
    self.sessions = sessions
  }

  static func number(_ input: String, in range: ClosedRange<Int>) -> Int? {
    guard let number = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
      range.contains(number)
    else { return nil }
    return number
  }
}
