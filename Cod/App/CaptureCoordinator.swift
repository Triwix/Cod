import Combine
import Photos
import SwiftUI
import UniformTypeIdentifiers

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
            case translate(String)
            case annotate(UIImage)
            case tool(FloatingToolSession)
            case pdf(PDFReference)
            case video(VideoReference, autoFloat: Bool = false)
            case readable(UIImage)
            case saved(SavedReference)
        }

        let id = UUID()
        var kind: Kind
    }

    @Published var pending: Pending?
    @Published var route: Route?
    @Published var toast: Toast?
    @Published var isWorking = false
    /// Invalidates asynchronous document loads when another explicit input wins.
    private(set) var explicitInputID = UUID()
    var isFloatListVisible = true
    @Published private(set) var sharedImages: [SharedImageInbox.Entry] = []
    @Published private(set) var sharedInboxError: String?
    private let sharedInbox: SharedImageInbox
    private let quickHandoff: QuickFloatHandoff
    private var quickRequestID: UUID?
    @Published private(set) var quickSharePreview: QuickFloatHandoff.Payload?
    @Published private(set) var lastExternalImageSize: CGSize?
    /// True when Cod was opened purely to float something, so the UI can stay
    /// out of the way instead of flashing the whole app.
    @Published var floatOnlyLaunch = false

    let store: SnapStore
    let settings: AppSettings
    let pip: PiPPinController

    /// `CGRect` only gained `Hashable` conformance in iOS 18. The app targets
    /// iOS 17, and the actual crop is integral anyway, so key history entries
    /// by the pixel rectangle that was written rather than the fractional drag
    /// rectangle.
    /// History entries already written for the crop currently on screen, keyed
    /// by selection rect — so floating and then copying text from the same
    /// selection updates one entry instead of creating two.
    private var archivedCrops: [PixelRectKey: Snap.ID] = [:]
    private var pipStatusCancellable: AnyCancellable?
    private var isAwaitingFloatResult = false
    private var dismissSelectionOnFloatSuccess = false
    private var imagePreparationID: UUID?
    private var imagePreparationTask: Task<Void, Never>?

    init(
        store: SnapStore,
        settings: AppSettings,
        pip: PiPPinController,
        sharedInbox: SharedImageInbox = .shared,
        quickHandoff: QuickFloatHandoff = .shared
    ) {
        self.store = store
        self.settings = settings
        self.pip = pip
        self.sharedInbox = sharedInbox
        self.quickHandoff = quickHandoff
        observePiPStatus()
    }

    convenience init() {
        self.init(
            store: .shared,
            settings: .shared,
            pip: .shared
        )
    }

    // MARK: - Ingestion

    func openReadableImage(_ image: UIImage) {
        prioritizeExplicitInput(); dismissSelection()
        floatOnlyLaunch = false
        route = .init(kind: .readable(image))
    }

    func floatSavedReference(_ id: UUID) {
        prioritizeExplicitInput()
        do {
            if let item = SavedReferenceStore.shared.items.first(where: { $0.id == id }) {
                if let card = item.text {
                    let image = try FloatingText.render(card.text, fontSize: card.fontSize, palette: card.palette,
                        colors: card.colors ?? card.palette.colors(for: currentInterfaceStyle))
                    receiveFloatIntentImage(image)
                } else if var tool = item.tool {
                    tool.interfaceStyle = currentInterfaceStyle
                    if tool.hasTimerAlarm {
                        Task {
                            do { try await FloatingTimerAlarms.shared.authorize(); floatTool(.init(configuration: tool)) }
                            catch { toast = .failure("Couldn't start alarm preset", error.localizedDescription) }
                        }
                    } else { floatTool(.init(configuration: tool)) }
                } else { throw SavedReferenceError.invalidContent }
                return
            }
            if let snap = store.snaps.first(where: { $0.id == id && $0.isFavorite }) {
                if snap.isVideo { reopenVideo(snap, float: true) }
                else if let image = store.image(for: snap) { receiveFloatIntentImage(image) }
                else { throw SavedReferenceError.missing }
                return
            }
            throw SavedReferenceError.missing
        } catch { toast = .failure("Couldn't open reference", error.localizedDescription) }
    }

    private var currentInterfaceStyle: UIUserInterfaceStyle {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // OpenIntent can arrive while Control Center is still dismissing and
        // our scene is inactive. Its own key window already has valid traits.
        let preferred = scenes.first(where: { $0.activationState == .foregroundActive })
        let window = preferred?.windows.first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        return window?.traitCollection.userInterfaceStyle ?? .light
    }

    func receiveExternalImage(_ image: UIImage, origin: Snap.Origin = .shared) {
        lastExternalImageSize = image.pixelSize
        finishQuickRequest(success: false)
        try? quickHandoff.deferAutomaticStart()
        if settings.oneTapFloat {
            CodDiagnosticLog.record("direct image received; automatic float \(Int(image.pixelSize.width))x\(Int(image.pixelSize.height))")
            floatImmediately(image: image, origin: origin, minimalUI: true, reusePreparedPlayback: false)
        } else {
            restoreFloatingSelection(image, origin: origin)
        }
    }

    /// Explicit Float actions never consult the crop preference or substitute
    /// the latest library photo. Record actual receipt for native handoff QA.
    func receiveFloatIntentImage(_ image: UIImage) {
        prioritizeExplicitInput()
        lastExternalImageSize = image.pixelSize
        CodDiagnosticLog.record("float intent received \(Int(image.pixelSize.width))x\(Int(image.pixelSize.height))")
        floatImmediately(image: image, minimalUI: true, reusePreparedPlayback: false)
    }

    @discardableResult
    func receiveQuickShare(retry: Bool = false, expectedID: UUID? = nil, fromNotification: Bool = false) -> Bool {
        guard !isWorking, !pip.status.isBusy else { return false }
        guard pending == nil || expectedID != nil else { return false }
        do {
            let payload: QuickFloatHandoff.Payload?
            if fromNotification, let id = expectedID { payload = try quickHandoff.claimNotification(id) }
            else { payload = try (retry ? quickHandoff.retry() : quickHandoff.claim(expectedID: expectedID)) }
            refreshQuickSharePreview()
            guard let payload else {
                if fromNotification {
                    toast = .failure("This notification is no longer current", "The image was already handled or replaced by a newer share. No other image was floated.")
                }
                return true
            }
            finishQuickRequest(success: false)
            lastExternalImageSize = payload.image.pixelSize
            quickRequestID = payload.id
            CodDiagnosticLog.record("quick share claimed id=\(payload.id) elapsed=\(Int(Date().timeIntervalSince(payload.createdAt) * 1_000))ms")
            if payload.mode == .float {
                floatImmediately(image: payload.image, minimalUI: true, reusePreparedPlayback: false)
            } else {
                restoreFloatingSelection(payload.image)
            }
        } catch {
            toast = .failure("Couldn't receive shared image", error.localizedDescription)
        }
        return true
    }

    func refreshQuickSharePreview() {
        do { quickSharePreview = try quickHandoff.preview() }
        catch { quickSharePreview = nil }
    }

    func prioritizeExplicitInput() {
        cancelImagePreparation()
        explicitInputID = UUID()
        finishQuickRequest(success: false)
        try? quickHandoff.deferAutomaticStart()
    }

    func discardQuickShare() {
        do {
            try quickHandoff.discard()
            quickRequestID = nil
            quickSharePreview = nil
        } catch { toast = .failure("Couldn't remove shared image", error.localizedDescription) }
    }

    private func finishQuickRequest(success: Bool) {
        guard let id = quickRequestID else { return }
        quickRequestID = nil
        do { try quickHandoff.finish(id, success: success) }
        catch { CodDiagnosticLog.record("quick share acknowledgement failed: \(error.localizedDescription)") }
        refreshQuickSharePreview()
    }

    func refreshSharedImages() {
        do {
            sharedImages = try sharedInbox.entries()
            sharedInboxError = nil
        } catch {
            sharedInboxError = error.localizedDescription
        }
    }

    func openSharedImage(_ entry: SharedImageInbox.Entry, float: Bool) {
        do {
            let image = try sharedInbox.image(for: entry.id)
            // Explicit user choice takes priority over arrival-mode settings.
            // Keep the durable inbox original for retries and future crops.
            if float { floatImmediately(image: image, minimalUI: true) }
            else { restoreFloatingSelection(image) }
        } catch {
            toast = .failure("Couldn't open shared image", error.localizedDescription)
        }
    }

    func removeSharedImage(_ entry: SharedImageInbox.Entry) {
        do {
            try sharedInbox.remove(entry.id)
            refreshSharedImages()
        } catch {
            toast = .failure("Couldn't remove shared image", error.localizedDescription)
        }
    }

    func present(image: UIImage, origin: Snap.Origin) {
        prepareImage(image) { [weak self] normalized in
            self?.presentPreparedImage(normalized, origin: origin)
        }
    }

    private func presentPreparedImage(_ normalized: UIImage, origin: Snap.Origin) {
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
                let snap = store.add(image: normalized, origin: origin)
                toast = store.snaps.contains(where: { $0.id == snap.id })
                    ? .success("Added to library")
                    : .failure("Couldn't add to Library", store.storageIssue)
            }
        }
    }

    /// Straight to the floating window — no crop surface, no action bar.
    /// This is the path the Shortcuts/share-sheet entries use.
    func floatImmediately(
        image: UIImage,
        origin: Snap.Origin = .shared,
        minimalUI: Bool = false,
        reusePreparedPlayback: Bool = true
    ) {
        prepareImage(image) { [weak self] normalized in
            self?.floatPreparedImage(normalized, origin: origin, minimalUI: minimalUI,
                                     reusePreparedPlayback: reusePreparedPlayback)
        }
    }

    private func floatPreparedImage(_ normalized: UIImage, origin: Snap.Origin,
                                    minimalUI: Bool, reusePreparedPlayback: Bool) {
        pending = nil
        archivedCrops.removeAll()
        if minimalUI { floatOnlyLaunch = true }
        startFloating(
            normalized,
            dismissSelectionOnSuccess: false,
            reusePreparedPlayback: reusePreparedPlayback
        )

        if pip.status != .unsupported {
            archive(normalized, rect: CGRect(origin: .zero, size: normalized.pixelSize), origin: origin)
        }
    }

    private func prepareImage(_ image: UIImage, then action: @escaping @MainActor (UIImage) -> Void) {
        cancelImagePreparation()
        // Already decoded imports keep their synchronous request bookkeeping;
        // only an actual redraw leaves the main actor.
        guard image.imageOrientation != .up || image.scale != 1 else { action(image); return }
        let id = UUID()
        imagePreparationID = id
        isWorking = true
        imagePreparationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let normalized = await Task.detached(priority: .userInitiated) { image.normalizedUp() }.value
            guard let self, !Task.isCancelled, self.imagePreparationID == id else { return }
            self.imagePreparationID = nil
            self.imagePreparationTask = nil
            self.isWorking = self.isAwaitingFloatResult
            action(normalized)
        }
    }

    private func cancelImagePreparation() {
        guard imagePreparationID != nil else { return }
        imagePreparationID = nil
        imagePreparationTask?.cancel()
        imagePreparationTask = nil
        if !isAwaitingFloatResult { isWorking = false }
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
        cancelImagePreparation()
        finishQuickRequest(success: false)
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }

    /// Restore an image for explicit user action, regardless of the configured
    /// arrival mode. Instant Float must not reopen PiP in a restoration loop.
    func restoreFloatingSelection(_ image: UIImage, origin: Snap.Origin = .shared) {
        cancelImagePreparation()
        isAwaitingFloatResult = false
        dismissSelectionOnFloatSuccess = false
        floatOnlyLaunch = false
        archivedCrops.removeAll()
        pending = Pending(image: image, origin: origin)
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
            if force { restoreFloatingSelection(hit.image, origin: .screenshot) }
            else { present(image: hit.image, origin: .screenshot) }
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
        if let data = UIPasteboard.general.data(forPasteboardType: UTType.gif.identifier), AnimatedImageImport.isAnimatedGIF(data) {
            prioritizeExplicitInput(); isWorking = true
            Task {
                defer { isWorking = false }
                do { route = .init(kind: .video(try await AnimatedImageImport.video(data))) }
                catch { toast = .failure("Couldn't open animation", error.localizedDescription) }
            }
            return
        }
        guard let image = UIPasteboard.general.image else {
            toast = .failure("Clipboard has no image")
            Haptics.warning()
            return
        }
        receiveExternalImage(image, origin: .pasted)
    }

    func reopen(_ snap: Snap) {
        cancelImagePreparation()
        if snap.isVideo { reopenVideo(snap); return }
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
        // Floating keeps the crop surface only until the
        // system window confirms success, so a failed attempt is still usable.
        let keepSurface = action == .float
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

        case .qr:
            await scanCodes(in: image, rect: rect, origin: origin)

        case .translate:
            await translate(image, rect: rect, origin: origin)

        case .annotate:
            archive(image, rect: rect, origin: origin)
            route = Route(kind: .annotate(image))

        case .upload, .pin:
            // Decode retired preferences without exposing or running them.
            break
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

    // MARK: - Floating

    private var archivedVideoIDs: Set<UUID> = []

    func floatVideo(_ reference: VideoReference, sound: Bool = false, repeats: Bool = FloatingVideoPlayback.defaultRepeats) {
        prioritizeExplicitInput()
        pip.stop()
        pending = nil
        floatOnlyLaunch = false
        isAwaitingFloatResult = true
        dismissSelectionOnFloatSuccess = false
        isWorking = true
        pip.float(video: reference, sound: sound, repeats: repeats)
        if settings.historyLimit != .off, !archivedVideoIDs.contains(reference.id) {
            archivedVideoIDs.insert(reference.id)
            Task {
                do { _ = try await store.add(video: reference, limit: settings.historyLimit) }
                catch {
                    archivedVideoIDs.remove(reference.id)
                    toast = .failure("Video wasn't saved in Library", error.localizedDescription)
                }
            }
        }
    }

    func reopenVideo(_ snap: Snap, float: Bool = false) {
        guard let url = store.videoURL(for: snap) else { return }
        Task {
            do {
                let video = try await VideoReference.copy(from: url)
                prioritizeExplicitInput()
                // Replaying a saved video must not create a duplicate history item.
                archivedVideoIDs.insert(video.id)
                route = .init(kind: .video(video, autoFloat: float))
            } catch { toast = .failure("Couldn't open video", error.localizedDescription) }
        }
    }

    func floatTool(_ session: FloatingToolSession) {
        do { try session.configuration.validate() }
        catch { toast = .failure("Couldn't start tool", error.localizedDescription); return }
        prioritizeExplicitInput()
        // Stop the previous source before registering the new attempt: its
        // idle notification must not finish this request by mistake.
        pip.stop()
        pending = nil
        floatOnlyLaunch = false
        isAwaitingFloatResult = true
        dismissSelectionOnFloatSuccess = false
        isWorking = true
        pip.float(tool: session)
    }

    private func observePiPStatus() {
        pipStatusCancellable = pip.$status
            .sink { @MainActor [weak self] status in
                self?.handlePiPStatus(status)
            }
    }

    private func startFloating(
        _ image: UIImage,
        dismissSelectionOnSuccess: Bool,
        reusePreparedPlayback: Bool = true
    ) {
        isAwaitingFloatResult = true
        self.dismissSelectionOnFloatSuccess = dismissSelectionOnSuccess
        isWorking = true
        toast = .info("Opening floating window…")
        pip.float(image, reusePreparedPlayback: reusePreparedPlayback)
    }

    private func handlePiPStatus(_ status: PiPPinController.Status) {
        guard isAwaitingFloatResult else { return }

        switch status {
        case .idle:
            finishQuickRequest(success: false)
            finishFloatAttempt()

        case .preparing:
            break

        case .active:
            let shouldDismiss = dismissSelectionOnFloatSuccess
            finishQuickRequest(success: true)
            finishFloatAttempt()
            if shouldDismiss { dismissSelection() }
            let content = pip.videoReference != nil ? "video" : pip.toolSession == nil ? "image" : "tool"
            toast = .info("Floating", "Switch apps when you're ready. The \(content) stays in Picture in Picture.")

        case .unsupported:
            finishQuickRequest(success: false)
            finishFloatAttempt()
            floatOnlyLaunch = false
            toast = .failure(
                "Not available here",
                "Picture in Picture isn't available here. You can still crop, copy, save, and share images."
            )

        case let .failed(message):
            finishQuickRequest(success: false)
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
    /// (for actions on an already archived capture).
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
