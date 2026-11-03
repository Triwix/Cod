import AVFoundation
import AVKit
import UIKit
import XCTest

@testable import Cod

final class Polish14Tests: XCTestCase {
  @MainActor func testOpaqueToolFramesKeepTheirAlphaInDirectPlaybackBuffers() throws {
    let configuration = FloatingToolConfiguration(kind: .clock)
    let image = FloatingToolRenderer.render(configuration: configuration, elapsed: 0, date: .now)
    let pixels = try XCTUnwrap(image.pixelBuffer())
    XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixels), kCVPixelFormatType_32BGRA)
    CVPixelBufferLockBaseAddress(pixels, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
    for y in stride(from: 0, to: CVPixelBufferGetHeight(pixels), by: 17) {
      for x in stride(from: 0, to: CVPixelBufferGetWidth(pixels), by: 17) {
        XCTAssertEqual(base[y * CVPixelBufferGetBytesPerRow(pixels) + x * 4 + 3], 255)
      }
    }
  }
  @MainActor func testFiniteFramesKeepTheirMediaTiming() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { _ in }
    let position = CMTime(seconds: 10, preferredTimescale: 600)
    let duration = CMTime(seconds: 1 / 15.0, preferredTimescale: 600)
    let sample = try LiveFloatSource.sampleBuffer(
      image: image, at: position, duration: duration)
    XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample), position)
    XCTAssertEqual(CMSampleBufferGetDuration(sample), duration)
  }
  func testPrompterCountdownDefaultsAndValidation() throws {
    var configuration = FloatingToolConfiguration(kind: .teleprompter, text: "One two three")
    XCTAssertTrue(configuration.prompterCountdownEnabled)
    XCTAssertEqual(configuration.prompterStartDelay, 3)
    XCTAssertTrue(configuration.supportsSeeking)
    XCTAssertNoThrow(try configuration.validate())
    configuration.prompterCountdownSeconds = 8
    XCTAssertEqual(configuration.prompterStartDelay, 8)
    configuration.prompterCountdownEnabled = false
    XCTAssertEqual(configuration.prompterStartDelay, 0)
    configuration.prompterCountdownSeconds = 61
    XCTAssertThrowsError(try configuration.validate())
    configuration.prompterCountdownSeconds = 0
    XCTAssertThrowsError(try configuration.validate())
  }

  func testCountdownFramesAreDistinctAndScriptStartsAfterDelay() {
    var configuration = FloatingToolConfiguration(kind: .teleprompter, text: "First second third")
    configuration.prompterMode = .words
    configuration.wordsPerMinute = 60
    func frame(_ time: Double) -> Data? {
      FloatingToolRenderer.render(configuration: configuration, elapsed: time, date: .distantPast)
        .pngData()
    }
    XCTAssertNotEqual(frame(0), frame(1))
    XCTAssertNotEqual(frame(1), frame(2))
    let firstWord = frame(3)
    let secondWord = frame(4)
    let lastWord = frame(5)
    XCTAssertNotEqual(firstWord, secondWord)
    XCTAssertEqual(lastWord, frame(50))
    configuration.prompterCountdownEnabled = false
    XCTAssertEqual(frame(0), firstWord)
  }

  @MainActor func testFinitePrompterDurationSeekClampingPauseAndReplay() {
    var now = 0.0
    var configuration = FloatingToolConfiguration(
      kind: .teleprompter, text: Array(repeating: "Word", count: 40).joined(separator: " "))
    configuration.prompterMode = .words
    configuration.wordsPerMinute = 60
    let session = FloatingToolSession(configuration: configuration, uptime: { now })
    XCTAssertEqual(session.playbackDuration, 43)
    session.resume()
    now = 20
    session.skip(by: -10)
    XCTAssertEqual(session.elapsed, 10)
    XCTAssertTrue(session.isPlaying)
    session.pause()
    session.skip(by: 15)
    XCTAssertEqual(session.elapsed, 25)
    XCTAssertFalse(session.isPlaying, "Seeking paused content must not start playback")
    session.seek(to: -100)
    XCTAssertEqual(session.elapsed, 0)
    session.seek(to: .infinity)
    XCTAssertEqual(session.elapsed, 0)
    session.seek(to: 999)
    XCTAssertEqual(session.elapsed, 43)
    XCTAssertTrue(session.snapshot.isFinished)
    session.resume()
    XCTAssertEqual(session.elapsed, 0, "A deliberate Play at the end replays the finite script")
    XCTAssertTrue(session.isPlaying)
    now = 21
    session.pause()
    now = 300
    XCTAssertEqual(session.elapsed, 1, "Pausing also freezes the starting countdown")
  }

  @MainActor func testScrollAndSingleScreenScriptsHaveFiniteDurations() throws {
    let short = FloatingToolConfiguration(kind: .teleprompter, text: "A short note")
    let shortSession = FloatingToolSession(configuration: short)
    XCTAssertEqual(shortSession.playbackDuration, 4)
    let long = FloatingToolConfiguration(
      kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
    let layout = FloatingToolRenderer.ScriptLayout(long)
    let longSession = FloatingToolSession(configuration: long)
    XCTAssertEqual(
      try XCTUnwrap(longSession.playbackDuration), 3 + Double(layout.travel) / long.scrollSpeed,
      accuracy: 0.001)
    XCTAssertGreaterThan(try XCTUnwrap(longSession.playbackDuration), 10)
  }

  @MainActor func testNativeFiniteDelegateRewindsAndAcknowledgesStaleCallbacks() async throws {
    var now = 0.0
    var configuration = FloatingToolConfiguration(
      kind: .teleprompter, text: Array(repeating: "Word", count: 40).joined(separator: " "))
    configuration.prompterMode = .words
    configuration.wordsPerMinute = 60
    let session = FloatingToolSession(configuration: configuration, uptime: { now })
    let source = LiveFloatSource(session: session)
    let pip = AVPictureInPictureController(
      contentSource: .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: source))
    source.controller = pip
    try source.start()
    source.activate()
    let range = source.pictureInPictureControllerTimeRangeForPlayback(pip)
    XCTAssertEqual(range.duration.seconds, 43, accuracy: 0.001)
    now = 20
    let skipped = expectation(description: "Native rewind completion")
    source.pictureInPictureController(
      pip, skipByInterval: CMTime(seconds: -10, preferredTimescale: 600)
    ) { skipped.fulfill() }
    await fulfillment(of: [skipped], timeout: 3)
    XCTAssertEqual(session.elapsed, 10)
    let timebase = try XCTUnwrap(source.layer.controlTimebase)
    XCTAssertTrue(CMTimeRangeContainsTime(range, time: CMTimebaseGetTime(timebase)))
    session.seek(to: 999)
    XCTAssertTrue(CMTimeRangeContainsTime(range, time: CMTimebaseGetTime(timebase)))
    XCTAssertTrue(source.pictureInPictureControllerIsPlaybackPaused(pip))
    source.stop()
    let stoppedAt = session.elapsed
    let acknowledged = expectation(description: "Stale rewind acknowledged")
    source.pictureInPictureController(
      pip, skipByInterval: CMTime(seconds: -10, preferredTimescale: 600)
    ) { acknowledged.fulfill() }
    await fulfillment(of: [acknowledged], timeout: 3)
    XCTAssertEqual(session.elapsed, stoppedAt)
  }

  @MainActor func testClockStopwatchAndRealTimersCannotBeRewound() {
    for kind in [FloatingToolKind.clock, .stopwatch, .countdown, .pomodoro] {
      var now = 0.0
      let session = FloatingToolSession(configuration: .init(kind: kind), uptime: { now })
      XCTAssertNil(session.playbackDuration)
      XCTAssertFalse(session.configuration.supportsSeeking)
      session.resume()
      now = 30
      session.skip(by: -10)
      XCTAssertEqual(session.elapsed, 30)
      session.pause()
    }
  }

  func testClockLineOptionsAndDateSpecificZoneAbbreviations() {
    let summer = Date(timeIntervalSince1970: 1_782_864_000)
    let winter = Date(timeIntervalSince1970: 1_799_913_600)
    var configuration = FloatingToolConfiguration(
      kind: .clock, timeZoneIdentifier: "America/Los_Angeles")
    let zone = TimeZone(identifier: configuration.timeZoneIdentifier)!
    XCTAssertTrue(
      configuration.snapshot(elapsed: 0, date: summer).title.contains(
        zone.abbreviation(for: summer)!))
    XCTAssertTrue(
      configuration.snapshot(elapsed: 0, date: winter).title.contains(
        zone.abbreviation(for: winter)!))
    configuration.showsClockTimeZone = false
    XCTAssertEqual(configuration.snapshot(elapsed: 0, date: summer).title, "Los Angeles")
    configuration.showsClockLocation = false
    configuration.showsClockDate = false
    let snapshot = configuration.snapshot(elapsed: 0, date: summer)
    XCTAssertEqual(snapshot.title, "")
    XCTAssertEqual(snapshot.detail, "")
    XCTAssertFalse(snapshot.value.isEmpty)
  }

  func testClockSizesAndVisibilityActuallyChangePixelsAndValidate() throws {
    var configuration = FloatingToolConfiguration(kind: .clock)
    func frame() -> Data? {
      FloatingToolRenderer.render(configuration: configuration, elapsed: 0, date: .distantPast)
        .pngData()
    }
    let initial = frame()
    configuration.clockTimeSize = 160
    XCTAssertNotEqual(frame(), initial)
    let bigTime = frame()
    configuration.clockLocationSize = 80
    configuration.clockDateSize = 70
    XCTAssertNotEqual(frame(), bigTime)
    configuration.showsClockLocation = false
    configuration.showsClockDate = false
    XCTAssertNotEqual(frame(), initial)
    XCTAssertNoThrow(try configuration.validate())
    configuration.clockTimeSize = .nan
    XCTAssertThrowsError(try configuration.validate())
  }

  func testPDFTypedPageValidationAndIndexConversion() {
    XCTAssertEqual(PDFPageSelection.index("1", count: 80), 0)
    XCTAssertEqual(PDFPageSelection.index(" 80 ", count: 80), 79)
    for input in ["", "0", "-1", "81", "2.5", String(repeating: "9", count: 100)] {
      XCTAssertNil(PDFPageSelection.index(input, count: 80))
    }
    XCTAssertNil(PDFPageSelection.index("1", count: 0))
  }
}
