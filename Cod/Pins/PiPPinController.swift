import AVFoundation
import AVKit
import Combine
#if COD_PERSONAL
import ObjectiveC
#endif
import UIKit

/// Floats a single snippet over *every* app using Picture in Picture.
///
/// The snippet is encoded as a short looping clip and played by an `AVPlayer`,
/// because that is the path PiP is actually built for. The
/// `AVSampleBufferDisplayLayer` route works for genuine live streams but needs
/// a control timebase to drain its queue; without one AVKit silently refuses to
/// open the window — no error, no delegate callback.
///
/// What comes with PiP either way: one window at a time, Apple's chrome, and
/// nothing at all in the Simulator.
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
    /// Set when a floating window died because Cod lost background time, so the
    /// UI can explain the audio-session trade instead of the window silently
    /// vanishing.
    @Published var lostToBackgrounding = false
    /// Hand the image back to the crop UI when the user restores PiP, including
    /// a tap during its opening animation. Do not treat restoration as failure.
    @Published var restorationImage: UIImage?
    private var returnPolicy = PiPReturnPolicy()

    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    /// The controller is the source of truth during a failed in-place
    /// replacement: the old window may still be active even though the new
    /// snippet could not be encoded.
    var isActive: Bool { controller?.isPictureInPictureActive == true }

    private var controller: AVPictureInPictureController?
    private var player: AVQueuePlayer?
    private var loopObserver: NSObjectProtocol?
    private var readinessWait: PiPReadinessWait?
    private var playerLayer: AVPlayerLayer?
    private var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private var sampleBufferTimebase: CMTimebase?
    #if APP_EXTENSION
    private var videoCallContentController: ImagePiPViewController?
    #endif
    /// Start of the current float request, for stage timings.
    private var startedAt = CFAbsoluteTimeGetCurrent()
    /// When Cod last backgrounded itself, so we can tell a window the user
    /// closed from one iOS killed because the app lost background time.
    private var suspendedAt: CFAbsoluteTime?
    private var hostView: UIView?
    /// Share extensions can't query `UIApplication.shared`, so they explicitly
    /// provide their own visible root view as the player-layer host.
    private weak var explicitHostView: UIView?
    private var clipURL: URL?
    private var possibleObservation: NSKeyValueObservation?
    private var startTimeout: Task<Void, Never>?
    private var startRetry: Task<Void, Never>?
    private var returnTask: Task<Void, Never>?
    private var foregroundObservation: NSObjectProtocol?
    private var prepareTask: Task<Void, Never>?
    /// Identifies the task that currently owns preparation state. Cancelling an
    /// older task is cooperative, so its defer must not clear a newer handle.
    private var preparationID: UUID?
    /// The Share extension supplies a file-backed sink because its stdout is
    /// not attached to Cod's normal device console.
    private var diagnosticsHandler: ((String) -> Void)?

    /// PiP renders into a window a few hundred points wide, so full-resolution
    /// screenshots buy nothing and cost encode time.
    private let maxRenderEdge: CGFloat = 1200

    /// Draws the player layer on screen while debugging. Off for normal use —
    /// the layer only has to exist and render, not be seen.
    #if APP_EXTENSION
    /// Visible in the current device diagnostic build. This proves whether the
    /// extension's AVPlayer is rendering the shared photo before AVKit takes
    /// ownership of it.
    static let showsRenderProbe = true
    #else
    static let showsRenderProbe = false
    #endif

    override init() {
        super.init()
    }

    // MARK: - Public

    func setHostView(_ view: UIView?) {
        explicitHostView = view
    }

    /// A Share extension process may be reused after its UI is dismissed.
    /// Controllers created for the previous host scene cannot be started from
    /// the next one, so each share begins with completely fresh AVKit state.
    func resetForNewShareSession(hostView view: UIView) {
        controller?.delegate = nil
        controller?.stopPictureInPicture()
        teardown()
        explicitHostView = view
    }

    func setDiagnosticsHandler(_ handler: ((String) -> Void)?) {
        diagnosticsHandler = handler
    }

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

    func float(_ image: UIImage, reusePreparedPlayback: Bool = true, sourceBundleIdentifier: String? = nil) {
        guard isSupported else {
            status = .unsupported
            return
        }

        #if APP_EXTENSION
        floatUsingVideoCallContent(image)
        #else
        returnPolicy.beginFloat()
        restorationImage = nil
        #if COD_PERSONAL
        SourceAppReturn.shared.capture(sourceBundleIdentifier: sourceBundleIdentifier)
        #endif
        returnTask?.cancel()
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
        if !reusePreparedPlayback, !wasActive { teardown() }
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
            let prepared = prepare(image)
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
                    returnToPreviousApp()
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
        #endif
    }

    #if APP_EXTENSION
    /// A video-call content source is AVKit's view-based PiP path. Unlike the
    /// player and sample-buffer paths, it doesn't ask the Share extension's
    /// media layer to cross into the system PiP scene.
    private func floatUsingVideoCallContent(_ image: UIImage) {
        currentImage = image
        status = .preparing
        prepareTask?.cancel()
        startedAt = CFAbsoluteTimeGetCurrent()

        let prepared = prepare(image)
        log("view-content float size=\(Int(prepared.size.width))x\(Int(prepared.size.height)) +\(elapsed())ms")
        configureAudioSession()
        discardPlayback()

        guard let window = explicitHostView else {
            status = .failed("Cod couldn't attach the floating view to the share screen.")
            return
        }

        let sourceView = UIView(frame: CGRect(x: 12, y: window.safeAreaInsets.top + 12, width: 2, height: 2))
        sourceView.backgroundColor = .clear
        sourceView.isUserInteractionEnabled = false
        window.addSubview(sourceView)
        hostView = sourceView

        let contentController = ImagePiPViewController(image: prepared)
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentController
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip
        videoCallContentController = contentController
        log("view-content controller created +\(elapsed())ms possible=\(pip.isPictureInPicturePossible)")
        startWhenPossible()
    }

    /// The AVPlayerLayer PiP handoff renders gray when its owner is a Share
    /// extension. A sample-buffer content source gives AVKit the actual still
    /// frame directly and avoids that player/scene handoff.
    private func floatUsingSampleBuffer(_ image: UIImage) {
        currentImage = image
        status = .preparing
        prepareTask?.cancel()
        startedAt = CFAbsoluteTimeGetCurrent()

        let prepared = prepare(image)
        log("sample-buffer float size=\(Int(prepared.size.width))x\(Int(prepared.size.height)) +\(elapsed())ms")
        configureAudioSession()
        discardPlayback()

        guard let sample = Self.makeStillSampleBuffer(from: prepared) else {
            status = .failed("Cod couldn't create a video frame from that image.")
            return
        }

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.preventsDisplaySleepDuringVideoPlayback = false

        var timebase: CMTimebase?
        let timebaseStatus = CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        guard timebaseStatus == noErr, let timebase else {
            status = .failed("Cod couldn't create the timing source for Picture in Picture.")
            return
        }
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 1)
        layer.controlTimebase = timebase

        sampleBufferLayer = layer
        sampleBufferTimebase = timebase
        guard attachHostView() else {
            discardPlayback()
            status = .failed("Cod couldn't attach the floating frame to the share screen.")
            return
        }

        layer.sampleBufferRenderer.enqueue(sample)
        log("sample buffer enqueued +\(elapsed())ms")

        prepareTask = Task { @MainActor in
            defer { prepareTask = nil }
            await waitForSampleBufferReady(layer)
            guard !Task.isCancelled, status == .preparing else { return }
            makeController()
            startWhenPossible()
        }
    }

    private static func makeStillSampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let pixelBuffer = image.pixelBuffer() else { return nil }

        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &description
        ) == noErr, let description else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .positiveInfinity,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: description,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }

    private func waitForSampleBufferReady(_ layer: AVSampleBufferDisplayLayer) async {
        for _ in 0..<40 {
            if #available(iOS 17.4, *), layer.isReadyForDisplay {
                log("sample layer ready +\(elapsed())ms")
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        log("sample layer readiness timed out; renderer=\(layer.sampleBufferRenderer.status.rawValue) error=\(layer.sampleBufferRenderer.error?.localizedDescription ?? "none")")
    }
    #endif

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
        keepCodOpenAfterFloating()
        controller?.stopPictureInPicture()
        teardown()
    }

    /// A deliberate Open Cod/restore/stop action takes precedence over the
    /// delayed automatic return. The next Float resets this per-request policy.
    func keepCodOpenAfterFloating() {
        returnPolicy.keepCodOpen()
        returnTask?.cancel()
        returnTask = nil
        suspendedAt = nil
        #if COD_PERSONAL && !APP_EXTENSION
        SourceAppReturn.shared.discard()
        #endif
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
        #if APP_EXTENSION
        guard let sampleBufferLayer, controller == nil else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferLayer,
            playbackDelegate: self
        )
        let pip: AVPictureInPictureController? = AVPictureInPictureController(contentSource: source)
        #else
        guard let playerLayer, controller == nil else { return }
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        #endif
        pip?.delegate = self
        // A looping still has no meaningful timeline; hide the scrubber.
        pip?.requiresLinearPlayback = true
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip
        log("controller created +\(elapsed())ms nil=\(pip == nil)")

        // Suppress the overlay *before* the window opens, otherwise iOS shows
        // the full control set on appearance and takes seconds to fade it out.
        #if COD_PERSONAL && !APP_EXTENSION
        if AppSettings.shared.hideFloatingControls { applyControlsStyle(.hidden) }
        #endif
    }

    #if COD_PERSONAL
    private enum ControlsStyle: Int {
        case standard = 0
        case hidden = 2
    }

    /// Undocumented `AVPictureInPictureController.controlsStyle`. There is no
    /// public way to hide the play/close/restore overlay — `requiresLinearPlayback`
    /// only drops the skip buttons.
    ///
    /// Guarded on the setter existing: a bare `setValue(_:forKey:)` against a
    /// missing key raises `NSUnknownKeyException`, which Swift cannot catch, so
    /// a future iOS dropping this would be an uncatchable crash rather than a
    /// cosmetic regression.
    private func applyControlsStyle(_ style: ControlsStyle) {
        guard let controller else { return }
        guard controller.responds(to: NSSelectorFromString("setControlsStyle:")) else {
            log("controlsStyle unavailable — leaving the system overlay alone")
            return
        }
        controller.setValue(style.rawValue, forKey: "controlsStyle")
        log("controlsStyle=\(style.rawValue)")
    }
    #endif

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
    /// either a delegate callback or an error in a Share extension. Retrying
    /// the same active controller works; do that automatically while the
    /// request is still preparing.
    private func requestPiPStart(_ controller: AVPictureInPictureController) {
        #if !APP_EXTENSION
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
        #endif
        log("starting PiP +\(elapsed())ms")
        controller.startPictureInPicture()

        startRetry?.cancel()
        startRetry = Task { @MainActor [weak self, weak controller] in
            guard let self, let controller else { return }
            for attempt in 1...3 {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled, self.controller === controller, self.status == .preparing,
                      !controller.isPictureInPictureActive else { return }
                #if !APP_EXTENSION
                guard self.hostView?.window?.windowScene?.activationState == .foregroundActive else { continue }
                #endif
                self.log("retrying PiP start (\(attempt)/3) +\(self.elapsed())ms")
                controller.startPictureInPicture()
            }
        }
    }

    private func scheduleStartTimeout() {
        startTimeout?.cancel()
        startTimeout = Task { @MainActor in
            #if APP_EXTENSION
            // Extensions get a short foreground lifetime. If AVKit still says
            // PiP is impossible after this window, waiting longer only makes
            // the share sheet look frozen.
            let timeout: UInt64 = 8_000_000_000
            #else
            let timeout: UInt64 = 25_000_000_000
            #endif
            try? await Task.sleep(nanoseconds: timeout)
            guard !Task.isCancelled, self.status == .preparing else { return }
            self.log("TIMED OUT — PiP never started")
            // Deliberately does NOT tear down. AVKit can open the window well
            // after we've given up, and destroying the player mid-handover was
            // itself making the launch intermittent.
            self.status = .failed(
                "iOS hasn't opened the window yet. Another app may be holding Picture in Picture — force-quit video apps and try again."
            )
        }
    }

    // MARK: - Plumbing

    private func prepare(_ image: UIImage) -> UIImage {
        let normalized = image.normalizedUp()
        let fitted = normalized.fitted(within: CGSize(width: maxRenderEdge, height: maxRenderEdge))
        // H.264 requires even dimensions; odd ones skew or fail to encode.
        let evenSize = CGSize(
            width: max(2, (fitted.size.width / 2).rounded(.down) * 2),
            height: max(2, (fitted.size.height / 2).rounded(.down) * 2)
        )
        guard evenSize != fitted.size else { return fitted }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: evenSize, format: format).image { _ in
            fitted.draw(in: CGRect(origin: .zero, size: evenSize))
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let mixes = AppSettings.shared.keepOtherAudioPlaying
        do {
            // Mixable keeps the user's music alive but makes Cod a secondary
            // audio app, which can cost the background time the window needs.
            try session.setCategory(.playback, mode: .moviePlayback, options: mixes ? [.mixWithOthers] : [])
            try session.setActive(true)
            log("audio session active, mixWithOthers=\(mixes)")
        } catch {
            log("AUDIO SESSION FAILED: \(error.localizedDescription)")
        }
    }

    private func attachHostView() -> Bool {
        if hostView != nil { return true }
        let renderingLayer: CALayer?
        if let sampleBufferLayer {
            renderingLayer = sampleBufferLayer
        } else {
            renderingLayer = playerLayer
        }
        guard let renderingLayer else {
            log("NO RENDERING LAYER — cannot attach the floating host view")
            return false
        }
        #if APP_EXTENSION
        guard let window = explicitHostView else {
            log("NO EXTENSION HOST VIEW — cannot host the layer")
            return false
        }
        #else
        guard let window = explicitHostView ?? UIApplication.shared.activeWindow else {
            log("NO KEY WINDOW — cannot host the layer")
            return false
        }
        #endif

        let width: CGFloat = 140
        let container = UIView(frame: CGRect(x: 12, y: window.safeAreaInsets.top + 12, width: width, height: width))
        container.isUserInteractionEnabled = false
        container.backgroundColor = .black
        container.alpha = Self.showsRenderProbe ? 1.0 : 0.02
        renderingLayer.frame = container.bounds
        container.layer.addSublayer(renderingLayer)
        window.addSubview(container)
        if Self.showsRenderProbe {
            window.bringSubviewToFront(container)
        } else {
            window.sendSubviewToBack(container)
        }
        hostView = container
        log("host view attached probe=\(Self.showsRenderProbe)")
        return true
    }

    /// Releases player-side state without touching status or the audio session.
    private func discardPlayback() {
        readinessWait?.finish(.cancelled)
        readinessWait = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        sampleBufferLayer?.sampleBufferRenderer.flush(removingDisplayedImage: true) {}
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        sampleBufferTimebase = nil
        #if APP_EXTENSION
        videoCallContentController = nil
        #endif
        hostView?.removeFromSuperview()
        hostView = nil
        if let clipURL { try? FileManager.default.removeItem(at: clipURL) }
        clipURL = nil
    }

    private func teardown(keepStatus: Bool = false) {
        returnTask?.cancel()
        returnTask = nil
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
        sampleBufferLayer?.sampleBufferRenderer.flush(removingDisplayedImage: true) {}
        sampleBufferLayer?.removeFromSuperlayer()
        sampleBufferLayer = nil
        sampleBufferTimebase = nil
        #if APP_EXTENSION
        videoCallContentController = nil
        #endif
        hostView?.removeFromSuperview()
        hostView = nil
        controller = nil
        suspendedAt = nil
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

    /// The overlay is suppressed only for the appearance animation. Once the
    /// window has settled, normal controls go back so tapping it still gives
    /// you close and restore — hidden by default, revealed on demand.
    private func restoreControlsAfterAppearance() {
        #if COD_PERSONAL
        guard AppSettings.shared.hideFloatingControls else { return }
        let appearingController = controller
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard status == .active, controller === appearingController else { return }
            applyControlsStyle(.standard)
        }
        #endif
    }

    /// Best-effort return after PiP. Restore the identified share host or an
    /// available system Back-to destination before the legacy Home fallback.
    /// These private APIs are not a public navigation contract.
    private func returnToPreviousApp() {
        #if !COD_PERSONAL || APP_EXTENSION
        // Public builds leave navigation to the user. No suspension, source
        // app activation, or synthetic system Back-to action is attempted.
        return
        #else
        guard AppSettings.shared.returnAfterFloating, returnPolicy.allowsAutomaticReturn else { return }
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            // Let the handover animation finish before yanking the app away.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, returnPolicy.allowsAutomaticReturn, status == .active,
                  controller?.isPictureInPictureActive == true,
                  UIApplication.shared.applicationState == .active else { return }

            let application = UIApplication.shared
            let returnHome = SourceAppReturn.shared.shouldReturnHome
            let returned = await SourceAppReturn.shared.returnToSource()
            guard !Task.isCancelled, returnPolicy.allowsAutomaticReturn else { return }
            if returned {
                log("source-screen return request accepted; visual destination needs confirmation")
                suspendedAt = CFAbsoluteTimeGetCurrent()
                return
            }
            guard !Task.isCancelled, returnPolicy.allowsAutomaticReturn, status == .active,
                  controller?.isPictureInPictureActive == true,
                  application.applicationState == .active else { return }
            let lastAppSelector = NSSelectorFromString("suspendReturningToLastApp:")
            if !returnHome, application.responds(to: lastAppSelector),
               let method = class_getInstanceMethod(type(of: application), lastAppSelector),
               method_getNumberOfArguments(method) == 3,
               let argumentType = method_copyArgumentType(method, 2) {
                let resultType = method_copyReturnType(method)
                defer { free(resultType); free(argumentType) }
                // Verify the signature before invoking an undocumented IMP.
                // BOOL uses B on current arm64, c on some older runtimes.
                let result = String(cString: resultType)
                let argument = String(cString: argumentType)
                if result == "v", argument == "B" || argument == "c" {
                    log("requesting return to last app (private API; destination unconfirmed)")
                    suspendedAt = CFAbsoluteTimeGetCurrent()
                    let implementation = method_getImplementation(method)
                    if argument == "B" {
                        typealias ReturnToLastApp = @convention(c) (UIApplication, Selector, Bool) -> Void
                        unsafeBitCast(implementation, to: ReturnToLastApp.self)(application, lastAppSelector, true)
                    } else {
                        typealias ReturnToLastApp = @convention(c) (UIApplication, Selector, Int8) -> Void
                        unsafeBitCast(implementation, to: ReturnToLastApp.self)(application, lastAppSelector, 1)
                    }
                    return
                }
                log("last-app return signature unsupported: \(result)/\(argument)")
            }

            let selector = NSSelectorFromString("suspend")
            guard application.responds(to: selector) else {
                log("suspend unavailable on this iOS — staying in the app")
                return
            }
            log(returnHome ? "temporary screenshot/Home source; returning directly to Home" : "last-app return unavailable; falling back to Home")
            suspendedAt = CFAbsoluteTimeGetCurrent()
            application.perform(selector)
        }
        #endif
    }

    private func log(_ message: String) {
        // Plain stdout so `devicectl device process launch --console` picks it
        // up without needing root. stdout block-buffers when redirected, so
        // flush or the tail never arrives.
        print("[CodPiP] \(message)")
        fflush(stdout)
        CodDiagnosticLog.record("PiP \(message)")
        diagnosticsHandler?(message)
    }
}

