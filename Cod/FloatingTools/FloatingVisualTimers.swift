import Combine

/// Visual timers don't need background execution: their monotonic deadlines
/// keep advancing. Retain closed sessions so users can find and cancel them.
@MainActor final class FloatingVisualTimers: ObservableObject {
  static let shared = FloatingVisualTimers()
  @Published private(set) var sessions: [FloatingToolSession] = []

  func keep(_ session: FloatingToolSession) {
    sessions.removeAll { $0.snapshot.isFinished }
    guard session.configuration.kind == .countdown, !session.configuration.hasTimerAlarm,
      session.isPlaying, !session.snapshot.isFinished,
      !sessions.contains(where: { $0.id == session.id })
    else { return }
    sessions.append(session)
  }

  func cancel(_ session: FloatingToolSession) {
    session.pause()
    sessions.removeAll { $0.id == session.id }
  }
}
