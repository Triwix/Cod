import AVFoundation
import AVKit
import Combine
import UIKit

/// Floats a single snippet over *every* app using Picture in Picture.
///
/// The snippet is encoded as a short looping clip and played by an `AVPlayer`,
/// using the documented AVKit video playback APIs. There are no extension-side
/// video-call experiments or private control/navigation overrides.
///
/// PiP has one window at a time, with system-owned controls and resizing.
@MainActor
final class PiPPinController: NSObject, ObservableObject {
    static let shared = PiPPinController()

    enum Status: Equatable {
        case idle
        case preparing
        case active
        case unsupported
        case failed(String)

        var isBusy: Bool { self == .preparing }
    }

    enum FloatPreparationPath: Equatable {
        case replaceActive
        case reusePrepared
        case cold
    }

    nonisolated static func preparationPath(
        wasActive: Bool,
        hasPlayer: Bool,
        hasController: Bool,
        reusePreparedPlayback: Bool = true
    ) -> FloatPreparationPath {
        if wasActive, hasPlayer { return .replaceActive }
        if reusePreparedPlayback, hasPlayer, hasController { return .reusePrepared }
        return .cold
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var isPossible = false
    /// Hand the image back to the crop UI when the user restores PiP, including
    /// a tap during its opening animation. Do not treat restoration as failure.
    @Published var restorationImage: UIImage?
    @Published var restorationTool: FloatingToolSession?
    @Published var restorationVideo: VideoReference?
    @Published private(set) var toolSession: FloatingToolSession?
    @Published private(set) var videoReference: VideoReference?
    @Published private(set) var completedVideoLoops = 0
    private var videoPlayback: FloatingVideoPlayback?
    private var videoRepeats = FloatingVideoPlayback.defaultRepeats
    private var videoSound = false
    private var liveSource: LiveFloatSource?
    private var restorationState = PiPRestorationState()

    let isSupported: Bool

    /// The controller is the source of truth during a failed in-place
    /// replacement: the old window may still be active even though the new
    /// snippet could not be encoded.
    var isActive: Bool { controller?.isPictureInPictureActive == true }

    private var controller: AVPictureInPictureController?
    private var player: AVQueuePlayer?
    private var loopObserver: NSObjectProtocol?
    private var readinessWait: PiPReadinessWait?
    private var playerLayer: AVPlayerLayer?
    /// Start of the current float request, for stage timings.
    private var startedAt = CFAbsoluteTimeGetCurrent()
    private var hostView: UIView?
    weak var inlineVideoHost: FloatingVideoHostView?
    private var ownsHostView = true
    private var clipURL: URL?
    private var possibleObservation: NSKeyValueObservation?
    private var startTimeout: Task<Void, Never>?
    private var startRetry: Task<Void, Never>?
    private var foregroundObservation: NSObjectProtocol?
    private var prepareTask: Task<Void, Never>?
    /// Identifies the task that currently owns preparation state. Cancelling an
    /// older task is cooperative, so its defer must not clear a newer handle.
    private var preparationID: UUID?
    private var audioInterruptionObservation: NSObjectProtocol?

    /// PiP renders into a window a few hundred points wide, so full-resolution
    /// screenshots buy nothing and cost encode time.
    private let maxRenderEdge: CGFloat = 1200

    override convenience init() {
        self.init(isSupported: AVPictureInPictureController.isPictureInPictureSupported())
    }

    /// Keep capability checks injectable so lifecycle tests do not depend on
    /// native PiP availability. The app always uses the system result above.
    init(isSupported: Bool) {
        self.isSupported = isSupported
        super.init()
        audioInterruptionObservation = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveSource?.audioIsInterrupted = type == .began
                self.log("audio interruption \(type == .began ? "began" : "ended")")
                // iOS owns alarm audio. An audio interruption isn't a request
                // to pause/cancel the independently scheduled timer.
            }
        }
    }

    deinit {
        if let audioInterruptionObservation { NotificationCenter.default.removeObserver(audioInterruptionObservation) }
    }

    func setVideoSound(_ enabled: Bool, for id: UUID) {
        guard videoReference?.id == id else { return }
        videoSound = enabled
        player?.isMuted = !enabled
    }

    func setVideoRepeats(_ enabled: Bool, for id: UUID) {
        guard videoReference?.id == id else { return }
        videoRepeats = enabled
        videoPlayback?.setRepeats(enabled)
    }

    // MARK: - Public

    /// Builds the player, layer and PiP controller ahead of time on a throwaway
    /// clip.
    ///
    /// Measured on device, everything Cod does takes ~190ms — but AVKit then
    /// takes the better part of ten seconds to flip
    /// `isPictureInPicturePossible` to true the first time, which looks to the
    /// user like Cod hanging. Doing it while they're still dragging a selection
    /// makes that cost invisible.
    func prewarm() {
        guard isSupported, controller == nil, prepareTask == nil, status == .idle else { return }

        let requestID = UUID()
        preparationID = requestID
        prepareTask = Task { @MainActor in
            defer {
                if preparationID == requestID {
                    preparationID = nil
                    prepareTask = nil
                }
            }
            do {
                let url = try await FloatingClip.make(from: Self.placeholderImage)
                guard !Task.isCancelled, preparationID == requestID,
                      controller == nil, status == .idle
                else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                // Only claim the audio session early if doing so is silent.
                // Otherwise it would cut the user's music the moment they open
                // the crop surface, before they've asked for anything.
                if AppSettings.shared.keepOtherAudioPlaying { configureAudioSession() }
                try startPlayback(with: url)
                guard attachHostView() else {
                    discardPlayback()
                    return
                }
                await waitForPlayerReady()
                guard !Task.isCancelled, preparationID == requestID,
                      status == .idle else { return }
                makeController()
                log("prewarmed, possible=\(controller?.isPictureInPicturePossible ?? false)")
                observePossible()
            } catch {
                log("prewarm failed (harmless): \(error.localizedDescription)")
            }
        }
    }

    func float(_ image: UIImage, reusePreparedPlayback: Bool = true) {
        guard isSupported else {
            status = .unsupported
            return
        }

        // A live tool uses a different documented content source. Do not let
        // its frame pump survive an explicit replacement with a photo.
        if liveSource != nil || videoReference != nil {
            controller?.stopPictureInPicture()
            teardown(keepStatus: true)
        }
        restorationTool = nil
        restorationVideo = nil
        restorationState.beginFloat()
        restorationImage = nil
        startTimeout?.cancel()
        startRetry?.cancel()
        possibleObservation = nil
        if let foregroundObservation { NotificationCenter.default.removeObserver(foregroundObservation) }
        foregroundObservation = nil
        readinessWait?.finish(.cancelled)
        readinessWait = nil
        let wasActive = controller?.isPictureInPictureActive == true
        // A share launch returns to an app that was backgrounded while its
        // placeholder was playing. Rebuild that dormant pipeline around the
        // actual image, while preserving an already-visible PiP replacement.
        // Playback cleanup is part of this new request, not a cancellation.
        // Publishing idle here would make CaptureCoordinator finish the
        // request before it can observe preparing and the eventual result.
        if !reusePreparedPlayback, !wasActive { teardown(keepStatus: true) }
        let previousImage = currentImage
        let wasPrewarmed = controller != nil && status == .idle
        currentImage = image
        status = .preparing
        prepareTask?.cancel()
        let requestID = UUID()
        preparationID = requestID
        startedAt = CFAbsoluteTimeGetCurrent()

        prepareTask = Task { @MainActor in
            // Without this the task handle lingers after a float completes and
            // the `prepareTask == nil` guard blocks every future prewarm.
            defer {
                if preparationID == requestID {
                    preparationID = nil
                    prepareTask = nil
                }
            }
            let maximumEdge = maxRenderEdge
            let prepared = await Task.detached(priority: .userInitiated) {
                image.renderedForPiP(maximumEdge: maximumEdge)
            }.value
            guard !Task.isCancelled, preparationID == requestID else { return }
            guard let prepared else {
                if wasActive { currentImage = previousImage }
                status = .failed("Cod couldn't prepare this image for playback.")
                return
            }
            log("float() size=\(Int(prepared.size.width))x\(Int(prepared.size.height)) prewarmed=\(wasPrewarmed) +\(elapsed())ms")

            do {
                let url = try await FloatingClip.make(from: prepared)
                guard !Task.isCancelled, preparationID == requestID else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                log("clip encoded +\(elapsed())ms")

                let path = Self.preparationPath(
                    wasActive: wasActive,
                    hasPlayer: player != nil,
                    hasController: controller != nil,
                    reusePreparedPlayback: reusePreparedPlayback
                )

                // Already floating? Swap the clip in place; the PiP window
                // stays put and just shows the new snippet.
                if path == .replaceActive, let player {
                    swapClip(to: url, on: player)
                    status = .active
                    return
                }

                configureAudioSession()

                // Warm path: player, layer and controller already exist, and
                // AVKit has had time to decide PiP is possible.
                if path == .reusePrepared, let player {
                    swapClip(to: url, on: player)
                    await waitForPlayerReady()
                    guard !Task.isCancelled, preparationID == requestID else { return }
                    startWhenPossible()
                    return
                }

                // Cold path. A prewarm cancelled mid-setup can leave a partly
                // built player behind; clear it rather than orphaning it.
                discardPlayback()
                try startPlayback(with: url)
                guard attachHostView() else {
                    discardPlayback()
                    status = .failed("Cod couldn't find its window to attach the floating layer to.")
                    return
                }
                await waitForPlayerReady()
                guard !Task.isCancelled, preparationID == requestID else { return }
                makeController()
                startWhenPossible()
            } catch {
                guard !Task.isCancelled, preparationID == requestID else { return }
                log("PREPARE FAILED: \(error)")
                if wasActive { currentImage = previousImage }
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Starts changing video content without altering the proven still-image
    /// encoder. Native play/pause controls are delegated to the tool session.
    func float(tool session: FloatingToolSession) {
        guard isSupported else {
            if session.configuration.hasTimerAlarm { session.resume() }
            status = .unsupported
            return
        }
        controller?.stopPictureInPicture()
        teardown(keepStatus: true)
        restorationState.beginFloat()
        restorationImage = nil
        restorationTool = nil
        restorationVideo = nil
        currentImage = nil
        toolSession = session
        status = .preparing
        startedAt = CFAbsoluteTimeGetCurrent()
        configureAudioSession()
        let source = LiveFloatSource(session: session)
        liveSource = source
        source.onFailure = { [weak self, weak source] error in
            guard let self, let source, self.liveSource === source else { return }
            self.status = .failed(error.localizedDescription)
            self.teardown(keepStatus: true)
        }
        do {
            try source.start()
            guard attachHostView() else { throw FloatingToolError.renderFailed }
            source.appearanceHost = hostView
            let pip = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: source))
            pip.delegate = self
            pip.requiresLinearPlayback = !session.configuration.supportsSeeking
            pip.canStartPictureInPictureAutomaticallyFromInline = false
            controller = pip
            source.controller = pip
            startWhenPossible()
        } catch {
            status = .failed(error.localizedDescription)
            teardown(keepStatus: true)
        }
    }

    func float(video reference: VideoReference, sound: Bool, repeats: Bool = FloatingVideoPlayback.defaultRepeats) {
        guard isSupported else { status = .unsupported; return }
        controller?.stopPictureInPicture()
        teardown(keepStatus: true)
        restorationState.beginFloat()
        restorationImage = nil
        restorationTool = nil
        restorationVideo = nil
        currentImage = nil
        videoReference = reference
        completedVideoLoops = 0
        videoRepeats = repeats
        videoSound = sound
        status = .preparing
        startedAt = CFAbsoluteTimeGetCurrent()
        configureAudioSession()
        let requestID = UUID()
        preparationID = requestID
        prepareTask = Task { @MainActor in
            defer {
                if preparationID == requestID { preparationID = nil; prepareTask = nil }
            }
            guard !Task.isCancelled, preparationID == requestID else { return }
            let playback = FloatingVideoPlayback(reference: reference, sound: videoSound, repeats: videoRepeats)
            videoPlayback = playback
            playback.onRepeat = { [weak self, weak playback] count in
                guard let self, let playback, self.videoPlayback === playback else { return }
                self.completedVideoLoops = count
            }
            let queue = playback.player
            let layer = AVPlayerLayer(player: queue)
            layer.videoGravity = .resizeAspect
            player = queue
            playerLayer = layer
            guard attachHostView() else {
                status = .failed("Cod couldn't attach the video to its window.")
                teardown(keepStatus: true)
                return
            }
            queue.play()
            await waitForPlayerReady()
            guard !Task.isCancelled, preparationID == requestID else { return }
            // Prepare the first frame, then hold the video at its beginning
            // while AVKit opens. A short clip mustn't finish during setup.
            queue.pause()
            await queue.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, preparationID == requestID else { return }
            makeController()
            startWhenPossible()
        }
    }

    /// A small black frame — never seen, it just gives AVKit something real to
    /// initialise against.
    private static let placeholderImage: UIImage = {
        let size = CGSize(width: 160, height: 160)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }()

    /// AVKit won't offer a PiP window until the layer has something to show.
    /// Waiting explicitly is both faster and far more predictable than
    /// creating the controller early and polling `isPictureInPicturePossible`.
    private func waitForPlayerReady() async {
        guard let layer = playerLayer, !layer.isReadyForDisplay else {
            log("layer already ready +\(elapsed())ms")
            return
        }
        let wait = PiPReadinessWait()
        readinessWait = wait
        wait.observation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak wait] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in wait?.finish(.ready) }
        }
        let outcome = await wait.wait()
        // An old wait must never clear a newer request's observation.
        if readinessWait === wait { readinessWait = nil }
        switch outcome {
        case .ready: log("layer ready for display +\(elapsed())ms")
        case .timedOut: log("layer readiness timed out — proceeding anyway")
        case .cancelled: log("layer readiness wait cancelled")
        }
    }

    private func elapsed() -> Int {
        Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
    }

    func stop() {
        controller?.stopPictureInPicture()
        teardown()
    }

    /// A prewarmed placeholder is only for foreground preparation. Never keep
    /// idle playback/audio running in the background without an actual float.
    func stopIdlePlayback() {
        guard status == .idle, !isActive else { return }
        teardown()
    }

    // MARK: - Playback

    private func startPlayback(with url: URL) throws {
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        // Every frame is identical, so restarting at the end is invisible.
        // AVPlayerLooper would be tidier but has to resolve the asset's
        // duration before it can configure itself, which costs seconds here.
        queuePlayer.actionAtItemEnd = .none

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak queuePlayer] _ in
            queuePlayer?.seek(to: .zero)
            queuePlayer?.play()
        }

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspect

        player = queuePlayer
        playerLayer = layer
        clipURL = url
        queuePlayer.play()
        log("player started (muted, seek-loop) +\(elapsed())ms")
    }

    private func swapClip(to url: URL, on player: AVQueuePlayer) {
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        let item = AVPlayerItem(url: url)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        player.replaceCurrentItem(with: item)
        player.play()

        let previous = clipURL
        clipURL = url
        if let previous { try? FileManager.default.removeItem(at: previous) }
        log("swapped clip in place +\(elapsed())ms")
        Haptics.success()
    }

    private func makeController() {
        guard let playerLayer, controller == nil else { return }
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.delegate = self
        // A looping still has no meaningful timeline; hide the scrubber.
        pip?.requiresLinearPlayback = videoReference == nil
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip
        log("controller created +\(elapsed())ms nil=\(pip == nil)")

    }


    /// Watches eligibility during prewarm so the log shows how long AVKit
    /// really takes, without anything waiting on it.
    private func observePossible() {
        guard let controller, !controller.isPictureInPicturePossible else { return }
        let warmStart = CFAbsoluteTimeGetCurrent()
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] pip, change in
            guard change.newValue == true else { return }
            Task { @MainActor in
                guard let self, self.controller === pip else { return }
                self.isPossible = true
                self.log("prewarm became possible after \(Int((CFAbsoluteTimeGetCurrent() - warmStart) * 1000))ms")
                self.possibleObservation = nil
            }
        }
    }

    private func startWhenPossible() {
        guard let controller else {
            status = .failed("iOS wouldn't create a Picture in Picture controller for this snippet.")
            return
        }

        isPossible = controller.isPictureInPicturePossible
        log("possible=\(isPossible) +\(elapsed())ms")

        if isPossible {
            requestPiPStart(controller)
            scheduleStartTimeout()
            return
        }

        // The player needs to reach a playable state before AVKit will offer
        // the window.
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] pip, change in
            guard change.newValue == true else { return }
            Task { @MainActor in
                guard let self, self.controller === pip, self.status == .preparing else { return }
                self.log("became possible +\(self.elapsed())ms")
                self.isPossible = true
                self.requestPiPStart(pip)
                self.possibleObservation = nil
            }
        }
        scheduleStartTimeout()
    }

    /// AVKit occasionally accepts `startPictureInPicture()` without producing
    /// either a delegate callback or an error. Retrying
    /// the same active controller works; do that automatically while the
    /// request is still preparing.
    private func requestPiPStart(_ controller: AVPictureInPictureController) {
        guard let sourceScene = hostView?.window?.windowScene else {
            log("PiP source view has no window scene")
            status = .failed("Cod's floating view isn't attached to its window yet.")
            return
        }
        guard sourceScene.activationState == .foregroundActive else {
            log("waiting for source scene foreground activation before PiP request +\(elapsed())ms")
            guard foregroundObservation == nil else { return }
            let waitingControllerID = ObjectIdentifier(controller)
            foregroundObservation = NotificationCenter.default.addObserver(
                forName: UIScene.didActivateNotification,
                object: sourceScene,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let current = self.controller,
                          ObjectIdentifier(current) == waitingControllerID else { return }
                    if let observer = self.foregroundObservation {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    self.foregroundObservation = nil
                    guard self.status == .preparing else { return }
                    self.log("source scene active; resuming PiP request")
                    self.startWhenPossible()
                }
            }
            return
        }
        log("starting PiP +\(elapsed())ms")
        controller.startPictureInPicture()

        startRetry?.cancel()
        startRetry = Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else { return }
            for attempt in 1...3 {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled, self.controller === controller, self.status == .preparing,
                      !controller.isPictureInPictureActive else { return }
                guard self.hostView?.window?.windowScene?.activationState == .foregroundActive else { continue }
                self.log("retrying PiP start (\(attempt)/3) +\(self.elapsed())ms")
                controller.startPictureInPicture()
            }
        }
    }

    private func scheduleStartTimeout() {
        startTimeout?.cancel()
        startTimeout = Task { @MainActor in
            let timeout: UInt64 = 25_000_000_000
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, self.status == .preparing else { return }
            self.log("TIMED OUT — PiP never started")
            if self.toolSession?.configuration.hasTimerAlarm == true { self.toolSession?.resume() }
            // Deliberately does NOT tear down. AVKit can open the window well
            // after we've given up, and destroying the player mid-handover was
            // itself making the launch intermittent.
            self.status = .failed(
                "iOS hasn't opened the window yet. Another app may be holding Picture in Picture — force-quit video apps and try again."
            )
            // A changing tool must not keep rendering indefinitely after a
            // failed launch. Preserve the legacy still-image late-start path.
            if self.liveSource != nil { self.teardown(keepStatus: true) }
        }
    }

    // MARK: - Plumbing

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let mixes = AppSettings.shared.keepOtherAudioPlaying
        do {
            // Mixable keeps the user's music alive but makes Cod a secondary
            // audio app, which can cost the background time the window needs.
            try session.setCategory(.playback, mode: .moviePlayback, options: mixes ? [.mixWithOthers] : [])
            try session.setActive(true)
            log("audio session active, mixWithOthers=\(mixes) otherAudioPlaying=\(session.isOtherAudioPlaying)")
        } catch {
            log("AUDIO SESSION FAILED: \(error.localizedDescription)")
        }
    }

    private func attachHostView() -> Bool {
        if hostView != nil { return true }
        guard let renderingLayer: CALayer = liveSource?.layer ?? playerLayer else {
            log("NO RENDERING LAYER — cannot attach the floating host view")
            return false
        }
        if videoReference != nil, let inlineVideoHost, inlineVideoHost.window != nil {
            inlineVideoHost.playbackLayer = playerLayer
            renderingLayer.frame = inlineVideoHost.bounds
            inlineVideoHost.layer.addSublayer(renderingLayer)
            hostView = inlineVideoHost
            ownsHostView = false
            return true
        }
        guard let window = UIApplication.shared.activeWindow else {
            log("NO KEY WINDOW — cannot host the layer")
            return false
        }

        let width: CGFloat = 140
        let container = UIView(frame: CGRect(x: 12, y: window.safeAreaInsets.top + 12, width: width, height: width))
        container.isUserInteractionEnabled = false
        container.backgroundColor = .black
        container.alpha = 0.02
        renderingLayer.frame = container.bounds
        container.layer.addSublayer(renderingLayer)
        window.addSubview(container)
        window.sendSubviewToBack(container)
        hostView = container
        ownsHostView = true
        log("host view attached")
        return true
    }

    /// Releases player-side state without touching status or the audio session.
    private func discardPlayback() {
        videoPlayback?.stop()
        videoPlayback = nil
        readinessWait?.finish(.cancelled)
        readinessWait = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        if ownsHostView { hostView?.removeFromSuperview() }
        (hostView as? FloatingVideoHostView)?.playbackLayer = nil
        hostView = nil
        if let clipURL { try? FileManager.default.removeItem(at: clipURL) }
        clipURL = nil
    }

    private func teardown(keepStatus: Bool = false, preservingToolTimer: Bool = false) {
        videoPlayback?.stop()
        videoPlayback = nil
        liveSource?.stop(preservingTimer: preservingToolTimer)
        liveSource = nil
        toolSession = nil
        videoReference = nil
        if let foregroundObservation {
            NotificationCenter.default.removeObserver(foregroundObservation)
        }
        foregroundObservation = nil
        controller?.delegate = nil
        startTimeout?.cancel()
        startTimeout = nil
        startRetry?.cancel()
        startRetry = nil
        prepareTask?.cancel()
        prepareTask = nil
        preparationID = nil
        possibleObservation = nil
        readinessWait?.finish(.cancelled)
        readinessWait = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        if ownsHostView { hostView?.removeFromSuperview() }
        (hostView as? FloatingVideoHostView)?.playbackLayer = nil
        hostView = nil
        controller = nil
        isPossible = false
        if let clipURL { try? FileManager.default.removeItem(at: clipURL) }
        clipURL = nil
        FloatingClip.cleanUp()
        if !keepStatus {
            status = .idle
            currentImage = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let message = message()
        // Plain stdout so `devicectl device process launch --console` picks it
        // up without needing root. stdout block-buffers when redirected, so
        // flush or the tail never arrives.
        print("[CodPiP] \(message)")
        fflush(stdout)
        CodDiagnosticLog.record("PiP \(message)")
        #endif
    }
}

