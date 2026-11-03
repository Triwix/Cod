import Combine
import UIKit

enum FloatingToolKind: String, CaseIterable, Identifiable, Codable {
  case countdown, stopwatch, clock, pomodoro, teleprompter, document
  var id: String { rawValue }
  var title: String {
    switch self {
    case .countdown: return "Timer"
    case .stopwatch: return "Stopwatch"
    case .clock: return "Current Time"
    case .pomodoro: return "Pomodoro"
    case .teleprompter: return "Teleprompter"
    case .document: return "Scrolling Reference"
    }
  }
  var icon: String {
    switch self {
    case .countdown: return "timer"
    case .stopwatch: return "stopwatch"
    case .clock: return "clock"
    case .pomodoro: return "leaf"
    case .teleprompter: return "text.alignleft"
    case .document: return "doc.text"
    }
  }
}

enum TeleprompterMode: String, CaseIterable, Identifiable, Codable {
  case scroll, words
  var id: String { rawValue }
  var title: String { self == .scroll ? "Scrolling" : "Words" }
}

struct WordPresentation {
  let words: [String]
  let groupSize: Int
  let wordsPerMinute: Double
  init(text: String, groupSize: Int, wordsPerMinute: Double) {
    words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    self.groupSize = min(8, max(1, groupSize))
    self.wordsPerMinute = wordsPerMinute.isFinite ? min(80_000, max(0.001, wordsPerMinute)) : 180
  }
  var duration: TimeInterval { Double(words.count) * 60 / wordsPerMinute }
  func chunk(at elapsed: TimeInterval) -> String {
    guard !words.isEmpty else { return "" }
    let safeElapsed = elapsed.isFinite ? min(10_000_000, max(0, elapsed)) : 0
    let wordIndex = Int(safeElapsed * wordsPerMinute / 60)
    let index = min((words.count - 1) / groupSize, wordIndex / groupSize) * groupSize
    return words[index..<min(words.count, index + groupSize)].joined(separator: " ")
  }
}

struct FloatingToolConfiguration: Codable, Equatable {
  var kind: FloatingToolKind
  var text = ""
  var palette: FloatingPalette = .system
  var interfaceStyleValue = UIUserInterfaceStyle.unspecified.rawValue
  var interfaceStyle: UIUserInterfaceStyle {
    get { UIUserInterfaceStyle(rawValue: interfaceStyleValue) ?? .unspecified }
    set { interfaceStyleValue = newValue.rawValue }
  }
  var usesSampleText = false
  var duration: TimeInterval = 300
  var focusDuration: TimeInterval = 25 * 60
  var breakDuration: TimeInterval = 5 * 60
  var rounds = 4
  var timeZoneIdentifier = TimeZone.current.identifier
  var uses24HourClock = false
  /// Render-space points per second, independent of the PiP window size.
  var scrollSpeed: Double = 32
  var prompterMode: TeleprompterMode = .scroll
  var wordsAtATime = 1
  var wordsPerMinute: Double = 180
  var fontSize: Double = 44
  var readingGuide = false
  var sideMargin: Double = 48
  var lineSpacing: Double = 14
  /// Script duration excludes the optional starting countdown.
  var targetReadingDuration: TimeInterval?
  var safeTargetReadingDuration: TimeInterval? {
    targetReadingDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
  }
  var customColors: FloatingColors?
  var alarmWhenFinished = false
  var keepTimerRunningOnClose = true
  var showsHundredths = false
  var prompterCountdownEnabled = true
  var prompterCountdownSeconds = 3
  var showsClockLocation = true
  var showsClockTimeZone = true
  var showsClockDate = true
  static let defaultClockLocationSize: Double = 44
  static let defaultClockTimeSize: Double = 100
  static let defaultClockDateSize: Double = 36
  var clockLocationSize = defaultClockLocationSize
  var clockTimeSize = defaultClockTimeSize
  var clockDateSize = defaultClockDateSize

  var hasCustomClockSizes: Bool {
    clockLocationSize != Self.defaultClockLocationSize
      || clockTimeSize != Self.defaultClockTimeSize
      || clockDateSize != Self.defaultClockDateSize
  }

  mutating func resetClockSizes() {
    clockLocationSize = Self.defaultClockLocationSize
    clockTimeSize = Self.defaultClockTimeSize
    clockDateSize = Self.defaultClockDateSize
  }

