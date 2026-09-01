import Combine
import Photos
import SwiftUI

/// Central brain: owns the capture that's currently on the crop surface, runs
/// the instant actions, and routes anything that needs its own UI.
@MainActor
final class CaptureCoordinator: ObservableObject {
    struct Pending: Identifiable, Equatable {
        let id = UUID()
        var image: UIImage
        var origin: Snap.Origin

        static func == (lhs: Pending, rhs: Pending) -> Bool { lhs.id == rhs.id }
    }

    struct Route: Identifiable {
        enum Kind {
            case share([Any])
            case barcodes([Recognizer.BarcodeHit])
            case text(String)
            case translate(String)
            case annotate(UIImage)
            case confirmUpload(UIImage)
        }

        let id = UUID()
        var kind: Kind
    }

    @Published var pending: Pending?
    @Published var route: Route?
    @Published var toast: Toast?
    @Published var isWorking = false
    /// True when Cod was opened purely to float something, so the UI can stay
    /// out of the way instead of flashing the whole app.
    @Published var floatOnlyLaunch = false

    let store: SnapStore
    let settings: AppSettings
    let pins: PinManager
    let pip: PiPPinController

    /// `CGRect` only gained `Hashable` conformance in iOS 18. The app targets
    /// iOS 17, and the actual crop is integral anyway, so key history entries
    /// by the pixel rectangle that was written rather than the fractional drag
    /// rectangle.
    /// History entries already written for the crop currently on screen, keyed
    /// by selection rect — so pinning *and then* copying text from the same
    /// selection updates one entry instead of creating two.
    private var archivedCrops: [PixelRectKey: Snap.ID] = [:]
    private var pipStatusCancellable: AnyCancellable?
    private var isAwaitingFloatResult = false
    private var dismissSelectionOnFloatSuccess = false

    init(
        store: SnapStore,
        settings: AppSettings,
        pins: PinManager,
        pip: PiPPinController
    ) {
        self.store = store
        self.settings = settings
        self.pins = pins
        self.pip = pip
        observePiPStatus()
    }

    convenience init() {
        self.init(
            store: .shared,
            settings: .shared,
            pins: .shared,
            pip: .shared
        )
    }

    // MARK: - Ingestion

    func present(image: UIImage, origin: Snap.Origin) {
        let normalized = image.normalizedUp()
        archivedCrops.removeAll()
        Haptics.prepare()

        switch settings.arrivalMode {
        case .selection:
            withAnimation(.easeOut(duration: 0.22)) {
                pending = Pending(image: normalized, origin: origin)
            }
            // AVKit takes seconds to make PiP available the first time. Start
            // that clock now, while the user is choosing a region, so tapping
            // Float feels immediate rather than looking like a hang.
            if settings.enabledActions.contains(.float) { pip.prewarm() }
        case .instant:
            let rect = CGRect(origin: .zero, size: normalized.pixelSize)
            run(settings.instantAction, image: normalized, rect: rect, origin: origin, dismiss: false)
        case .library:
            if settings.historyLimit == .off {
                // Arrival mode and history can be configured independently.
                // Falling back to selection avoids claiming an image was filed
                // when the store immediately discards it.
                pending = Pending(image: normalized, origin: origin)
                toast = .info("History is off", "Select a region instead, or enable History in Settings.")
                if settings.enabledActions.contains(.float) { pip.prewarm() }
            } else {
                store.add(image: normalized, origin: origin)
                toast = .success("Added to library")
            }
        }
    }

    /// Straight to the floating window — no crop surface, no action bar.
    /// This is the path the Shortcuts/share-sheet entries use.
    func floatImmediately(
        image: UIImage,
        origin: Snap.Origin = .shared,
        minimalUI: Bool = false
    ) {
        let normalized = image.normalizedUp()
        pending = nil
        archivedCrops.removeAll()
        if minimalUI { floatOnlyLaunch = true }
        startFloating(normalized, dismissSelectionOnSuccess: false)

        if pip.status != .unsupported {
            archive(normalized, rect: CGRect(origin: .zero, size: normalized.pixelSize), origin: origin)
        }
    }

    /// Floats the newest screenshot whole, for Back Tap / Action Button.
    func floatLatestScreenshot(minimalUI: Bool = false) async {
        // Start AVKit warming while Photos is still fetching.
        pip.prewarm()
        if minimalUI { floatOnlyLaunch = true }
        do {
            guard await waitForScreenshotSettle() else {
                floatOnlyLaunch = false
                return
            }
            let hit = try await PhotoLibraryService.latestScreenshot()
            settings.lastSeenScreenshotID = hit.localIdentifier
            floatImmediately(image: hit.image, origin: .screenshot, minimalUI: minimalUI)
        } catch {
            floatOnlyLaunch = false
            toast = .failure("Couldn't load screenshot", error.localizedDescription)
        }
    }

