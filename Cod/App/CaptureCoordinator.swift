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

    /// History entries already written for the crop currently on screen, keyed
    /// by selection rect — so pinning *and then* copying text from the same
    /// selection updates one entry instead of creating two.
    private var archivedCrops: [CGRect: Snap.ID] = [:]

    init(
        store: SnapStore = .shared,
        settings: AppSettings = .shared,
        pins: PinManager = .shared,
        pip: PiPPinController = .shared
    ) {
        self.store = store
        self.settings = settings
        self.pins = pins
        self.pip = pip
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
            store.add(image: normalized, origin: origin)
            toast = .success("Added to library")
        }
    }

    /// Straight to the floating window — no crop surface, no action bar.
    /// This is the path the Shortcuts/share-sheet entries use.
    func floatImmediately(image: UIImage, minimalUI: Bool = false) {
        let normalized = image.normalizedUp()
        pending = nil
        if minimalUI { floatOnlyLaunch = true }
        pip.float(normalized)

        switch pip.status {
        case .unsupported:
            toast = .failure(
                "Not available here",
                "Floating needs Picture in Picture, which the Simulator doesn't have."
            )
        case let .failed(message):
            toast = .failure("Couldn't start floating", message)
        default:
            archive(normalized, rect: CGRect(origin: .zero, size: normalized.pixelSize), origin: .shared)
            toast = .info("Floating", "Swipe home — the snippet stays on screen.")
        }
    }

    /// Floats the newest screenshot whole, for Back Tap / Action Button.
    func floatLatestScreenshot(minimalUI: Bool = false) async {
        // Start AVKit warming while Photos is still fetching.
        pip.prewarm()
        if minimalUI { floatOnlyLaunch = true }
        do {
            let hit = try await PhotoLibraryService.latestScreenshot()
            settings.lastSeenScreenshotID = hit.localIdentifier
            floatImmediately(image: hit.image, minimalUI: minimalUI)
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
            let hit = try await PhotoLibraryService.latestScreenshot()
            if !force, hit.localIdentifier == settings.lastSeenScreenshotID { return }
            settings.lastSeenScreenshotID = hit.localIdentifier

            if settings.captureDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(settings.captureDelay * 1_000_000_000))
            }
            present(image: hit.image, origin: .screenshot)
        } catch {
            toast = .failure("Couldn't load screenshot", error.localizedDescription)
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
        // out of one screenshot in a row. Floating dismisses it — the whole
        // point is to get out of Cod and into another app.
        let keepSurface = action == .pin
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
            pip.float(image)
            switch pip.status {
            case .unsupported:
                toast = .failure(
                    "Not available here",
                    "Floating over other apps needs Picture in Picture, which the Simulator doesn't have."
                )
            case let .failed(message):
                toast = .failure("Couldn't start floating", message)
            default:
                toast = .info("Floating", "Swipe home — the snippet stays on screen.")
            }

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
            let album = settings.saveToDedicatedAlbum ? settings.albumName : nil
            try await PhotoLibraryService.save(image, toAlbumNamed: album)
            archive(image, rect: rect, origin: origin)
            toast = .success("Saved to Photos", album.map { "Album: \($0)" })
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
            pip.float(pin.image)
            if let error = pip.lastError {
                toast = .failure("Floating window unavailable", error)
            } else if pip.status == .unsupported {
                toast = .failure(
                    "Not available here",
                    "Floating over other apps needs Picture in Picture, which the Simulator doesn't have."
                )
            }
        case .recrop:
            withAnimation { pending = Pending(image: pin.image, origin: .unknown) }
        }
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

        if let existingID = archivedCrops[rect],
           var existing = store.snaps.first(where: { $0.id == existingID }) {
            if let text { existing.recognizedText = text }
            if !barcodes.isEmpty { existing.barcodes = barcodes }
            store.update(existing)
            return
        }

        let snap = store.add(image: image, origin: origin, recognizedText: text, barcodes: barcodes)
        archivedCrops[rect] = snap.id
    }
}
