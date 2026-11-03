import SwiftUI

struct FloatingToolEditor: View {
  var savedReference: SavedReference?
  var originalImage: UIImage?
  private var restoresConfiguration = false
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @State private var configuration: FloatingToolConfiguration
  @AppStorage("cod.tools.timerDuration") private var savedDuration = 300
  @AppStorage("cod.tools.keepTimerRunningOnClose") private var keepTimerRunning = true
  @AppStorage("cod.tools.stopwatchHundredths") private var showsHundredths = false
  @AppStorage("cod.tools.clockLocation") private var clockLocation = true
  @AppStorage("cod.tools.clockZoneLabel") private var clockZoneLabel = true
  @AppStorage("cod.tools.clockDate") private var clockDate = true
  @AppStorage("cod.tools.clockLocationSize") private var clockLocationSize = 44.0
  @AppStorage("cod.tools.clockTimeSize") private var clockTimeSize = 100.0
  @AppStorage("cod.tools.clockDateSize") private var clockDateSize = 36.0
  @State private var focusMinutes = "25"
  @State private var breakMinutes = "5"
  @State private var focusSessions = "4"
  private enum PomodoroField: Hashable { case focus, rest, sessions }
  @FocusState private var focusedNumber: PomodoroField?
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.colorScheme) private var colorScheme
  @State private var session: FloatingToolSession?
  @State private var errorMessage: String?
  @State private var isStarting = false
  @State private var loadedDraft = false

  init(kind: FloatingToolKind) { _configuration = State(initialValue: .init(kind: kind)) }
  init(configuration: FloatingToolConfiguration, savedReference: SavedReference? = nil, originalImage: UIImage? = nil) {
    _configuration = State(initialValue: configuration)
    self.savedReference = savedReference; self.originalImage = originalImage
    restoresConfiguration = true
    _focusMinutes = State(initialValue: String(Int(configuration.focusDuration / 60)))
    _breakMinutes = State(initialValue: String(Int(configuration.breakDuration / 60)))
    _focusSessions = State(initialValue: String(configuration.rounds))
  }

  var body: some View {
    FloatingEditorLayout {
      if configuration.kind == .clock {
        TimelineView(.periodic(from: .now, by: 1)) { tick in preview(at: tick.date) }
      } else { preview(at: Date()) }
      Button {
        Task { await startFloating() }
      } label: {
        Label("Float \(configuration.kind.title)", systemImage: "pip.enter").frame(
          maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(CodActionStyle()).accessibilityIdentifier(
        "float-tool"
      )
      .disabled(
        isStarting || coordinator.isWorking
          || (try? preparedConfiguration.validate()) == nil
          || (configuration.kind == .countdown && duration.totalSeconds == 0)
          || (configuration.kind == .pomodoro && pomodoroValues == nil)
      )
      if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
    } settings: {
      if configuration.kind == .countdown {
        Section("Duration") {
          Menu("Quick duration") {
            ForEach([1, 5, 10, 15, 25, 30, 60], id: \.self) { minutes in
              Button("\(minutes) min") {
                savedDuration = minutes * 60
              }
            }
          }
          TimerDurationWheels(seconds: $savedDuration)
          if duration.totalSeconds == 0 {
            Text("Choose at least one second.").foregroundStyle(.secondary)
          }
        }
        Section {
          Toggle("Alarm when finished", isOn: $configuration.alarmWhenFinished)
            .disabled(!FloatingTimerAlarms.isAvailable)
            .accessibilityIdentifier("timer-alarm-enabled")
        } header: {
          Text("Sound")
        } footer: {
          Text(
            FloatingTimerAlarms.isAvailable
              ? "Uses Apple's alarm sound, including while locked or silenced. You'll be asked for permission when you start an alarm-enabled timer."
              : "Timer alarms require iOS 26 or later. This device can use the visual timer without a sound."
          )
        }
        Section {
          Toggle("Keep alarm running when PiP closes", isOn: $keepTimerRunning)
            .accessibilityIdentifier("timer-keep-running")
        } footer: {
          Text(
            keepTimerRunning
              ? "Closing PiP keeps an enabled alarm and its countdown running. This also keeps visual-only countdowns running on the Float screen until Cod quits."
              : "Closing PiP stops this timer and cancels its alarm. Returning to Cod with PiP's restore button doesn't cancel it. Locking may also close PiP, so keep this on for a background timer."
          )
        }
      }
      if configuration.kind == .stopwatch {
        Section {
          Toggle("Show hundredths", isOn: $showsHundredths)
            .accessibilityIdentifier("stopwatch-hundredths")
        } footer: {
          Text(
            "Shows fractional seconds, for example 00:12.34. This preference applies when you next float a stopwatch."
          )
        }
      }
      if configuration.kind == .pomodoro {
        Section {
          numberRow(
            "Focus (min)", input: $focusMinutes, range: PomodoroValues.focusRange, field: .focus,
            identifier: "pomodoro-focus")
          numberRow(
            "Break (min)", input: $breakMinutes, range: PomodoroValues.breakRange, field: .rest,
            identifier: "pomodoro-break")
          numberRow(
            "Sessions", input: $focusSessions, range: PomodoroValues.sessionRange, field: .sessions,
            identifier: "pomodoro-sessions")
          if pomodoroValues == nil {
            Text("Enter focus 1–180 minutes, break 1–60 minutes, and 1–12 sessions.")
              .foregroundStyle(.red).accessibilityIdentifier("pomodoro-validation")
          }
        } header: {
          Text("Focus and breaks")
        } footer: {
          Text(
            "Tap a number to type, or use − and +. Alternates focus and breaks, ending after the last focus session."
          )
        }
      }
      if configuration.kind == .clock {
        Section("Current Time") {
          NavigationLink {
            FloatingTimeZonePicker(selection: $configuration.timeZoneIdentifier)
          } label: {
            LabeledContent(
              "Time zone",
              value: configuration.timeZoneIdentifier.replacingOccurrences(of: "_", with: " "))
          }
          Toggle("24-hour time", isOn: $configuration.uses24HourClock)
          Toggle("Show location", isOn: $clockLocation).accessibilityIdentifier(
            "clock-show-location")
          if clockLocation {
            Toggle("Show time-zone abbreviation", isOn: $clockZoneLabel)
              .accessibilityIdentifier("clock-show-zone")
            Text(
              "Shown next to the location, such as Los Angeles · PDT. The abbreviation follows daylight saving time; some zones use a GMT offset."
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
          Toggle("Show date", isOn: $clockDate).accessibilityIdentifier("clock-show-date")
        }
        Section("Text sizes") {
          if clockLocation {
            clockSize("Location text size", value: $clockLocationSize, range: 20...100)
          }
          clockSize("Time text size", value: $clockTimeSize, range: 40...180)
          if clockDate { clockSize("Date text size", value: $clockDateSize, range: 20...100) }
          if preparedConfiguration.hasCustomClockSizes {
            Button("Reset sizes to preset") {
              var reset = preparedConfiguration
              reset.resetClockSizes()
              clockLocationSize = reset.clockLocationSize
              clockTimeSize = reset.clockTimeSize
              clockDateSize = reset.clockDateSize
            }
            .accessibilityIdentifier("clock-reset-sizes")
          }
        }
      }
      Section("Appearance") {
        FloatingAppearancePicker(
          palette: $configuration.palette, customColors: $configuration.customColors)
      }
      SavedReferenceSaveSection(name: savedReference?.name ?? "", id: savedReference?.id, original: originalImage) { name, id in
        SavedReference(id: id, name: name, detail: configuration.kind.title, tool: preparedConfiguration, originalFilename: savedReference?.originalFilename)
      }
      if let session {
        Section("Playback") {
          if session.configuration.kind != .clock {
            FloatingToolPlaybackControls(session: session, showsValue: true)
          }
          NavigationLink("Playback controls") { FloatingToolSessionView(session: session) }
        }
      }
      Section {
        Text(helpText)
      }
    }
    .navigationTitle(configuration.kind.title)
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        if configuration.kind == .pomodoro {
          Spacer()
          Button("Done") { focusedNumber = nil }
        }
      }
    }
    .task {
      if restoresConfiguration, !loadedDraft {
        loadedDraft = true
        if configuration.kind == .countdown {
          savedDuration = Int(configuration.duration)
          keepTimerRunning = configuration.keepTimerRunningOnClose
        }
        if configuration.kind == .stopwatch { showsHundredths = configuration.showsHundredths }
        if configuration.kind == .clock {
          clockLocation = configuration.showsClockLocation
          clockZoneLabel = configuration.showsClockTimeZone
          clockDate = configuration.showsClockDate
          clockLocationSize = configuration.clockLocationSize
          clockTimeSize = configuration.clockTimeSize
          clockDateSize = configuration.clockDateSize
        }
        return
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
    ) { notification in
      guard configuration.kind == .pomodoro,
        let field = notification.object as? UITextField,
        field.keyboardType == .numberPad,
        ["Focus (min)", "Break (min)", "Sessions"].contains(field.placeholder ?? "")
      else { return }
      // Numeric settings replace their current value on the first keystroke.
      // Restrict this documented UIKit notification to these three fields.
      DispatchQueue.main.async {
        guard field.isFirstResponder else { return }
        field.selectedTextRange = field.textRange(
          from: field.beginningOfDocument, to: field.endOfDocument)
      }
    }
  }

  @MainActor private func startFloating() async {
    isStarting = true
    defer { isStarting = false }
    do {
      let config = preparedConfiguration
      try config.validate()
      if config.hasTimerAlarm { try await FloatingTimerAlarms.shared.authorize() }
      let created = FloatingToolSession(configuration: config)
      session = created
      errorMessage = nil
      coordinator.floatTool(created)
    } catch { errorMessage = error.localizedDescription }
  }

  private func preview(at date: Date) -> some View {
    let config = preparedConfiguration
    return FloatingPreviewImage(
      image: FloatingToolRenderer.render(
        configuration: config,
        elapsed: 0, date: date),
      label: "Tool preview",
      value: config.kind == .clock ? config.snapshot(elapsed: 0, date: date).value : nil)
  }

  private var helpText: String {
    switch configuration.kind {
    case .clock:
      return
        "Shows the current time in your selected time zone. When you return, it reads the current system time rather than counting missed updates."
    case .countdown:
      return
        "With Alarm when finished off, this is a visual-only timer. An enabled alarm is delivered by iOS independently of PiP."
    default:
      return
        "A visual display, with no scheduled alarm. Closing PiP pauses this tool. Return here to pause, resume or restart."
    }
  }

  private var duration: TimerDuration { TimerDuration(savedDuration) }

  @ViewBuilder private func clockSize(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>
  ) -> some View {
    LabeledContent(title, value: "\(Int(value.wrappedValue))")
    Slider(value: value, in: range, step: 2).accessibilityLabel(title)
  }
  private var pomodoroValues: PomodoroValues? {
    PomodoroValues(focus: focusMinutes, rest: breakMinutes, sessions: focusSessions)
  }

  @ViewBuilder private func numberRow(
    _ title: String, input: Binding<String>, range: ClosedRange<Int>, field: PomodoroField,
    identifier: String
  ) -> some View {
    let controls = HStack {
      TextField(title, text: input)
        .keyboardType(.numberPad).submitLabel(.done)
        .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
        .frame(minWidth: 64, maxWidth: textSize.isAccessibilitySize ? 150 : 80)
        .focused($focusedNumber, equals: field)
        .onSubmit { focusedNumber = nil }
        .accessibilityLabel(title).accessibilityIdentifier(identifier)
      Stepper(
        "Adjust \(title)",
        value: Binding(
          get: { PomodoroValues.number(input.wrappedValue, in: range) ?? range.lowerBound },
          set: { input.wrappedValue = String($0) }), in: range
      )
      .labelsHidden().fixedSize()
    }
    if textSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
        controls
      }
    } else {
      HStack {
        Text(title)
        Spacer()
        controls
      }
    }
  }

  private var preparedConfiguration: FloatingToolConfiguration {
    var result = configuration
    result.interfaceStyle = colorScheme == .dark ? .dark : .light
    result.duration = Double(duration.totalSeconds)
    result.keepTimerRunningOnClose = keepTimerRunning
    result.showsHundredths = showsHundredths
    result.showsClockLocation = clockLocation
    result.showsClockTimeZone = clockZoneLabel
    result.showsClockDate = clockDate
    result.clockLocationSize = clockLocationSize
    result.clockTimeSize = clockTimeSize
    result.clockDateSize = clockDateSize
    result.usesSampleText = false
    result.focusDuration = Double((pomodoroValues?.focus ?? 25) * 60)
    result.breakDuration = Double((pomodoroValues?.rest ?? 5) * 60)
    result.rounds = pomodoroValues?.sessions ?? 4
    return result
  }
}

