import AVFoundation
import AVKit
import UIKit

/// Documented sample-buffer video playback for changing content. The existing
/// AVPlayer-based image pipeline is kept separate and unchanged.
@MainActor
final class LiveFloatSource: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
  let session: FloatingToolSession
  let layer = AVSampleBufferDisplayLayer()
  weak var controller: AVPictureInPictureController?
  var onFailure: ((Error) -> Void)?
  var nativePlaybackIsActive = false
  var audioIsInterrupted = false
  weak var appearanceHost: UIView?
  private var renderTask: Task<Void, Never>?
  private var timebase: CMTimebase?
  private var didStop = false
  private var lastFrameKey: Int?
  nonisolated private let playbackState: ToolPlaybackFlag

  init(session: FloatingToolSession) {
    self.session = session
    playbackState = ToolPlaybackFlag(duration: session.playbackDuration)
    super.init()
    layer.videoGravity = .resizeAspect
    var clock: CMTimebase?
    if CMTimebaseCreateWithSourceClock(
      allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &clock)
      == noErr,
      let clock
    {
      timebase = clock
      CMTimebaseSetTime(
        clock,
        time: session.playbackDuration == nil ? CMClockGetTime(CMClockGetHostTimeClock()) : .zero)
      CMTimebaseSetRate(clock, rate: session.playbackDuration == nil ? 1 : 0)
      layer.controlTimebase = clock
    }
    session.onPlaybackChange = { [weak self] in
      guard let self, !self.didStop else { return }
      self.lastFrameKey = nil
      if self.session.configuration.supportsSeeking { self.layer.sampleBufferRenderer.flush() }
      self.synchronizePlaybackClock()
      self.playbackState.setPaused(!self.session.isPlaying)
      self.controller?.invalidatePlaybackState()
      do { try self.enqueueFrame() } catch { self.onFailure?(error) }
    }
  }

  func start() throws {
    try session.configuration.validate()
    try enqueueFrame()
    playbackState.setPaused(!session.isPlaying)
    renderTask = Task { @MainActor [weak self] in
      var pacing = FloatingFramePacer(now: FloatingElapsedClock.now())
      while !Task.isCancelled {
        // Smooth rings and fractional stopwatches, without redrawing
        // whole-second clocks at video cadence. Paused content is deduplicated
        // below, but can still redraw for a seek or system appearance change.
        let fps = self?.session.isPlaying == true
          ? self?.session.configuration.framesPerSecond ?? 1 : 2
        let delay = pacing.nextDelay(now: FloatingElapsedClock.now(), framesPerSecond: fps)
        do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(1)) } catch { return }
        guard let self, !self.didStop else { return }
        // A paused seek must still get its replacement frame if the renderer
        // wasn't ready during the explicit playback-change callback.
        do { try self.enqueueFrame() } catch {
          self.onFailure?(error)
          return
        }
      }
    }
  }

  func activate() {
    nativePlaybackIsActive = true
    session.resume()
  }

  func stop(preservingTimer: Bool = false) {
    didStop = true
    nativePlaybackIsActive = false
    renderTask?.cancel()
    renderTask = nil
    session.onPlaybackChange = nil
    session.pictureInPictureDidClose(preservingTimer: preservingTimer)
    if session.configuration.keepTimerRunningOnClose || preservingTimer {
      FloatingVisualTimers.shared.keep(session)
    }
    playbackState.setPaused(true)
    layer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    controller = nil
  }

  private func enqueueFrame() throws {
    guard !didStop else { return }
    let elapsed = session.elapsed
    if let appearanceHost,
      session.updateSystemAppearance(appearanceHost.traitCollection.userInterfaceStyle) {
      lastFrameKey = nil
    }
    let configuration = session.configuration
    let key = configuration.frameKey(elapsed: elapsed, date: session.displayDate)
    if key == lastFrameKey { return }
    let renderer = layer.sampleBufferRenderer
    if renderer.status == .failed { renderer.flush() }
    guard renderer.isReadyForMoreMediaData else { return }
    // Resume/pause/seek synchronizes immediately. During steady playback,
    // don't keep resetting a perfectly good video timebase on every frame.
    if session.playbackDuration != nil, let timebase,
      abs(CMTimebaseGetTime(timebase).seconds - mediaTime.seconds) > 0.1 {
      synchronizePlaybackClock()
    }
    let image = session.renderedFrame()
    let timestamp =
      session.playbackDuration == nil
      ? CMClockGetTime(CMClockGetHostTimeClock()) : mediaTime
    let sample = try Self.sampleBuffer(image: image, at: timestamp)
    renderer.enqueue(sample)
    lastFrameKey = key
    let finished = session.snapshot.isFinished
    // A one-screen script is still displayed, not scrolled off into blank.
    if finished, session.isPlaying { session.complete() }
  }

  /// Finite media uses script time, not the host clock's uptime. Keep the
  /// final playhead inside the last frame of the actual finite range.
  private var mediaTime: CMTime {
    let duration = session.playbackDuration ?? 0
    return CMTime(
      seconds: min(max(0, duration - 1 / 600), max(0, session.elapsed)), preferredTimescale: 600)
  }

  private func synchronizePlaybackClock() {
    guard session.playbackDuration != nil, let timebase else { return }
    // Freeze before repositioning. Setting a near-end time while the old rate
    // is still 1 can run beyond the finite range before the pause is applied.
    CMTimebaseSetRate(timebase, rate: 0)
    CMTimebaseSetTime(timebase, time: mediaTime)
    if session.isPlaying { CMTimebaseSetRate(timebase, rate: 1) }
  }

  static func sampleBuffer(
    image: UIImage, at time: CMTime, duration: CMTime = .invalid
  ) throws -> CMSampleBuffer {
    guard let pixels = image.pixelBuffer() else { throw FloatingToolError.renderFailed }
    var description: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &description)
        == noErr,
      let description
    else { throw FloatingToolError.renderFailed }
    var timing = CMSampleTimingInfo(
      duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescription: description,
        sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
      let sample
    else { throw FloatingToolError.renderFailed }
    return sample
  }

  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool
  ) {
    Task { @MainActor [weak self] in
      guard let self, self.controller === pictureInPictureController, !self.didStop else { return }
      if self.session.configuration.hasTimerAlarm, !playing {
        // AVKit may request a pause just BEFORE its will-stop callback
        // (including app termination). Wait for that transition to
        // settle before treating it as a user's native Pause tap.
        try? await Task.sleep(for: .milliseconds(200))
        guard self.controller === pictureInPictureController, !self.didStop else { return }
      }
      // AVKit also sends playback changes during setup/teardown. Those
      // aren't an explicit timer pause and must not disarm a system
      // alarm merely because PiP couldn't open or the phone locked.
      guard self.nativePlaybackIsActive, pictureInPictureController.isPictureInPictureActive else {
        return
      }
      if !playing, self.audioIsInterrupted, self.session.configuration.hasTimerAlarm { return }
      self.session.setPlayingFromPiP(playing)
    }
  }
  nonisolated func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    playbackState.range
  }
  nonisolated func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    playbackState.isPaused
  }
  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}
  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
    completion: @escaping () -> Void
  ) {
    guard playbackState.canSeek else {
      completion()
      return
    }
    Task { @MainActor [weak self] in
      defer { completion() }
      guard let self, self.controller === pictureInPictureController, !self.didStop else { return }
      self.session.skip(by: skipInterval.seconds)
    }
  }
}

/// Anchor cadence to deadlines instead of adding render time to every sleep.
/// Late frames jump to the present; don't queue a burst of stale catch-up work.
struct FloatingFramePacer {
  private(set) var nextFrameAt: TimeInterval
  init(now: TimeInterval) { nextFrameAt = now }
  mutating func nextDelay(now: TimeInterval, framesPerSecond: Double) -> TimeInterval {
    let fps = framesPerSecond.isFinite ? min(120, max(1, framesPerSecond)) : 1
    nextFrameAt = max(nextFrameAt + 1 / fps, now)
    return max(0, nextFrameAt - now)
  }
}

/// Synchronous system queries need a thread-safe snapshot, not a hop to the
/// main actor or an assumption about AVKit's callback queue.
private final class ToolPlaybackFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var paused = true
  let range: CMTimeRange
  let canSeek: Bool
  init(duration: TimeInterval?) {
    canSeek = duration != nil
    range = CMTimeRange(
      start: .zero,
      duration: duration.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .positiveInfinity)
  }
  var isPaused: Bool { lock.withLock { paused } }
  func setPaused(_ value: Bool) { lock.withLock { paused = value } }
}
