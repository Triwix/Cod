import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Prepares the shared image using an App Group. Opening Cod is always the
/// user's action, either manually or by tapping an optional notification.
final class ShareViewController: UIViewController {
    private var hosting: UIHostingController<ShareRootView>?
    private let state = ShareFloatState()
    private var sharedImage: UIImage?
    private var imageToFloat: UIImage?
    private var oneTapFloat = false
    private var useFloatNotification = false
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
        diagnostic("build=supported-only-6 process=\(ProcessInfo.processInfo.processIdentifier)")
        oneTapFloat = SharePreferences.shared.oneTapFloat
        useFloatNotification = SharePreferences.shared.useFloatNotification
        diagnostic("share mode oneTapFloat=\(oneTapFloat)")
        view.backgroundColor = .systemBackground
        presentStatus()
        loadSharedImage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        // Loading may finish before the extension's crop/status UI appears.
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
        if useFloatNotification {
            if oneTapFloat { startFloat(image) }
            else if !hasPresentedSelection {
                hasPresentedSelection = true
                state.phase = .selecting(image)
            }
            return
        }
        // Selecting Cod is already the user's request. No extra Save/Done tap.
        startFloat(image)
    }

    private func startFloat(_ image: UIImage) {
        guard hasAppeared, !completed, !hasAttemptedHandoff,
              handoffTask == nil else { return }
        imageToFloat = image
        hasAttemptedHandoff = true
        state.phase = .opening
        handoffTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.useFloatNotification {
                do {
                    let id = try QuickFloatHandoff.shared.store(image, mode: .float)
                    try await ShareFloatNotifications().schedule(id)
                    self.handoffTask = nil
                    guard !self.completed else { return }
                    self.diagnostic("notification handoff accepted request=\(id)")
                    self.finish()
                } catch {
                    self.handoffTask = nil
                    guard !self.completed else { return }
                    self.diagnostic("notification handoff failed: \(error.localizedDescription)")
                    self.state.phase = .failed(error.localizedDescription)
                }
                return
            }
            do {
                try QuickFloatHandoff.shared.store(image, mode: self.oneTapFloat ? .float : .crop)
                self.handoffTask = nil
                guard !self.completed else { return }
                self.diagnostic("image queued automatically; no app launch requested")
                self.finish()
            } catch {
                self.handoffTask = nil
                guard !self.completed else { return }
                self.state.phase = .failed(error.localizedDescription)
            }
        }
    }


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
