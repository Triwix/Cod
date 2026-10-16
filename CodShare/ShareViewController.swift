import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Personal builds retain the legacy launch/crop flow. Public builds prepare
/// the latest image automatically and float it when the containing app opens.
final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareRootView>?
    private let state = ShareFloatState()
    private var sharedImage: UIImage?
    private var imageToFloat: UIImage?
    private var oneTapFloat = false
    private var hasPresentedSelection = false
    private var hasAppeared = false
    private var completed = false
    private var hasAttemptedHandoff = false
    private var handoffTask: Task<Void, Never>?
    private var imageLoadID: UUID?
    private var imageLoadProgress: Progress?
    private var imageLoadTimeout: Task<Void, Never>?

    private static let diagnosticQueue = DispatchQueue(label: "com.josh.cod.share-diagnostics")

    private func diagnostic(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        print("[CodShare] \(message)")
        Self.diagnosticQueue.async {
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = directory.appendingPathComponent("share-diagnostics.log")
            guard let data = line.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
                return
            }
            // Keep this quick to retrieve over a wireless device connection
            // without allowing months of share attempts to grow forever.
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 128 * 1_024 {
                try? data.write(to: url, options: .atomic)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Diagnostics must never interfere with the share action.
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        diagnostic("viewDidLoad")
        diagnostic("build=fast-share-20261015 process=\(ProcessInfo.processInfo.processIdentifier)")
        oneTapFloat = SharePreferences.shared.oneTapFloat
        diagnostic("share mode oneTapFloat=\(oneTapFloat)")
        view.backgroundColor = .systemBackground
        presentStatus()
        loadSharedImage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        // The responder chain is only usable once this view is attached to
        // the host window. Loading can finish before OR after that happens.
        presentImageIfReady()
    }

    private func loadSharedImage() {
        imageLoadTimeout?.cancel()
        imageLoadProgress?.cancel()
        imageLoadID = nil
        state.phase = .loading
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        diagnostic("received \(items.count) extension item(s)")
        guard let item = items.first else {
            diagnostic("no extension item")
            state.phase = .failed("No image was received. Share a single photo or screenshot with Cod.")
            return
        }

        let attachments = item.attachments ?? []
        diagnostic("received \(attachments.count) attachment(s)")
        guard let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            diagnostic("no image-conforming provider")
            state.phase = .failed("This item isn't an image. Share a single photo or screenshot with Cod.")
            return
        }
        diagnostic("image provider found; requesting file")
        diagnostic("image representation types=\(provider.registeredTypeIdentifiers.joined(separator: ","))")
        let requestID = UUID()
        imageLoadID = requestID
        imageLoadTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, !self.completed, self.imageLoadID == requestID else { return }
            self.imageLoadID = nil
            self.imageLoadProgress?.cancel()
            self.imageLoadProgress = nil
            self.imageLoadTimeout = nil
            self.diagnostic("image provider timed out")
            self.state.phase = .failed("This image is taking too long to load. Try again, or open it in Photos first so it can finish downloading.")
        }
        imageLoadProgress = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
            let bytes = url.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0
            self?.diagnostic("provider callback bytes=\(bytes) error=\(error?.localizedDescription ?? "none")")
            let image = url.flatMap(Self.memorySafeImage(at:))
            DispatchQueue.main.async {
                guard let self, !self.completed, self.imageLoadID == requestID else { return }
                if let image { self.completeImageLoad(image, requestID: requestID) }
                else { self.loadImageObject(from: provider, requestID: requestID) }
            }
        }
    }

    private func loadImageObject(from provider: NSItemProvider, requestID: UUID) {
        // Some native share sheets vend a securely archived UIImage for
        // public.image, not an ImageIO-readable PNG/JPEG file. Ask the typed
        // provider rather than treating arbitrary archive bytes as an image.
        if provider.canLoadObject(ofClass: UIImage.self) {
            diagnostic("file wasn't ImageIO-readable; requesting typed UIImage")
            imageLoadProgress = provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                let image = (object as? UIImage)?.boundedShareImage()
                self?.diagnostic("typed image callback error=\(error?.localizedDescription ?? "none")")
                DispatchQueue.main.async { self?.completeImageLoad(image, requestID: requestID) }
            }
        } else {
            // Legacy public.image providers can advertise only the abstract
            // image type. loadItem lets UIKit vend its native image object.
            diagnostic("requesting legacy public.image object")
            imageLoadProgress = nil // This legacy API has no cancellable Progress.
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] object, error in
                let image: UIImage?
                if let native = object as? UIImage { image = native.boundedShareImage() }
                else if let url = object as? URL { image = UIImage.decodedImage(at: url) }
                else if let data = object as? Data, data.count <= SharedImageInbox.maximumImageBytes {
                    image = UIImage(data: data)?.boundedShareImage()
                } else { image = nil }
                self?.diagnostic("legacy image callback class=\(object.map { String(describing: type(of: $0)) } ?? "none") error=\(error?.localizedDescription ?? "none")")
                DispatchQueue.main.async { self?.completeImageLoad(image, requestID: requestID) }
            }
        }
    }

    private func completeImageLoad(_ image: UIImage?, requestID: UUID) {
        guard !completed, imageLoadID == requestID else { return }
        imageLoadID = nil
        imageLoadTimeout?.cancel()
        imageLoadTimeout = nil
        imageLoadProgress = nil
        guard let image else {
            diagnostic("image decode failed")
            state.phase = .failed("Cod couldn't read this image. Try sharing it again from Photos.")
            return
        }
        diagnostic("decoded \(Int(image.pixelSize.width))x\(Int(image.pixelSize.height)); image ready")
        sharedImage = image
        presentImageIfReady()
    }

    /// Share extensions have a much smaller memory budget than apps. Decoding
    /// a modern camera image at full resolution, normalizing it, and then
    /// asking Vision to inspect it can exceed that budget before SwiftUI draws
    /// a frame. ImageIO creates an oriented thumbnail without first expanding
    /// the full source bitmap in memory.
    private static func memorySafeImage(at url: URL) -> UIImage? {
        UIImage.decodedImage(at: url)
    }

    private func presentStatus() {
        let root = ShareRootView(
            state: state,
            onFinish: { [weak self] in self?.finish() },
            onRetry: { [weak self] in
                guard let self, !self.completed, self.handoffTask == nil else { return }
                self.hasAttemptedHandoff = false
                if self.sharedImage == nil { self.loadSharedImage() }
                else if let image = self.imageToFloat { self.startFloat(image) }
                else { self.presentImageIfReady() }
            },
            onFloat: { [weak self] image in self?.startFloat(image) }
        )
        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .systemBackground
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        hosting = controller
    }

    private func presentImageIfReady() {
        guard hasAppeared, !completed, !hasAttemptedHandoff, let image = sharedImage else { return }
        #if COD_PERSONAL || COD_FAST_SHARE
        if oneTapFloat {
            startFloat(image)
        } else if !hasPresentedSelection {
            hasPresentedSelection = true
            diagnostic("presenting crop surface; waiting for manual Float")
            state.phase = .selecting(image)
        }
        #else
        // Selecting Cod is already the user's request. No extra Save/Done tap.
        startFloat(image)
        #endif
    }

    private func startFloat(_ image: UIImage) {
        guard hasAppeared, !completed, !hasAttemptedHandoff,
              handoffTask == nil else { return }
        imageToFloat = image
        hasAttemptedHandoff = true
        state.phase = .opening
        handoffTask = Task { @MainActor [weak self] in
            guard let self else { return }
            #if COD_PERSONAL
            let opened = await self.handoffForFloat(image)
            self.handoffTask = nil
            guard !self.completed else { return }
            if !opened {
                self.state.phase = .failed("iOS couldn't open Cod. Try again, or open Cod once before sharing.")
            }
            #else
            do {
                #if COD_FAST_SHARE
                // Crop-first mode already selected its image in this extension.
                // Each explicit retry gets a fresh ID, so old completions can
                // neither delete nor acknowledge the user's latest attempt.
                let id = try QuickFloatHandoff.shared.store(image, mode: .float)
                guard let url = QuickFloatLaunchRoute.configured?.url(for: id) else {
                    throw SharedImageInbox.InboxError.unavailable
                }
                self.diagnostic("fast share stored; opening containing app request=\(id)")
                let accepted = await FastShareAppLauncher.open(url, from: self)
                self.handoffTask = nil
                guard !self.completed else { return }
                if accepted { self.finish() }
                else {
                    self.state.phase = .failed("iOS couldn't open Cod. Try Again will retry this image. You can also open Cod directly to float it.")
                }
                #else
                try QuickFloatHandoff.shared.store(image, mode: self.oneTapFloat ? .float : .crop)
                self.handoffTask = nil
                guard !self.completed else { return }
                self.diagnostic("image queued automatically; no app launch requested")
                #if COD_LAUNCH_PROBE
                self.state.phase = .launchProbe
                #else
                self.finish()
                #endif
                #endif
            } catch {
                self.handoffTask = nil
                guard !self.completed else { return }
                self.state.phase = .failed(error.localizedDescription)
            }
            #endif
        }
    }

    #if COD_PERSONAL
    /// The extension cannot own durable PiP. Cod briefly comes forward to
    /// start the window; returning to the source app is best-effort private API.
    private func handoffForFloat(_ image: UIImage) async -> Bool {
        diagnostic("Float oneTap=\(oneTapFloat); image=\(Int(image.pixelSize.width))x\(Int(image.pixelSize.height))")
        let host = ShareSourceContext.bundleIdentifier(from: self, diagnostic: diagnostic)
        let screenshotOrigin = host == "com.apple.ScreenshotServicesService"
            ? ShareSourceContext.screenshotOrigin(from: extensionContext?.inputItems as? [NSExtensionItem] ?? [], diagnostic: diagnostic)
            : nil
        let source = screenshotOrigin ?? host
        diagnostic("share source=\(source ?? "unknown")")
        guard ShareFloatHandoff.store(image, sourceBundleIdentifier: source) else {
            diagnostic("float handoff image encoding failed")
            return false
        }
        diagnostic("float handoff stored; requesting containing app")

        // This is the public request. Share extensions usually receive false,
        // but trying it first keeps the supported path available on any system
        // version that elects to honor it.
        let publiclyOpened = await requestOpen(label: "extension context") { completion in
            guard let context = extensionContext else {
                completion(false)
                return
            }
            context.open(ShareFloatHandoff.url, completionHandler: completion)
        }
        guard !completed else { return false }
        if publiclyOpened {
            diagnostic("containing app opened through extension context")
            finish()
            return true
        }

        // Cod is a sideloaded personal utility and already uses the private
        // UIApplication selectors to background itself. The
        // responder-chain launch is the inverse operation. It may stop working
        // on a future iOS release, so failure is surfaced rather than hidden.
        let privatelyOpened = await openThroughResponderChain(ShareFloatHandoff.url)
        diagnostic("responder-chain containing-app request=\(privatelyOpened)")
        if privatelyOpened { finish() }
        return privatelyOpened
    }

    private func openThroughResponderChain(_ url: URL) async -> Bool {
        var responder: UIResponder? = self
        var visited = Set<ObjectIdentifier>()
        while let candidate = responder,
              visited.insert(ObjectIdentifier(candidate)).inserted, visited.count <= 32 {
            diagnostic("launch responder=\(String(describing: type(of: candidate)))")
            if let application = candidate as? UIApplication {
                return await requestOpen(label: "responder-chain UIApplication") { completion in
                    application.open(url, options: [:], completionHandler: completion)
                }
            }
            responder = candidate.next
        }
        diagnostic("no UIApplication found in responder chain")
        return false
    }

    /// Finding a responder is not evidence that iOS accepted the launch. Read
    /// the real callback, and release the share UI if the callback never comes.
    private func requestOpen(
        label: String,
        perform: (@escaping @Sendable (Bool) -> Void) -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let attempt = URLLaunchAttempt(continuation: continuation)
            attempt.timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                self?.diagnostic("\(label) launch callback timed out")
                attempt.finish(false)
            }
            perform { [weak self] opened in
                Task { @MainActor in
                    self?.diagnostic("\(label) launch callback accepted=\(opened)")
                    attempt.finish(opened)
                }
            }
        }
    }
    #endif

    private func finish() {
        guard !completed else { return }
        completed = true
        imageLoadID = nil
        imageLoadTimeout?.cancel()
        imageLoadTimeout = nil
        imageLoadProgress?.cancel()
        imageLoadProgress = nil
        diagnostic("completeRequest")
        extensionContext?.completeRequest(returningItems: nil)
    }
}

#if COD_PERSONAL
@MainActor
private final class URLLaunchAttempt {
    private var continuation: CheckedContinuation<Bool, Never>?
    var timeout: Task<Void, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ opened: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        continuation.resume(returning: opened)
    }
}
#endif
