import Foundation

/// Clock-style wheels persist one value, not three independently saved fields.
struct TimerDuration: Equatable {
    static let maximum = 86_399
    var totalSeconds: Int
    init(_ seconds: Int) { totalSeconds = min(Self.maximum, max(0, seconds)) }
    var hours: Int { totalSeconds / 3_600 }
    var minutes: Int { totalSeconds / 60 % 60 }
    var seconds: Int { totalSeconds % 60 }
    func changing(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) -> Self {
        .init(min(23, max(0, hours ?? self.hours)) * 3_600
              + min(59, max(0, minutes ?? self.minutes)) * 60
              + min(59, max(0, seconds ?? self.seconds)))
    }
}