/// Ignore out-of-order start/failure events after the user restores PiP.
struct PiPRestorationState {
    private(set) var isRestoring = false

    mutating func beginFloat() {
        isRestoring = false
    }

    mutating func beginRestoration() {
        isRestoring = true
    }
}

/// Each preparation owns its own continuation and observation. Cancelling a
/// float releases the wait immediately; queued KVO/timeout events are harmless.
@MainActor
final class PiPReadinessWait {
    enum Outcome: Equatable { case ready, timedOut, cancelled }

    var observation: NSKeyValueObservation?
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var timeout: Task<Void, Never>?

    func wait(timeoutNanoseconds: UInt64 = 5_000_000_000) async -> Outcome {
        await withTaskCancellationHandler {
            if Task.isCancelled { finish(.cancelled) }
            if let outcome { return outcome }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                timeout = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.finish(.timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.cancelled) }
        }
    }

    func finish(_ result: Outcome) {
        guard outcome == nil else { return }
        outcome = result
        observation = nil
        timeout?.cancel()
        timeout = nil
        continuation?.resume(returning: result)
        continuation = nil
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPPinController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            self.log("WILL START PiP +\(self.elapsed())ms")
            // Once AVKit has begun its appearance animation, a second start
            // request can conflict with a user tap during the transition.
            self.startRetry?.cancel()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            guard !self.restorationState.isRestoring else { return }
            self.log("DID START PiP +\(self.elapsed())ms")
            self.startTimeout?.cancel()
            self.startRetry?.cancel()
            self.status = .active
            self.liveSource?.activate()
            self.videoPlayback?.activate()
            Haptics.success()
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            self.startRetry?.cancel()
            self.liveSource?.nativePlaybackIsActive = false
            self.log("WILL STOP PiP")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else {
                self.log("ignoring stop callback from replaced controller")
                return
            }
            self.log("DID STOP PiP")
            self.teardown(preservingToolTimer: self.restorationState.isRestoring)
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            if self.restorationState.isRestoring {
                self.log("PiP start ended during user restoration; preserving restored image UI")
                self.teardown()
                return
            }
            self.log("FAILED TO START: \(error)")
            if self.toolSession?.configuration.hasTimerAlarm == true { self.toolSession?.resume() }
            self.status = .failed(error.localizedDescription)
            self.teardown(keepStatus: true)
        }
    }

    /// Tapping the PiP window's restore button brings Cod forward again.
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else {
                completionHandler(false)
                return
            }
            self.log("PiP requested app interface restoration")
            self.restorationState.beginRestoration()
            self.startRetry?.cancel()
            self.startTimeout?.cancel()
            if let video = self.videoReference { self.restorationVideo = video }
            else if let session = self.toolSession { self.restorationTool = session }
            else { self.restorationImage = self.currentImage }
            completionHandler(true)
        }
    }
}


extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