  var prompterStartDelay: TimeInterval {
    prompterCountdownEnabled ? Double(prompterCountdownSeconds) : 0
  }

  var supportsSeeking: Bool { kind == .teleprompter || kind == .document }

  var hasTimerAlarm: Bool { kind == .countdown && alarmWhenFinished }

  /// Changing pixels need a higher cadence; clocks/whole seconds don't.
  var framesPerSecond: Double {
    switch kind {
    case .countdown, .pomodoro: return 20
    case .teleprompter: return prompterMode == .scroll ? 60 : 15
    case .document: return 30
    case .stopwatch: return showsHundredths ? 30 : 1
    case .clock: return 1
    }
  }

  func frameKey(elapsed: TimeInterval, date: Date) -> Int {
    let value = kind == .clock ? date.timeIntervalSince1970 : elapsed * framesPerSecond
    return Int(min(Double(Int.max / 2), max(Double(Int.min / 2), value.isFinite ? value : 0)))
  }

  var colors: FloatingColors {
    let base = customColors ?? palette.colors(for: interfaceStyle)
    return usesSampleText ? FloatingText.sampleColors(base) : base
  }

  static let exampleScript = """
    Welcome to your teleprompter.

    Keep your words in view while you present, practise a speech, or record in another app. Replace this example with your own script whenever you're ready.

    Take a breath. Look up. Speak naturally, as if you're talking to one person.

    Use Scroll speed to find a comfortable pace. Adjust the text size and colors so each line is easy to read.

    Tap Float to keep the script above other apps. Use the floating window's play and pause button whenever you need a moment.

    You don't have to rush. A pause gives your audience time to think, and gives you time to find your next idea.

    When you reach the end, the final lines stay in view. Use the player's rewind control to go back, or return to Cod to restart or edit your script.

    That's it. Your next story starts here.
    """

  var totalPomodoroDuration: TimeInterval {
    focusDuration * Double(rounds) + breakDuration * Double(max(0, rounds - 1))
  }

