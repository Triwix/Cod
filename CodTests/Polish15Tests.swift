import UIKit
import XCTest

@testable import Cod

final class Polish15Tests: XCTestCase {
  func testSystemPaletteIsDefaultAndResolvesExplicitlyForBothAppearances() throws {
    XCTAssertEqual(FloatingToolConfiguration(kind: .clock).palette, .system)
    XCTAssertEqual(FloatingPalette.allCases, [.system, .dark, .light, .yellow])
    XCTAssertEqual(FloatingPalette.system.colors(for: .light), FloatingPalette.light.colors(for: .dark))
    XCTAssertEqual(FloatingPalette.system.colors(for: .dark), FloatingPalette.dark.colors(for: .light))
    XCTAssertNotEqual(FloatingPalette.system.colors(for: .light), FloatingPalette.system.colors(for: .dark))
    for value in ["dark", "light", "yellow", "system"] {
      let decoded = try JSONDecoder().decode(FloatingPalette.self, from: Data("\"\(value)\"".utf8))
      XCTAssertEqual(decoded.rawValue, value)
    }
  }

  func testSystemRespectsCustomColorsAndGrayExamplesInBothAppearances() {
    var configuration = FloatingToolConfiguration(kind: .teleprompter)
    configuration.usesSampleText = true
    for style in [UIUserInterfaceStyle.light, .dark] {
      configuration.interfaceStyle = style
      let base = FloatingPalette.system.colors(for: style)
      XCTAssertEqual(configuration.colors, FloatingText.sampleColors(base))
      let custom = FloatingColors(background: .purple, foreground: .cyan)
      configuration.customColors = custom
      XCTAssertEqual(configuration.colors, FloatingText.sampleColors(custom))
      configuration.customColors = nil
    }
  }

  func testClockSizeResetRestoresAllLinesAndNothingElse() {
    var configuration = FloatingToolConfiguration(kind: .clock, palette: .yellow)
    XCTAssertFalse(configuration.hasCustomClockSizes)
    configuration.clockLocationSize = 88
    configuration.clockTimeSize = 160
    configuration.clockDateSize = 82
    configuration.showsClockLocation = false
    configuration.showsClockDate = false
    XCTAssertTrue(configuration.hasCustomClockSizes)
    configuration.resetClockSizes()
    XCTAssertFalse(configuration.hasCustomClockSizes)
    XCTAssertEqual(configuration.clockLocationSize, 44)
    XCTAssertEqual(configuration.clockTimeSize, 100)
    XCTAssertEqual(configuration.clockDateSize, 36)
    XCTAssertEqual(configuration.palette, .yellow)
    XCTAssertFalse(configuration.showsClockLocation)
    XCTAssertFalse(configuration.showsClockDate)
  }

  @MainActor func testSystemAppearanceDoesNotChangePlaybackPositionOrDuration() throws {
    var now = 0.0
    var configuration = FloatingToolConfiguration(
      kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
    configuration.interfaceStyle = .light
    let session = FloatingToolSession(configuration: configuration, uptime: { now })
    let duration = try XCTUnwrap(session.playbackDuration)
    let oldLayout = try XCTUnwrap(session.scriptLayout)
    session.resume(); now = 12
    XCTAssertTrue(session.updateSystemAppearance(.dark))
    XCTAssertEqual(session.elapsed, 12)
    XCTAssertTrue(session.isPlaying)
    XCTAssertEqual(try XCTUnwrap(session.playbackDuration), duration, accuracy: 0.001)
    XCTAssertNotEqual(oldLayout.text, session.scriptLayout?.text)
    XCTAssertFalse(session.updateSystemAppearance(.dark))
    session.pause()
    XCTAssertTrue(session.updateSystemAppearance(.light))
    XCTAssertFalse(session.isPlaying)
    XCTAssertEqual(session.elapsed, 12)
    let fixed = FloatingToolSession(configuration: .init(kind: .clock, palette: .yellow))
    XCTAssertFalse(fixed.updateSystemAppearance(.dark))
  }

  func testScrollingTargets60FPSWithoutSpeedingUpWordsOrTheTimeline() {
    var configuration = FloatingToolConfiguration(kind: .teleprompter)
    XCTAssertEqual(configuration.framesPerSecond, 60)
    XCTAssertNotEqual(configuration.frameKey(elapsed: 0, date: .now), configuration.frameKey(elapsed: 1 / 60.0, date: .now))
    configuration.prompterMode = .words
    XCTAssertEqual(configuration.framesPerSecond, 15)
    XCTAssertEqual(configuration.wordsPerMinute, 180)
    XCTAssertEqual(FloatingToolConfiguration(kind: .clock).framesPerSecond, 1)
  }

  func testFramePacingSubtractsRenderCostAndDropsLateCatchUpFrames() {
    var pacing = FloatingFramePacer(now: 0)
    var now = 0.0
    for _ in 0..<120 {
      now += pacing.nextDelay(now: now, framesPerSecond: 60)
      now += 0.004 // four milliseconds spent producing each frame
    }
    XCTAssertEqual(now, 2.004, accuracy: 0.0001)
    XCTAssertEqual(pacing.nextDelay(now: 100, framesPerSecond: 60), 0)
    XCTAssertEqual(pacing.nextDelay(now: 100, framesPerSecond: 60), 1 / 60.0, accuracy: 0.0001)
    XCTAssertEqual(pacing.nextDelay(now: 200, framesPerSecond: .nan), 0)
    XCTAssertEqual(pacing.nextDelay(now: 200, framesPerSecond: .nan), 1)
  }

  func testCachedScrollingUsesFractionalPositionsAndRetainsFinalText() {
    var configuration = FloatingToolConfiguration(kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
    configuration.prompterCountdownEnabled = false
    let layout = FloatingToolRenderer.ScriptLayout(configuration)
    func frame(_ elapsed: Double) -> Data? {
      FloatingToolRenderer.render(configuration: configuration, elapsed: elapsed, date: .distantPast, scriptLayout: layout).pngData()
    }
    XCTAssertGreaterThan(layout.travel, 0)
    XCTAssertNotEqual(frame(0), frame(1 / 60.0))
    XCTAssertNotEqual(frame(1 / 60.0), frame(2 / 60.0))
    XCTAssertEqual(frame(layout.duration(configuration)), frame(1_000))
  }

  func testCachedLongScriptRenderCost() {
    let text = String(repeating: "A long script stays smooth without laying out every line again.\n", count: 250)
    let configuration = FloatingToolConfiguration(kind: .teleprompter, text: text)
    let layout = FloatingToolRenderer.ScriptLayout(configuration)
    let started = ContinuousClock.now
    for index in 0..<60 {
      autoreleasepool {
        _ = FloatingToolRenderer.render(configuration: configuration, elapsed: 10 + Double(index) / 60, date: .now, scriptLayout: layout)
      }
    }
    print("Cod long-script 60-frame render cost: \(started.duration(to: .now))")
  }
}
