import ActivityKit
import AlarmKit
import Combine
import SwiftUI

@MainActor
protocol FloatingTimerAlarmScheduling: AnyObject {
  func schedule(id: UUID, after duration: TimeInterval) async throws -> Date
  func cancel(id: UUID) throws
}

struct FloatingTimerAlarmRecord: Identifiable, Codable, Equatable {
  let id: UUID
  let date: Date
  var estimated: Bool? = nil
}

enum FloatingTimerAlarmError: LocalizedError {
  case unavailable, permissionDenied
  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Timer alarms require iOS 26 or later. You can still use the visual timer."
    case .permissionDenied:
      return
        "Allow alarms for Cod in Settings, or turn off Alarm when finished to use a visual-only timer."
    }
  }
}

/// AlarmKit owns delivery and sound, including when Cod isn't running. These
/// are native duration timers, with the required countdown widget. A two-second
/// timer isn't an absolute clock alarm rounded to a wall-clock second.
@MainActor
final class FloatingTimerAlarms: ObservableObject, FloatingTimerAlarmScheduling {
  static let shared = FloatingTimerAlarms()
  @Published private(set) var records: [FloatingTimerAlarmRecord]
  private let defaults: UserDefaults
  private var updates: Task<Void, Never>?
  private var activityDiscovery: Task<Void, Never>?
  private var activityObservers: [String: Task<Void, Never>] = [:]
  private var scheduledAfter: [UUID: Date] = [:]
  private var alertingIDs: Set<UUID> = []
  private final class WeakSession {
    weak var value: FloatingToolSession?
    init(_ value: FloatingToolSession) { self.value = value }
  }
  private var sessions: [UUID: WeakSession] = [:]
  private static let storageKey = "cod.tools.timerAlarms"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    records =
      defaults.data(forKey: Self.storageKey)
      .flatMap { try? JSONDecoder().decode([FloatingTimerAlarmRecord].self, from: $0) } ?? []
  }

  static var isAvailable: Bool {
    if #available(iOS 26.0, *) { return true }
    return false
  }

  func authorize() async throws {
    guard #available(iOS 26.0, *) else { throw FloatingTimerAlarmError.unavailable }
    guard try await AlarmManager.shared.requestAuthorization() == .authorized else {
      throw FloatingTimerAlarmError.permissionDenied
    }
  }

  func track(_ session: FloatingToolSession) {
    sessions = sessions.filter { $0.value.value != nil }
    sessions[session.id] = WeakSession(session)
  }

  func cancelTimer(id: UUID) async throws {
    if let session = sessions[id]?.value {
      session.cancelAlarm()
      await session.waitForAlarmUpdate()
      if let error = session.alarmError {
        throw NSError(
          domain: "CodTimerAlarm", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
      }
    } else {
      try cancel(id: id)
    }
  }

  func schedule(id: UUID, after duration: TimeInterval) async throws -> Date {
    guard #available(iOS 26.0, *) else { throw FloatingTimerAlarmError.unavailable }
    guard AlarmManager.shared.authorizationState == .authorized else {
      throw FloatingTimerAlarmError.permissionDenied
    }
    if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
      try AlarmManager.shared.cancel(id: id)
    }
    monitor()
    let requested = Date()
    scheduledAfter[id] = requested
    alertingIDs.remove(id)
    CodDiagnosticLog.record(
      "timer schedule requested duration=\(duration) id=\(id) at=\(requested.timeIntervalSince1970)"
    )
    _ = try await AlarmManager.shared.schedule(
      id: id, configuration: Self.configuration(duration: duration))
    let completed = Date()
    let actual = Self.countdownDeadline(id: id, notBefore: requested)
    let date = actual ?? completed.addingTimeInterval(duration)
    records.removeAll { $0.id == id }
    records.append(.init(id: id, date: date, estimated: actual == nil))
    persist()
    for activity in Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activities { watch(activity) }
    CodDiagnosticLog.record(
      "timer scheduled duration=\(duration) id=\(id) deadline=\(date.timeIntervalSince1970) source=\(actual == nil ? "estimated" : "system") schedulingSeconds=\(completed.timeIntervalSince(requested))"
    )
    return records.first(where: { $0.id == id })?.date ?? date
  }

  func cancel(id: UUID) throws {
    guard #available(iOS 26.0, *) else { throw FloatingTimerAlarmError.unavailable }
    // An alarm already dismissed in system UI needs no further cancel.
    if try AlarmManager.shared.alarms.contains(where: { $0.id == id }) {
      try AlarmManager.shared.cancel(id: id)
    }
    records.removeAll { $0.id == id }
    scheduledAfter.removeValue(forKey: id)
    alertingIDs.remove(id)
    persist()
    CodDiagnosticLog.record("timer cancelled id=\(id) at=\(Date().timeIntervalSince1970)")
  }

  func monitor() {
    guard updates == nil, #available(iOS 26.0, *) else { return }
    for activity in Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activities { watch(activity) }
    activityDiscovery = Task { @MainActor [weak self] in
      for await activity in Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activityUpdates {
        guard let self, !Task.isCancelled else { return }
        self.watch(activity)
      }
    }
    updates = Task { @MainActor [weak self] in
      for await _ in AlarmManager.shared.alarmUpdates {
        guard let self, !Task.isCancelled else { return }
        // Query current state rather than applying a queued snapshot
        // from before a pause/reschedule completed.
        guard let alarms = try? AlarmManager.shared.alarms else { continue }
        let existing = Set(alarms.map(\.id))
        for alarm in alarms where alarm.state == .alerting && !self.alertingIDs.contains(alarm.id) {
          let now = Date()
          let record = self.records.first { $0.id == alarm.id }
          let lateness = record.map { now.timeIntervalSince($0.date) }
          CodDiagnosticLog.record(
            "timer alerting id=\(alarm.id) at=\(now.timeIntervalSince1970) deadlineDelta=\(lateness.map(String.init(describing:)) ?? "unknown") estimated=\(record?.estimated ?? true)"
          )
          self.sessions[alarm.id]?.value?.alarmDidAlert()
        }
        self.alertingIDs = Set(alarms.filter { $0.state == .alerting }.map(\.id))
        for record in self.records where !existing.contains(record.id) {
          self.sessions[record.id]?.value?.alarmWasDismissed()
        }
        self.records.removeAll { !existing.contains($0.id) }
        self.scheduledAfter = self.scheduledAfter.filter { existing.contains($0.key) }
        let activeActivities = Set(
          Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activities.map(\.id))
        for id in Array(self.activityObservers.keys) where !activeActivities.contains(id) {
          self.activityObservers.removeValue(forKey: id)?.cancel()
        }
        for activity in Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activities {
          self.watch(activity)
        }
        self.persist()
      }
    }
  }

  @available(iOS 26.0, *)
  private static func countdownDeadline(id: UUID, notBefore: Date) -> Date? {
    for activity in Activity<AlarmAttributes<CodTimerAlarmMetadata>>.activities
    where activity.activityState == .active {
      let state = activity.content.state
      if state.alarmID == id, case .countdown(let countdown) = state.mode,
        countdown.startDate >= notBefore.addingTimeInterval(-0.05)
      {
        return countdown.fireDate
      }
    }
    return nil
  }

  @available(iOS 26.0, *)
  private func watch(_ activity: Activity<AlarmAttributes<CodTimerAlarmMetadata>>) {
    reconcile(activity)
    guard activityObservers[activity.id] == nil, activity.activityState == .active else { return }
    activityObservers[activity.id] = Task { @MainActor [weak self] in
      for await _ in activity.contentUpdates {
        guard let self, !Task.isCancelled else { return }
        self.reconcile(activity)
      }
    }
  }

  @available(iOS 26.0, *)
  private func reconcile(_ activity: Activity<AlarmAttributes<CodTimerAlarmMetadata>>) {
    let state = activity.content.state
    guard activity.activityState == .active, case .countdown(let countdown) = state.mode,
      !alertingIDs.contains(state.alarmID),
      countdown.startDate
        >= (scheduledAfter[state.alarmID] ?? .distantPast).addingTimeInterval(-0.05),
      let index = records.firstIndex(where: { $0.id == state.alarmID })
    else { return }
    let old = records[index]
    guard old.estimated != false || abs(old.date.timeIntervalSince(countdown.fireDate)) > 0.02
    else { return }
    records[index] = .init(id: old.id, date: countdown.fireDate, estimated: false)
    sessions[old.id]?.value?.alarmDeadlineDidChange(countdown.fireDate)
    persist()
    CodDiagnosticLog.record(
      "timer deadline synchronized id=\(old.id) deadline=\(countdown.fireDate.timeIntervalSince1970) correction=\(countdown.fireDate.timeIntervalSince(old.date))"
    )
  }

  private func persist() {
    defaults.set(try? JSONEncoder().encode(records), forKey: Self.storageKey)
  }

  @available(iOS 26.0, *)
  static func configuration(duration: TimeInterval)
    -> AlarmManager.AlarmConfiguration<CodTimerAlarmMetadata>
  {
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = .init(title: "Timer finished")
    } else {
      alert = .init(
        title: "Timer finished",
        stopButton: .init(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
    }
    let attributes = AlarmAttributes(
      presentation: .init(alert: alert, countdown: .init(title: "Cod Timer")),
      metadata: CodTimerAlarmMetadata(), tintColor: .orange)
    return .timer(duration: duration, attributes: attributes, sound: .default)
  }

  func isAlerting(id: UUID) -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    return (try? AlarmManager.shared.alarms.contains { $0.id == id && $0.state == .alerting })
      == true
  }
}
