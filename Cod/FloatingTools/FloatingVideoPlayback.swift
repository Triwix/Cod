import AVFoundation

/// Speed and an optional section to play (and repeat) instead of the whole
/// video, for practice and tutorials.
struct FloatingVideoOptions: Equatable {
  static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
  static let minimumSection: Double = 1

  var speed: Float = 1
  /// Seconds into the video. Nil plays the whole video.
  var section: ClosedRange<Double>?

  /// A section that fits a video of this length, or nil when it covers
  /// (almost) all of it.
  static func clampedSection(_ section: ClosedRange<Double>?, duration: Double) -> ClosedRange<Double>? {
    guard let section, duration.isFinite, duration > minimumSection else { return nil }
    let start = min(max(0, section.lowerBound), duration - minimumSection)
    let end = min(duration, max(section.upperBound, start + minimumSection))
    guard start > 0.05 || end < duration - 0.05 else { return nil }
    return start...end
  }

  static func speedTitle(_ speed: Float) -> String {
    let text = speed == speed.rounded() ? String(Int(speed)) : String(format: "%g", speed)
    return "\(text)×"
  }
}

/// Repeat the real movie, not a still-image clip. Keeping one item also keeps
/// native seeking meaningful when Repeat is changed during playback.
@MainActor final class FloatingVideoPlayback {
  nonisolated static let defaultRepeats = true
  let player: AVQueuePlayer
  let reference: VideoReference
  private(set) var repeats: Bool
  private(set) var completedLoops = 0
  var onRepeat: ((Int) -> Void)?
  private var endObserver: NSObjectProtocol?
  private var repeatTask: Task<Void, Never>?
  private var revision = 0
  private var active = false
  private(set) var options: FloatingVideoOptions
  /// Where playback starts and each repeat returns to.
  var startTime: CMTime { CMTime(seconds: options.section?.lowerBound ?? 0, preferredTimescale: 600) }

  init(reference: VideoReference, sound: Bool = false, repeats: Bool = defaultRepeats,
       options: FloatingVideoOptions = .init()) {
    self.reference = reference
    self.repeats = repeats
    self.options = options
    let item = AVPlayerItem(url: reference.url)
    // The end of a section counts as the end of the video, so Repeat and
    // Repeat Off both work on the section.
    if let end = options.section?.upperBound {
      item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
    }
    item.audioTimePitchAlgorithm = .timeDomain
    player = AVQueuePlayer(playerItem: item)
    player.isMuted = !sound
    player.preventsDisplaySleepDuringVideoPlayback = false
    player.actionAtItemEnd = .pause
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.repeatIfEnabled() }
    }
  }

  deinit {
    repeatTask?.cancel()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
  }

  func activate() {
    active = true
    // PiP's own Play button uses the default rate, so the speed sticks.
    player.defaultRate = options.speed
    player.play()
  }

  func setSpeed(_ speed: Float) {
    options.speed = speed
    player.defaultRate = speed
    if player.rate != 0 { player.rate = speed }
  }

  func setRepeats(_ value: Bool) {
    guard repeats != value else { return }
    repeats = value
    revision += 1
    repeatTask?.cancel()
    // Changing Repeat while paused must not press Play for the user.
  }

  func stop() {
    active = false
    revision += 1
    repeatTask?.cancel()
    repeatTask = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    player.pause()
    onRepeat = nil
  }

  private func repeatIfEnabled() {
    guard active, repeats else { return }
    repeatTask?.cancel()
    let revision = revision
    repeatTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let finished = await self.player.seek(
        to: self.startTime, toleranceBefore: .zero, toleranceAfter: .zero)
      guard finished, !Task.isCancelled, self.active, self.repeats, revision == self.revision else {
        return
      }
      self.player.play()
      self.completedLoops += 1
      self.onRepeat?(self.completedLoops)
      CodDiagnosticLog.record("video repeat completed count=\(self.completedLoops)")
    }
  }
}
