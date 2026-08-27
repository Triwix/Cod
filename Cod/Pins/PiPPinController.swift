import AVFoundation
import AVKit
import Combine
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

    @Published private(set) var status: Status = .idle
    @Published private(set) var currentImage: UIImage?
    @Published private(set) var isPossible = false
    /// Set when a floating window died because Cod lost background time, so the
    /// UI can explain the audio-session trade instead of the window silently
    /// vanishing.
    @Published var lostToBackgrounding = false

    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()

    var isActive: Bool { status == .active }

    var lastError: String? {
        if case let .failed(message) = status { return message }
        return nil
    }

    private var controller: AVPictureInPictureController?
    private var player: AVQueuePlayer?
    private var loopObserver: NSObjectProtocol?
    private var readyObservation: NSKeyValueObservation?
    private var playerLayer: AVPlayerLayer?
    /// Start of the current float request, for stage timings.
    private var startedAt = CFAbsoluteTimeGetCurrent()
    /// When Cod last backgrounded itself, so we can tell a window the user
    /// closed from one iOS killed because the app lost background time.
    private var suspendedAt: CFAbsoluteTime?
    private var hostView: UIView?
    private var clipURL: URL?
    private var possibleObservation: NSKeyValueObservation?
    private var startTimeout: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    /// PiP renders into a window a few hundred points wide, so full-resolution
    /// screenshots buy nothing and cost encode time.
    private let maxRenderEdge: CGFloat = 1200

    /// Draws the player layer on screen while debugging. Off for normal use —
    /// the layer only has to exist and render, not be seen.
    static let showsRenderProbe = false

    private override init() {
        super.init()
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

        prepareTask = Task { @MainActor in
            defer { prepareTask = nil }
            do {
                let url = try await FloatingClip.make(from: Self.placeholderImage)
                guard controller == nil, status == .idle else { return }

                // Only claim the audio session early if doing so is silent.
                // Otherwise it would cut the user's music the moment they open
                // the crop surface, before they've asked for anything.
                if AppSettings.shared.keepOtherAudioPlaying { configureAudioSession() }
                try startPlayback(with: url)
                attachHostView()
                await waitForPlayerReady()
                makeController()
                log("prewarmed, possible=\(controller?.isPictureInPicturePossible ?? false)")
                observePossible()
            } catch {
                log("prewarm failed (harmless): \(error.localizedDescription)")
            }
        }
    }

    func float(_ image: UIImage) {
        guard isSupported else {
            status = .unsupported
            return
        }

        let wasPrewarmed = controller != nil && status == .idle
        currentImage = image
        status = .preparing
        prepareTask?.cancel()
        startedAt = CFAbsoluteTimeGetCurrent()

        prepareTask = Task { @MainActor in
            // Without this the task handle lingers after a float completes and
            // the `prepareTask == nil` guard blocks every future prewarm.
            defer { prepareTask = nil }
            let prepared = prepare(image)
            log("float() size=\(Int(prepared.size.width))x\(Int(prepared.size.height)) prewarmed=\(wasPrewarmed) +\(elapsed())ms")

            do {
                let url = try await FloatingClip.make(from: prepared)
                guard !Task.isCancelled else { return }
                log("clip encoded +\(elapsed())ms")

                // Already floating? Swap the clip in place; the PiP window
                // stays put and just shows the new snippet.
                if status == .active, let player {
                    swapClip(to: url, on: player)
                    return
                }

                configureAudioSession()

                // Warm path: player, layer and controller already exist, and
                // AVKit has had time to decide PiP is possible.
                if let player, controller != nil {
                    swapClip(to: url, on: player)
                    await waitForPlayerReady()
                    startWhenPossible()
                    return
                }

                // Cold path. A prewarm cancelled mid-setup can leave a partly
                // built player behind; clear it rather than orphaning it.
                discardPlayback()
                try startPlayback(with: url)
                attachHostView()
                await waitForPlayerReady()
                makeController()
                startWhenPossible()
            } catch {
                log("PREPARE FAILED: \(error)")
                status = .failed(error.localizedDescription)
            }
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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            readyObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                guard layer.isReadyForDisplay, !resumed else { return }
                resumed = true
                continuation.resume()
            }
            // Never hang the whole flow on this.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !resumed else { return }
                resumed = true
                self.log("layer readiness timed out — proceeding anyway")
                continuation.resume()
            }
        }
        readyObservation = nil
        log("layer ready for display +\(elapsed())ms")
    }

    private func elapsed() -> Int {
        Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
    }

    func stop() {
        controller?.stopPictureInPicture()
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
        pip?.requiresLinearPlayback = true
        pip?.canStartPictureInPictureAutomaticallyFromInline = false
        controller = pip
        log("controller created +\(elapsed())ms nil=\(pip == nil)")

        // Suppress the overlay *before* the window opens, otherwise iOS shows
        // the full control set on appearance and takes seconds to fade it out.
        if AppSettings.shared.hideFloatingControls { applyControlsStyle(.hidden) }
    }

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

    /// Watches eligibility during prewarm so the log shows how long AVKit
    /// really takes, without anything waiting on it.
    private func observePossible() {
        guard let controller, !controller.isPictureInPicturePossible else { return }
        let warmStart = CFAbsoluteTimeGetCurrent()
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor in
                guard let self else { return }
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
            log("starting PiP +\(elapsed())ms")
            controller.startPictureInPicture()
            scheduleStartTimeout()
            return
        }

        // The player needs to reach a playable state before AVKit will offer
        // the window.
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] pip, change in
            guard change.newValue == true else { return }
            Task { @MainActor in
                guard let self, self.status == .preparing else { return }
                self.log("became possible +\(self.elapsed())ms — starting PiP")
                self.isPossible = true
                pip.startPictureInPicture()
                self.possibleObservation = nil
            }
        }
        scheduleStartTimeout()
    }

    private func scheduleStartTimeout() {
        startTimeout?.cancel()
        startTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
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

    private func attachHostView() {
        guard hostView == nil, let playerLayer else { return }
        guard let window = UIApplication.shared.activeWindow else {
            log("NO KEY WINDOW — cannot host the layer")
            status = .failed("Cod couldn't find its window to attach the floating layer to.")
            return
        }

        let width: CGFloat = 140
        let container = UIView(frame: CGRect(x: 12, y: window.safeAreaInsets.top + 12, width: width, height: width))
        container.isUserInteractionEnabled = false
        container.backgroundColor = .black
        container.alpha = Self.showsRenderProbe ? 1.0 : 0.02
        playerLayer.frame = container.bounds
        container.layer.addSublayer(playerLayer)
        window.addSubview(container)
        if Self.showsRenderProbe {
            window.bringSubviewToFront(container)
        } else {
            window.sendSubviewToBack(container)
        }
        hostView = container
        log("host view attached probe=\(Self.showsRenderProbe)")
    }

    /// Releases player-side state without touching status or the audio session.
    private func discardPlayback() {
        readyObservation = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        hostView?.removeFromSuperview()
        hostView = nil
        if let clipURL { try? FileManager.default.removeItem(at: clipURL) }
        clipURL = nil
    }

    private func teardown(keepStatus: Bool = false) {
        startTimeout?.cancel()
        startTimeout = nil
        prepareTask?.cancel()
        prepareTask = nil
        possibleObservation = nil
        readyObservation = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        hostView?.removeFromSuperview()
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

    /// The overlay is suppressed only for the appearance animation. Once the
    /// window has settled, normal controls go back so tapping it still gives
    /// you close and restore — hidden by default, revealed on demand.
    private func restoreControlsAfterAppearance() {
        guard AppSettings.shared.hideFloatingControls else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard status == .active else { return }
            applyControlsStyle(.standard)
        }
    }

    /// Sends Cod to the background once the window is up, so you land back
    /// where you started rather than staring at Cod.
    ///
    /// This uses `UIApplication`'s private `suspend`, which is the same thing
    /// pressing Home does — and PiP demonstrably survives being backgrounded,
    /// which is the entire point of the feature. It is private API, so it can
    /// stop working on any iOS release; the setting exists so it can be turned
    /// off without a rebuild. Fine for a sideloaded personal app, not something
    /// to ship to the App Store.
    private func returnToPreviousApp() {
        guard AppSettings.shared.returnAfterFloating else { return }
        Task { @MainActor in
            // Let the handover animation finish before yanking the app away.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard status == .active else { return }

            let selector = NSSelectorFromString("suspend")
            guard UIApplication.shared.responds(to: selector) else {
                log("suspend unavailable on this iOS — staying in the app")
                return
            }
            log("returning to previous app")
            suspendedAt = CFAbsoluteTimeGetCurrent()
            UIApplication.shared.perform(selector)
        }
    }

    private func log(_ message: String) {
        // Plain stdout so `devicectl device process launch --console` picks it
        // up without needing root. stdout block-buffers when redirected, so
        // flush or the tail never arrives.
        print("[CodPiP] \(message)")
        fflush(stdout)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPPinController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.log("WILL START PiP +\(self.elapsed())ms") }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            self.log("DID START PiP +\(self.elapsed())ms")
            self.startTimeout?.cancel()
            self.status = .active
            Haptics.success()
            self.restoreControlsAfterAppearance()
            self.returnToPreviousApp()
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.log("WILL STOP PiP") }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in
            // A stop that lands within a couple of seconds of Cod backgrounding
            // itself wasn't the user tapping close — it's iOS pulling the
            // player's background time, which a mixable audio session forfeits.
            if let suspendedAt = self.suspendedAt {
                let delta = Int((CFAbsoluteTimeGetCurrent() - suspendedAt) * 1000)
                self.log("DID STOP PiP — \(delta)ms after backgrounding")
                if delta < 2500 {
                    self.log("DIAGNOSIS: window did not survive backgrounding. mixWithOthers=\(AppSettings.shared.keepOtherAudioPlaying)")
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
        completionHandler(true)
    }
}

// MARK: - Pixel buffers

extension UIImage {
    func pixelBuffer() -> CVPixelBuffer? {
        guard let cgImage else { return nil }
        let width = max(2, cgImage.width - (cgImage.width % 2))
        let height = max(2, cgImage.height - (cgImage.height % 2))

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
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