struct FloatingToolSessionView: View {
  @ObservedObject var session: FloatingToolSession
  @EnvironmentObject private var coordinator: CaptureCoordinator
  @EnvironmentObject private var pip: PiPPinController
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    FloatingEditorLayout {
      TimelineView(
        .animation(
          minimumInterval: 1 / session.configuration.framesPerSecond, paused: !session.isPlaying)
      ) { _ in
        FloatingPreviewImage(
          image: session.renderedFrame(), label: "Live tool preview")
      }
      if pip.toolSession?.id != session.id {
        Button {
          coordinator.floatTool(session)
        } label: {
          Label("Float Again", systemImage: "pip.enter").frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(Color.codActionBackground).disabled(
          coordinator.isWorking)
      } else {
        Button("Stop Floating", role: .destructive) { pip.stop() }
          .buttonStyle(.bordered).frame(minHeight: 44)
      }
    } settings: {
      Section {
        if session.configuration.kind != .clock { FloatingToolPlaybackControls(session: session) }
        Text(
          session.configuration.kind == .clock
            ? "Shows the current time in your selected time zone. Float Again opens a fresh view of the current time."
            : "Native PiP play/pause controls remain available. You can also pause, resume or restart here."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle(session.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
    .background(Color(.systemGroupedBackground))
    .onChange(of: colorScheme, initial: true) { _, scheme in
      session.updateSystemAppearance(scheme == .dark ? .dark : .light)
    }
  }

}

struct FloatingToolPlaybackControls: View {
  @ObservedObject var session: FloatingToolSession
  var showsValue = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let duration = session.playbackDuration {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
          LabeledContent(
            "Position",
            value:
              "\(FloatingToolConfiguration.time(session.elapsed)) / \(FloatingToolConfiguration.time(duration, roundingUp: true))"
          )
          .accessibilityIdentifier("prompter-position")
          .accessibilityValue(String(Int(session.elapsed)))
          LabeledContent(
            "Playback remaining",
            value: FloatingToolConfiguration.time(max(0, duration - session.elapsed), roundingUp: true)
          )
          .accessibilityIdentifier("prompter-remaining")
          Slider(
            value: Binding(get: { min(duration, session.elapsed) }, set: { session.seek(to: $0) }),
            in: 0...duration
          )
          .accessibilityLabel("Script position")
        }
        HStack {
          Button("Back 10 seconds", systemImage: "gobackward.10") { session.skip(by: -10) }
            .accessibilityIdentifier("prompter-rewind")
          Spacer()
          Button("Forward 10 seconds", systemImage: "goforward.10") { session.skip(by: 10) }
            .accessibilityIdentifier("prompter-forward")
        }.buttonStyle(.bordered)
      }
      if showsValue, session.configuration.kind != .teleprompter {
        TimelineView(
          .animation(
            minimumInterval: 1 / session.configuration.framesPerSecond, paused: !session.isPlaying)
        ) { _ in
          Text(session.snapshot.value).font(.title2.monospacedDigit())
            .accessibilityLabel("Current value: \(session.snapshot.value)")
        }
      }
      HStack {
        Button(session.isPlaying ? "Pause" : "Resume") {
          if session.isPlaying { session.pause() } else { session.resume() }
        }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("tool-play-pause")
        Button("Restart") { session.reset() }.buttonStyle(.bordered).frame(minHeight: 44)
      }
      .disabled(session.isUpdatingAlarm)
      if session.configuration.hasTimerAlarm {
        if let error = session.alarmError {
          Text("Couldn't update alarm: \(error) Check Timer alarms on the Float screen.")
            .foregroundStyle(
              .red)
        } else if session.isUpdatingAlarm {
          ProgressView("Updating alarm…")
        } else if let date = session.alarmDate {
          Text("Alarm: \(date.formatted(date: .omitted, time: .standard))").font(.footnote)
        } else {
          Text("Alarm paused").font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct FloatingTimeZonePicker: View {
  @Binding var selection: String
  @State private var query = ""
  @Environment(\.dismiss) private var dismiss
  private var zones: [String] {
    TimeZone.knownTimeZoneIdentifiers.filter {
      query.isEmpty
        || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    List(zones, id: \.self) { identifier in
      Button {
        selection = identifier
        dismiss()
      } label: {
        HStack {
          Text(identifier.replacingOccurrences(of: "_", with: " "))
          Spacer()
          if selection == identifier { Image(systemName: "checkmark") }
        }
      }
    }
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search time zones")
    .navigationTitle("Time Zone")
  }
}
