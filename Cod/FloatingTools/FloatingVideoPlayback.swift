import AVFoundation

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

  init(reference: VideoReference, sound: Bool = false, repeats: Bool = defaultRepeats) {
    self.reference = reference
    self.repeats = repeats
    let item = AVPlayerItem(url: reference.url)
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
    player.play()
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
        to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
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