/// User interaction wins over delayed navigation, including out-of-order
/// lifecycle events while PiP is still appearing.
struct PiPReturnPolicy {
    private(set) var allowsAutomaticReturn = true
    private(set) var isRestoring = false

    mutating func beginFloat() {
        allowsAutomaticReturn = true
        isRestoring = false
    }

    mutating func keepCodOpen() { allowsAutomaticReturn = false }

    mutating func beginRestoration() {
        allowsAutomaticReturn = false
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
            guard !self.returnPolicy.isRestoring else { return }
            self.log("DID START PiP +\(self.elapsed())ms")
            self.startTimeout?.cancel()
            self.startRetry?.cancel()
            self.status = .active
            Haptics.success()
            self.restoreControlsAfterAppearance()
            self.returnToPreviousApp()
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            self.returnPolicy.keepCodOpen()
            self.returnTask?.cancel()
            self.startRetry?.cancel()
            self.log("WILL STOP PiP")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else {
                self.log("ignoring stop callback from replaced controller")
                return
            }
            // Timing alone cannot identify a background failure: restoring the
            // window also brings Cod forward and stops PiP. Record foreground
            // state before suggesting that background playback was lost.
            if let suspendedAt = self.suspendedAt {
                let delta = Int((CFAbsoluteTimeGetCurrent() - suspendedAt) * 1000)
                self.log("DID STOP PiP — \(delta)ms after backgrounding")
                var isForeground = false
                #if !APP_EXTENSION
                isForeground = UIApplication.shared.applicationState == .active
                #endif
                self.log("stop context: foreground=\(isForeground)")
                if delta < 2500, !isForeground {
                    self.log("early background stop; cause unconfirmed. mixWithOthers=\(AppSettings.shared.keepOtherAudioPlaying)")
                    self.lostToBackgrounding = true
                }
            } else {
                self.log("DID STOP PiP (user dismissed)")
            }
            self.suspendedAt = nil
            self.teardown()
        }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            guard let owned = self.controller, owned === controller else { return }
            if self.returnPolicy.isRestoring {
                self.log("PiP start ended during user restoration; preserving restored image UI")
                self.teardown()
                return
            }
            self.log("FAILED TO START: \(error)")
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
            self.keepCodOpenAfterFloating()
            self.returnPolicy.beginRestoration()
            self.startRetry?.cancel()
            self.startTimeout?.cancel()
            self.restorationImage = self.currentImage
            completionHandler(true)
        }
    }
}

#if APP_EXTENSION
@MainActor
private final class ImagePiPViewController: AVPictureInPictureVideoCallViewController {
    private let imageView: UIImageView

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(nibName: nil, bundle: nil)

        // AVKit owns the actual discrete window sizes. This communicates only
        // the image's natural aspect ratio, preserving every resize step iOS
        // offers instead of forcing a fixed window size.
        let aspect = image.size.width / max(image.size.height, 1)
        let width: CGFloat = 500
        preferredContentSize = CGSize(width: width, height: width / max(aspect, 0.05))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

extension PiPPinController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        Task { @MainActor in
            guard let timebase = self.sampleBufferTimebase else { return }
            CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
            pictureInPictureController.invalidatePlaybackState()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        Task { @MainActor in
            self.log("sample PiP render size=\(newRenderSize.width)x\(newRenderSize.height)")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        true
    }
}
#endif

#if !APP_EXTENSION
extension UIApplication {
    var activeWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
#endif
