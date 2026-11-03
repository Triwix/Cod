import SwiftUI

struct TeleprompterOptions: View {
  @Binding var configuration: FloatingToolConfiguration
  var body: some View {
    Section("Presentation") {
      Picker("Presentation", selection: $configuration.prompterMode) {
        ForEach(TeleprompterMode.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented).accessibilityIdentifier("prompter-mode")
      if configuration.prompterMode == .words {
        Stepper(
          "Words at a time: \(configuration.wordsAtATime)", value: $configuration.wordsAtATime,
          in: 1...8
        )
        .accessibilityIdentifier("prompter-word-count")
        if configuration.targetReadingDuration == nil {
          LabeledContent("Reading speed", value: "\(Int(configuration.wordsPerMinute)) words/min")
          Slider(value: $configuration.wordsPerMinute, in: 60...500, step: 10).accessibilityLabel(
            "Words per minute")
        }
      } else if configuration.targetReadingDuration == nil {
        LabeledContent("Scroll speed", value: "\(Int(configuration.scrollSpeed))")
        Slider(value: $configuration.scrollSpeed, in: 10...120, step: 2).accessibilityLabel(
          "Scroll speed")
      }
    }
    Section("Reading layout") {
      if configuration.prompterMode == .scroll {
        Toggle("Reading guide", isOn: $configuration.readingGuide).accessibilityIdentifier(
          "prompter-reading-guide")
      }
      LabeledContent("Side margins", value: "\(Int(configuration.sideMargin))")
      Slider(value: $configuration.sideMargin, in: 32...160, step: 8).accessibilityLabel(
        "Side margins")
      if configuration.prompterMode == .scroll {
        LabeledContent("Line spacing", value: "\(Int(configuration.lineSpacing))")
        Slider(value: $configuration.lineSpacing, in: 0...40, step: 2).accessibilityLabel(
          "Line spacing")
      }
      Toggle(
        "Finish in a set time",
        isOn: Binding(
          get: { configuration.targetReadingDuration != nil },
          set: { configuration.targetReadingDuration = $0 ? 120 : nil }
        )
      ).accessibilityIdentifier("prompter-timed-reading")
      if configuration.targetReadingDuration != nil {
        TimerDurationWheels(
          seconds: Binding(
            get: { Int(configuration.targetReadingDuration ?? 120) },
            set: { configuration.targetReadingDuration = Double($0) }))
        if !(15...3_600).contains(configuration.targetReadingDuration ?? 0) {
          Text("Choose 15 seconds to 1 hour.").foregroundStyle(.red)
        }
        Text(
          "Script time excludes the starting countdown. This sets playback pace, not a guaranteed speaking time."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
    Section {
      Toggle("Countdown before starting", isOn: $configuration.prompterCountdownEnabled)
        .accessibilityIdentifier("prompter-countdown")
      if configuration.prompterCountdownEnabled {
        Stepper(
          "Start after \(configuration.prompterCountdownSeconds) seconds",
          value: $configuration.prompterCountdownSeconds, in: 1...60
        )
        .accessibilityIdentifier("prompter-delay")
      }
      if configuration.text.count <= 20_000 {
        Text(
          "Duration: \(FloatingToolConfiguration.time(configuration.prompterStartDelay + FloatingToolRenderer.ScriptLayout(configuration).duration(configuration), roundingUp: true))"
        )
        .accessibilityIdentifier("prompter-duration")
      }
    } header: {
      Text("Start & playback")
    } footer: {
      Text(
        "The countdown starts when PiP opens. Pause and seek with the player's available controls or Playback controls in Cod. The final text stays visible. This doesn't record video."
      )
    }
  }
}

struct ReferenceScrollOptions: View {
  @Binding var speed: Double
  @Binding var position: Double
  let reference: ScrollingReference?
  var body: some View {
    Section("Scrolling") {
      LabeledContent("Speed", value: "\(Int(speed))")
      Slider(value: $speed, in: 10...120, step: 2).accessibilityLabel("Reference scroll speed")
      if let reference {
        Text(
          "Duration: \(FloatingToolConfiguration.time(reference.duration(speed: speed), roundingUp: true))"
        )
      }
      LabeledContent("Preview position", value: "\(Int(position * 100))%")
      Slider(value: $position, in: 0...1).accessibilityLabel("Reference preview position")
      Text(
        "Playback starts at the top. Pause or seek with PiP's available controls or return to Cod. The final region stays visible."
      )
      .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