  func validate() throws {
    switch kind {
    case .countdown:
      guard duration.isFinite, (1...86_400).contains(duration) else {
        throw FloatingToolError.invalidDuration
      }
    case .pomodoro:
      guard focusDuration.isFinite, breakDuration.isFinite,
        (60...10_800).contains(focusDuration), (60...3_600).contains(breakDuration),
        (1...12).contains(rounds)
      else { throw FloatingToolError.invalidDuration }
    case .clock:
      guard TimeZone(identifier: timeZoneIdentifier) != nil else {
        throw FloatingToolError.invalidTimeZone
      }
      guard clockLocationSize.isFinite, (20...100).contains(clockLocationSize),
        clockTimeSize.isFinite, (40...180).contains(clockTimeSize),
        clockDateSize.isFinite, (20...100).contains(clockDateSize)
      else { throw FloatingToolError.invalidStyle }
    case .document:
      guard duration.isFinite, (1...7_200).contains(duration) else { throw FloatingToolError.invalidDuration }
    case .teleprompter:
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FloatingTextError.empty
      }
      guard text.count <= 20_000 else { throw FloatingToolError.scriptTooLong }
      guard scrollSpeed.isFinite, (10...120).contains(scrollSpeed), fontSize.isFinite,
        (28...72).contains(fontSize), wordsPerMinute.isFinite, (60...500).contains(wordsPerMinute),
        (1...8).contains(wordsAtATime), (1...60).contains(prompterCountdownSeconds),
        sideMargin.isFinite, (32...160).contains(sideMargin),
        lineSpacing.isFinite, (0...40).contains(lineSpacing),
        targetReadingDuration.map({ $0.isFinite && (15...3_600).contains($0) }) ?? true
      else { throw FloatingToolError.invalidStyle }
    case .stopwatch: break
    }
  }

  func snapshot(elapsed: TimeInterval, date: Date) -> FloatingToolSnapshot {
    let elapsed = max(0, elapsed)
    switch kind {
    case .countdown:
      let remaining = max(0, duration - elapsed)
      return .init(
        title: remaining == 0 ? "Finished" : "Timer", value: Self.time(remaining, roundingUp: true),
        detail: "Countdown", progress: min(1, elapsed / max(1, duration)),
        isFinished: remaining == 0)
    case .stopwatch:
      return .init(
        title: "Stopwatch", value: Self.time(elapsed, hundredths: showsHundredths),
        detail: "Elapsed time")
    case .clock:
      let formatter = DateFormatter()
      formatter.locale = .autoupdatingCurrent
      formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
      formatter.dateFormat = uses24HourClock ? "HH:mm:ss" : "h:mm:ss a"
      let value = formatter.string(from: date)
      formatter.dateFormat = "EEE, MMM d"
      let zone =
        timeZoneIdentifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(
          of: "_", with: " ")
        ?? timeZoneIdentifier
      let abbreviation = TimeZone(identifier: timeZoneIdentifier)?.abbreviation(for: date)
      let location =
        showsClockTimeZone && abbreviation?.isEmpty == false
        ? "\(zone) · \(abbreviation!)" : zone
      return .init(
        title: showsClockLocation ? location : "", value: value,
        detail: showsClockDate ? formatter.string(from: date) : "")
    case .pomodoro:
      if elapsed >= totalPomodoroDuration {
        return .init(
          title: "Finished", value: "Well done", detail: "\(rounds) focus sessions complete",
          progress: 1,
          isFinished: true)
      }
      let cycle = max(1, focusDuration + breakDuration)
      let round = min(rounds - 1, Int(elapsed / cycle))
      let position = elapsed - Double(round) * cycle
      let resting = position >= focusDuration
      let phaseDuration = resting ? breakDuration : focusDuration
      let phaseElapsed = resting ? position - focusDuration : position
      return .init(
        title: resting ? "Break" : "Focus",
        value: Self.time(phaseDuration - phaseElapsed, roundingUp: true),
        detail: "Session \(round + 1) of \(rounds)",
        progress: min(1, phaseElapsed / max(1, phaseDuration)))
    case .document:
      return .init(title: "Scrolling Reference", value: text, detail: "Auto-scroll")
    case .teleprompter:
      return .init(
        title: "Teleprompter", value: text,
        detail: prompterMode == .scroll ? "Auto-scroll" : "Words")
    }
  }

  static func time(_ seconds: TimeInterval, roundingUp: Bool = false, hundredths: Bool = false)
    -> String
  {
    let finite = seconds.isFinite ? seconds : 0
    let total = Int(min(359_999_999, max(0, roundingUp ? ceil(finite) : floor(finite))))
    let whole =
      total >= 3_600
      ? String(format: "%02d:%02d:%02d", total / 3_600, total / 60 % 60, total % 60)
      : String(format: "%02d:%02d", total / 60, total % 60)
    guard hundredths else { return whole }
    let fraction = Int((min(359_999_999, max(0, finite)) * 100).rounded(.down)) % 100
    return whole + String(format: ".%02d", fraction)
  }
}

struct FloatingToolSnapshot: Equatable {
  var title: String
  var value: String
  var detail: String
  var progress: Double? = nil
  var isFinished = false
}

enum FloatingToolError: LocalizedError {
  case invalidDuration, invalidTimeZone, invalidStyle, scriptTooLong, renderFailed
  var errorDescription: String? {
    switch self {
    case .invalidDuration: return "Choose a valid duration and number of sessions."
    case .invalidTimeZone: return "Choose a valid time zone."
    case .invalidStyle: return "Choose a supported text size and scrolling speed."
    case .scriptTooLong: return "Use a script of 20,000 characters or fewer."
    case .renderFailed: return "Cod couldn't create a video frame for this tool."
    }
  }
}

/// Pure timing state: never count timer callbacks. Missing a callback or
/// backgrounding can't make a countdown or Pomodoro run slowly.
struct FloatingToolTimeline {
  private(set) var accumulated: TimeInterval = 0
  private(set) var resumedAt: TimeInterval?
  var isPlaying: Bool { resumedAt != nil }

  func elapsed(at uptime: TimeInterval) -> TimeInterval {
    accumulated + (resumedAt.map { max(0, uptime - $0) } ?? 0)
  }

  mutating func resume(at uptime: TimeInterval) {
    if resumedAt == nil { resumedAt = uptime }
  }

  mutating func pause(at uptime: TimeInterval) {
    guard resumedAt != nil else { return }
    accumulated = elapsed(at: uptime)
    resumedAt = nil
  }

