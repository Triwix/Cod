import AVFoundation
import UIKit
import XCTest

@testable import Cod

final class Polish12Tests: XCTestCase {
  func testTypedPomodoroValuesValidateWithoutRequiringKeyboardCommit() {
    let input = PomodoroValues(focus: "125", rest: " 17 ", sessions: "9")
    XCTAssertEqual(input?.focus, 125)
    XCTAssertEqual(input?.rest, 17)
    XCTAssertEqual(input?.sessions, 9)
    XCTAssertNil(PomodoroValues(focus: "", rest: "5", sessions: "4"))
    XCTAssertNil(PomodoroValues(focus: "181", rest: "5", sessions: "4"))
    XCTAssertNil(PomodoroValues(focus: "25", rest: "61", sessions: "4"))
    XCTAssertNil(PomodoroValues(focus: "25", rest: "5", sessions: "0"))
    XCTAssertNil(PomodoroValues(focus: "25", rest: "5", sessions: "13"))
    XCTAssertNil(PomodoroValues(focus: "2.5", rest: "5", sessions: "4"))
    XCTAssertNil(PomodoroValues(focus: String(repeating: "9", count: 50), rest: "5", sessions: "4"))
  }

  func testPomodoroBoundaryInputsProduceValidConfigurations() throws {
    let values = try XCTUnwrap(PomodoroValues(focus: "180", rest: "60", sessions: "12"))
    var config = FloatingToolConfiguration(kind: .pomodoro)
    config.focusDuration = Double(values.focus * 60)
    config.breakDuration = Double(values.rest * 60)
    config.rounds = values.sessions
    XCTAssertNoThrow(try config.validate())
    XCTAssertEqual(config.snapshot(elapsed: 0, date: .distantPast).value, "03:00:00")
    XCTAssertEqual(config.snapshot(elapsed: 0, date: .distantPast).detail, "Session 1 of 12")
  }

  func testPreviewMaskUsesActualFittedImageBoundsForAllTextShapes() {
    let bounds = CGSize(width: 680, height: 180)
    XCTAssertEqual(
      FloatingPreviewImage.fittedSize(CGSize(width: 900, height: 240), within: bounds),
      CGSize(width: 675, height: 180))
    XCTAssertEqual(
      FloatingPreviewImage.fittedSize(CGSize(width: 900, height: 900), within: bounds),
      CGSize(width: 180, height: 180))
    XCTAssertEqual(
      FloatingPreviewImage.fittedSize(CGSize(width: 960, height: 540), within: bounds),
      CGSize(width: 320, height: 180))
    XCTAssertEqual(FloatingPreviewImage.fittedSize(.zero, within: bounds), .zero)
  }

  @MainActor func testRealVideoRepeatsByDefaultThenStopsAtTheEndWhenDisabled() async throws {
    let (playback, source) = try await makePlayback()
    defer {
      playback.stop()
      try? FileManager.default.removeItem(at: source)
    }
    XCTAssertTrue(FloatingVideoPlayback.defaultRepeats)
    XCTAssertTrue(playback.repeats)
    XCTAssertTrue(playback.player.isMuted)
    let loop = expectation(description: "Real item reaches its end and repeats")
    playback.onRepeat = { _ in loop.fulfill() }
    playback.activate()
    await fulfillment(of: [loop], timeout: 10)
    XCTAssertEqual(playback.completedLoops, 1)
    playback.setRepeats(false)
    playback.onRepeat = nil
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while playback.player.currentTime().seconds < playback.reference.duration - 0.05,
      ContinuousClock.now < deadline
    {
      try await Task.sleep(for: .milliseconds(50))
    }
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(playback.completedLoops, 1)
    XCTAssertEqual(playback.player.rate, 0)
    XCTAssertGreaterThanOrEqual(
      playback.player.currentTime().seconds, playback.reference.duration - 0.1)
  }

  @MainActor func testRepeatToggleDoesNotResumeAPausedVideoAndTeardownCannotLoop() async throws {
    let (playback, source) = try await makePlayback()
    defer {
      playback.stop()
      try? FileManager.default.removeItem(at: source)
    }
    playback.activate()
    playback.player.pause()
    playback.setRepeats(false)
    playback.setRepeats(true)
    XCTAssertEqual(playback.player.rate, 0)
    playback.stop()
    NotificationCenter.default.post(
      name: .AVPlayerItemDidPlayToEndTime, object: playback.player.currentItem)
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(playback.completedLoops, 0)
    XCTAssertEqual(playback.player.rate, 0)
  }

  @MainActor private func makePlayback() async throws -> (FloatingVideoPlayback, URL) {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    }
    let source = try await FloatingClip.make(from: image)
    let reference = try await VideoReference.copy(from: source)
    return (FloatingVideoPlayback(reference: reference), source)
  }
}