    func dismissSelection() {
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }

    /// Pulls the newest item from the Screenshots album onto the crop surface.
    func captureLatestScreenshot(force: Bool = true) async {
        do {
            // Give Photos time to commit a screenshot before asking which asset
            // is newest. Waiting after the fetch only delays an already-stale
            // result and defeats the setting's purpose.
            guard await waitForScreenshotSettle() else { return }
            let hit = try await PhotoLibraryService.latestScreenshot()
            if !force, hit.localIdentifier == settings.lastSeenScreenshotID { return }
            settings.lastSeenScreenshotID = hit.localIdentifier
            present(image: hit.image, origin: .screenshot)
        } catch {
            toast = .failure("Couldn't load screenshot", error.localizedDescription)
        }
    }

    /// Returns false when the enclosing capture task was cancelled while
    /// waiting, so a stale intent cannot surface an image later.
    private func waitForScreenshotSettle() async -> Bool {
        guard settings.captureDelay > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(
                nanoseconds: UInt64(settings.captureDelay * 1_000_000_000)
            )
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    func pasteFromClipboard() {
        guard let image = UIPasteboard.general.image else {
            toast = .failure("Clipboard has no image")
            Haptics.warning()
            return
        }
        present(image: image, origin: .pasted)
    }

    func reopen(_ snap: Snap) {
        guard let image = store.image(for: snap) else {
            toast = .failure("That capture is missing its image")
            return
        }
        archivedCrops.removeAll()
        withAnimation(.easeOut(duration: 0.22)) {
            pending = Pending(image: image, origin: snap.origin)
        }
    }

    // MARK: - Running actions

    func run(
        _ action: SnapAction,
        image: UIImage,
        rect: CGRect,
        origin: Snap.Origin = .unknown,
        dismiss: Bool = true
    ) {
        // Pinning keeps the crop surface up so you can pull several snippets
        // out of one screenshot in a row. Floating keeps it only until the
        // system window confirms success, so a failed attempt is still usable.
        let keepSurface = action == .pin || action == .float
        if dismiss && !keepSurface { dismissSelection() }

        Task { await perform(action, image: image, rect: rect, origin: origin) }
    }

    private func perform(_ action: SnapAction, image: UIImage, rect: CGRect?, origin: Snap.Origin) async {
        switch action {
        case .copyImage:
            UIPasteboard.general.image = image
            archive(image, rect: rect, origin: origin)
            toast = .success("Image copied")
            Haptics.success()

        case .copyText:
            await copyText(from: image, rect: rect, origin: origin)

        case .save:
            await save(image, rect: rect, origin: origin)

        case .share:
            archive(image, rect: rect, origin: origin)
            route = Route(kind: .share([image]))

        case .float:
            archive(image, rect: rect, origin: origin)
            startFloating(image, dismissSelectionOnSuccess: true)

        case .pin:
            pins.add(image: image)
            archive(image, rect: rect, origin: origin)
            if settings.autoCopyOnCapture { UIPasteboard.general.image = image }

        case .qr:
            await scanCodes(in: image, rect: rect, origin: origin)

        case .translate:
            await translate(image, rect: rect, origin: origin)

        case .annotate:
            archive(image, rect: rect, origin: origin)
            route = Route(kind: .annotate(image))

        case .upload:
            archive(image, rect: rect, origin: origin)
            route = Route(kind: .confirmUpload(image))
        }
    }

    // MARK: - Individual actions

    private func copyText(from image: UIImage, rect: CGRect?, origin: Snap.Origin) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Recognizer.recognizeText(in: image)
            guard !result.isEmpty else {
                toast = .failure("No text found", "Try a tighter crop, or switch OCR to Accurate.")
                Haptics.warning()
                return
            }
            UIPasteboard.general.string = result.text
            archive(image, rect: rect, origin: origin, text: result.text)
            let preview = result.text.replacingOccurrences(of: "\n", with: " ")
            toast = .success("Text copied", String(preview.prefix(60)))
            Haptics.success()
        } catch {
            toast = .failure("OCR failed", error.localizedDescription)
        }
    }

    private func save(_ image: UIImage, rect: CGRect?, origin: Snap.Origin) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let requestedAlbum = settings.saveToDedicatedAlbum ? settings.albumName : nil
            let destination = try await PhotoLibraryService.save(image, toAlbumNamed: requestedAlbum)
            archive(image, rect: rect, origin: origin)
            switch destination {
            case let .album(name):
                toast = .success("Saved to Photos", "Album: \(name)")
            case .library where requestedAlbum?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false:
                toast = .success("Saved to Photos", "Dedicated albums need Full Photos Access; saved to Recents instead.")
            case .library:
                toast = .success("Saved to Photos")
            }
            Haptics.success()
        } catch {
            toast = .failure("Couldn't save", error.localizedDescription)
            Haptics.warning()
        }
    }

    private func scanCodes(in image: UIImage, rect: CGRect?, origin: Snap.Origin) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let hits = try await Recognizer.detectBarcodes(in: image)
            guard !hits.isEmpty else {
                toast = .failure("No codes found", "Make sure the whole code is inside the crop.")
                Haptics.warning()
                return
            }
            archive(image, rect: rect, origin: origin, barcodes: hits.map(\.payload))
            route = Route(kind: .barcodes(hits))
            Haptics.success()
        } catch {
            toast = .failure("Scan failed", error.localizedDescription)
        }
    }

    private func translate(_ image: UIImage, rect: CGRect?, origin: Snap.Origin) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Recognizer.recognizeText(in: image)
            guard !result.isEmpty else {
                toast = .failure("No text to translate")
                Haptics.warning()
                return
            }
            archive(image, rect: rect, origin: origin, text: result.text)
            route = Route(kind: .translate(result.text))
        } catch {
            toast = .failure("OCR failed", error.localizedDescription)
        }
    }

    // MARK: - Pin menu actions

    func run(pinAction: PinAction, pin: Pin) {
        switch pinAction {
        case .copyImage:
            UIPasteboard.general.image = pin.image
            toast = .success("Image copied")
        case .copyText:
            Task { await copyText(from: pin.image, rect: nil, origin: .unknown) }
        case .save:
            Task { await save(pin.image, rect: nil, origin: .unknown) }
        case .share:
            route = Route(kind: .share([pin.image]))
        case .sendToPiP:
            startFloating(pin.image, dismissSelectionOnSuccess: false)
        case .recrop:
            withAnimation { pending = Pending(image: pin.image, origin: .unknown) }
        }
    }

    // MARK: - Floating

    private func observePiPStatus() {
        pipStatusCancellable = pip.$status
            .sink { @MainActor [weak self] status in
                self?.handlePiPStatus(status)
            }
    }

    private func startFloating(_ image: UIImage, dismissSelectionOnSuccess: Bool) {
        isAwaitingFloatResult = true
        self.dismissSelectionOnFloatSuccess = dismissSelectionOnSuccess
        isWorking = true
        toast = .info("Opening floating window…")
        pip.float(image)
    }

    private func handlePiPStatus(_ status: PiPPinController.Status) {
        guard isAwaitingFloatResult else { return }

        switch status {
        case .idle:
            finishFloatAttempt()

        case .preparing:
            break

        case .active:
            let shouldDismiss = dismissSelectionOnFloatSuccess
            finishFloatAttempt()
            if shouldDismiss { dismissSelection() }
            toast = .info("Floating", "The snippet is now in the system window.")

        case .unsupported:
            finishFloatAttempt()
            floatOnlyLaunch = false
            toast = .failure(
                "Not available here",
                "Floating needs Picture in Picture, which the Simulator doesn't have."
            )

        case let .failed(message):
            finishFloatAttempt()
            floatOnlyLaunch = false
            toast = .failure("Couldn't start floating", message)
        }
    }

    private func finishFloatAttempt() {
        isAwaitingFloatResult = false
        dismissSelectionOnFloatSuccess = false
        isWorking = false
    }

    // MARK: - History

    /// Writes the crop to history, or enriches the entry already written for
    /// this same selection. A `nil` rect means "don't file this at all"
    /// (actions run from a pin's menu, where the snippet is already in there).
    private func archive(
        _ image: UIImage,
        rect: CGRect?,
        origin: Snap.Origin,
        text: String? = nil,
        barcodes: [String] = []
    ) {
        guard settings.historyLimit != .off, let rect else { return }

        let key = PixelRectKey(rect)
        if let existingID = archivedCrops[key],
           var existing = store.snaps.first(where: { $0.id == existingID }) {
            if let text { existing.recognizedText = text }
            if !barcodes.isEmpty { existing.barcodes = barcodes }
            store.update(existing)
            return
        }

        let snap = store.add(image: image, origin: origin, recognizedText: text, barcodes: barcodes)
        archivedCrops[key] = snap.id
    }
}