  mutating func reset(at uptime: TimeInterval) {
    accumulated = 0
    if isPlaying { resumedAt = uptime }
  }

  mutating func synchronize(elapsed: TimeInterval, at uptime: TimeInterval, playing: Bool) {
    accumulated = max(0, elapsed)
    resumedAt = playing ? uptime : nil
  }
}

/// ContinuousClock includes device sleep, unlike systemUptime. A process-local
/// origin is sufficient: live sessions aren't restored across app termination.
enum FloatingElapsedClock {
  private static let origin = ContinuousClock.now
  static func now() -> TimeInterval {
    let interval = origin.duration(to: .now).components
    return Double(interval.seconds) + Double(interval.attoseconds) / 1_000_000_000_000_000_000
  }
}

@MainActor
final class FloatingToolSession: ObservableObject, Identifiable {
  let id = UUID()
  let document: ScrollingReference?
  var title: String { document?.name ?? configuration.kind.title }
  @Published private(set) var configuration: FloatingToolConfiguration
  lazy var scriptLayout: FloatingToolRenderer.ScriptLayout? =
    configuration.kind == .teleprompter ? .init(configuration) : nil
  var playbackDuration: TimeInterval? {
    if let document { return document.duration(speed: configuration.scrollSpeed) }
    guard configuration.supportsSeeking, let scriptLayout else { return nil }
    return configuration.prompterStartDelay + scriptLayout.duration(configuration)
  }
  func renderedFrame() -> UIImage {
    if let document { return document.frame(elapsed: elapsed, speed: configuration.scrollSpeed) }
    return FloatingToolRenderer.render(configuration: configuration, elapsed: elapsed, date: displayDate, scriptLayout: scriptLayout)
  }
  @Published private(set) var timeline = FloatingToolTimeline()
  @Published private(set) var alarmDate: Date?
  @Published private(set) var alarmError: String?
  @Published private(set) var isUpdatingAlarm = false
  private var pausedDate: Date
  private let now: () -> Date
  private let uptime: () -> TimeInterval
  var onPlaybackChange: (() -> Void)?
  private let alarmScheduler: any FloatingTimerAlarmScheduling
  private var alarmTask: Task<Void, Never>?
  private var alarmRevision = 0

  init(
    configuration: FloatingToolConfiguration,
    document: ScrollingReference? = nil,
    alarmScheduler: (any FloatingTimerAlarmScheduling)? = nil,
    now: @escaping () -> Date = Date.init,
    uptime: @escaping () -> TimeInterval = FloatingElapsedClock.now
  ) {
    self.configuration = configuration
    self.document = document
    self.alarmScheduler = alarmScheduler ?? FloatingTimerAlarms.shared
    self.now = now
    self.uptime = uptime
    pausedDate = now()
    if alarmScheduler == nil, configuration.hasTimerAlarm { FloatingTimerAlarms.shared.track(self) }
  }
  var isPlaying: Bool { timeline.isPlaying }
  var elapsed: TimeInterval { timeline.elapsed(at: uptime()) }
  var displayDate: Date { configuration.kind == .clock || isPlaying ? now() : pausedDate }
  var snapshot: FloatingToolSnapshot {
    var value = configuration.snapshot(elapsed: elapsed, date: displayDate)
    if let playbackDuration { value.isFinished = elapsed >= playbackDuration }
    return value
  }

  /// Appearance changes don't restart, seek or reschedule a running tool.
  @discardableResult
  func updateSystemAppearance(_ style: UIUserInterfaceStyle) -> Bool {
    guard configuration.palette == .system, configuration.interfaceStyle != style,
      style == .light || style == .dark else { return false }
    configuration.interfaceStyle = style
    scriptLayout = configuration.kind == .teleprompter ? .init(configuration) : nil
    return true
  }

  func resume() {
    guard !isPlaying, !isUpdatingAlarm else { return }
    if snapshot.isFinished {
      guard configuration.supportsSeeking else { return }
      timeline.reset(at: uptime())
    }
    if !configuration.hasTimerAlarm { timeline.resume(at: uptime()) }
    onPlaybackChange?()
    updateAlarm(playing: true)
  }
  func pause() {
    pausedDate = now()
    timeline.pause(at: uptime())
    onPlaybackChange?()
    updateAlarm(playing: false)
  }
  func reset() {
    let playing = isPlaying
    timeline.reset(at: uptime())
    if configuration.hasTimerAlarm { timeline.pause(at: uptime()) }
    pausedDate = now()
    onPlaybackChange?()
    updateAlarm(playing: playing)
  }

  /// Finishing the visual countdown must not cancel its system alarm just
  /// as it starts ringing. An explicit Pause/Restart still updates the alarm.
  func complete() {
    if let playbackDuration {
      timeline.synchronize(elapsed: playbackDuration, at: uptime(), playing: false)
    } else {
      timeline.pause(at: uptime())
    }
    onPlaybackChange?()
  }

  /// Only scripted media has a replayable timeline. Seeking a stopwatch or
  /// alarm would change its meaning or detach the pixels from a real alarm.
  func seek(to seconds: TimeInterval) {
    guard let duration = playbackDuration, seconds.isFinite else { return }
    let target = min(duration, max(0, seconds))
    let playing = isPlaying && target < duration
    timeline.synchronize(elapsed: target, at: uptime(), playing: playing)
    onPlaybackChange?()
  }

  func skip(by interval: TimeInterval) {
    guard interval.isFinite else { return }
    seek(to: elapsed + interval)
  }

  func setPlayingFromPiP(_ playing: Bool) {
    // System audio interruptions and completion aren't a user cancel.
    if configuration.hasTimerAlarm, !playing,
      snapshot.isFinished || FloatingTimerAlarms.shared.isAlerting(id: id)
    {
      alarmDidAlert()
      return
    }
    guard !isUpdatingAlarm else { return }
    if playing { resume() } else { pause() }
  }

  func alarmDidAlert() {
    guard configuration.hasTimerAlarm else { return }
    timeline.synchronize(elapsed: configuration.duration, at: uptime(), playing: false)
    onPlaybackChange?()
  }

  func alarmWasDismissed() {
    guard !isUpdatingAlarm else { return }
    timeline.pause(at: uptime())
    alarmDate = nil
    onPlaybackChange?()
  }

  func cancelAlarm() { pause() }

  func pictureInPictureDidClose(preservingTimer: Bool = false) {
    if configuration.kind == .countdown, preservingTimer || configuration.keepTimerRunningOnClose {
      return
    }
    pause()
  }

  /// Reconcile a provisional date with AlarmKit's actual countdown, even
  /// when the Live Activity appeared after schedule() returned.
  func alarmDeadlineDidChange(_ date: Date) {
    guard configuration.hasTimerAlarm, alarmDate != nil, !isUpdatingAlarm else { return }
    alarmDate = date
    let elapsed = max(0, configuration.duration - date.timeIntervalSince(now()))
    timeline.synchronize(elapsed: elapsed, at: uptime(), playing: elapsed < configuration.duration)
    onPlaybackChange?()
  }

  func waitForAlarmUpdate() async { await alarmTask?.value }

  private func updateAlarm(playing: Bool) {
    guard configuration.hasTimerAlarm else { return }
    alarmRevision += 1
    let revision = alarmRevision
    let previous = alarmTask
    let remaining = max(0, configuration.duration - elapsed)
    isUpdatingAlarm = true
    alarmTask = Task { @MainActor [weak self] in
      // Serialize async schedule/cancel calls. A late schedule must never
      // undo a newer pause, restart, or cancellation.
      await previous?.value
      guard let self, revision == self.alarmRevision else { return }
      do {
        let date: Date?
        if playing {
          date = try await self.alarmScheduler.schedule(id: self.id, after: remaining)
        } else {
          try self.alarmScheduler.cancel(id: self.id)
          date = nil
        }
        guard revision == self.alarmRevision else { return }
        self.alarmDate = date
        self.alarmError = nil
        if let date {
          let elapsed = max(0, self.configuration.duration - date.timeIntervalSince(self.now()))
          self.timeline.synchronize(elapsed: elapsed, at: self.uptime(), playing: true)
        }
        self.onPlaybackChange?()
      } catch {
        guard revision == self.alarmRevision else { return }
        self.alarmError = error.localizedDescription
        self.timeline.pause(at: self.uptime())
        self.onPlaybackChange?()
      }
      if revision == self.alarmRevision { self.isUpdatingAlarm = false }
    }
  }
}
