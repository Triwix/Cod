import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pip: PiPPinController
    @EnvironmentObject private var settings: AppSettings

    @State private var pickerItem: PhotosPickerItem?
    @State private var cropPickerItem: PhotosPickerItem?
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var imports = MediaImportState()
    @State private var selectedFile: URL?
    private var isLoadingPhoto: Bool { imports.isLoading }
    @State private var installingShortcut: FloatShortcut?
    @State private var importingFile = false
    @StateObject private var timerAlarms = FloatingTimerAlarms.shared
    @StateObject private var visualTimers = FloatingVisualTimers.shared

    var body: some View {
        NavigationStack {
            List {
                if isLoadingPhoto || imports.failure != nil { Section { importFeedback } }
                if !settings.hasCompletedIntroduction { Section { introductionCard } }
                #if DEBUG
                    if let size = coordinator.lastExternalImageSize {
                        Text("Received image \(Int(size.width))x\(Int(size.height))")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("received-image-size")
                    }
                #endif
                if coordinator.quickSharePreview != nil { Section { quickShare } }
                if pip.isActive || pip.status.isBusy {
                    Section("Currently floating") {
                        floatingStatus
                        if let session = pip.toolSession {
                            NavigationLink("Playback controls") { FloatingToolSessionView(session: session) }
                        }
                    }
                }
                if !timerAlarms.records.isEmpty {
                    Section("Timer alarms") {
                        ForEach(timerAlarms.records) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Timer alarm · \(record.date.formatted(date: .omitted, time: .standard))")
                                Button("Cancel alarm", role: .destructive) {
                                    Task {
                                        do { try await timerAlarms.cancelTimer(id: record.id) } catch {
                                            coordinator.toast = .failure(
                                                "Couldn't cancel alarm", error.localizedDescription)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("cancel-timer-alarm")
                            }
                        }
                    }
                }
                if !visualTimers.sessions.isEmpty {
                    Section("Visual timers") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            ForEach(visualTimers.sessions) { session in
                                VStack(alignment: .leading, spacing: 8) {
                                    NavigationLink(session.snapshot.isFinished ? "Timer finished" : "Timer · \(session.snapshot.value)") {
                                        FloatingToolSessionView(session: session)
                                    }
                                    Button(session.snapshot.isFinished ? "Remove timer" : "Cancel timer", role: .destructive) { visualTimers.cancel(session) }
                                }
                            }
                        }
                    }
                }
                Section {
                    choosePhoto
                    screenshotActions
                    Button { importingFile = true } label: {
                        CodRowLabel("Choose File", systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("choose-file")
                } header: {
                    Text("Media & documents")
                } footer: {
                    Text("Files can be images, videos, animated GIFs or PDFs")
                }
                .disabled(coordinator.isWorking || isLoadingPhoto)
                FloatingToolRows()
                if settings.hasCompletedIntroduction, !settings.hasDismissedFloatSetupTip {
                    Section("Quick setup") { setupCard }
                }
                if !coordinator.sharedImages.isEmpty || coordinator.sharedInboxError != nil { Section { sharedImages } }
                Section {
                    NavigationLink {
                        OneTapFloatGuide()
                    } label: {
                        CodRowLabel("Floating guide & setup", systemImage: "questionmark.circle")
                    }
                }
            }
            .codFormStyle()
            .onAppear { coordinator.isFloatListVisible = true }
            .onDisappear { coordinator.isFloatListVisible = false }
            .navigationTitle("Cod")
            .background(Color(.systemGroupedBackground))
            .task { timerAlarms.monitor() }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: VisualFileImport.contentTypes) { result in
                do {
                    selectedFile = try result.get()
                } catch { imports.report(error) }
            }
        }
        .sheet(item: $installingShortcut) { shortcut in
            if let url = shortcut.fileURL { ShortcutInstaller(url: url) }
        }
        .task(id: pickerItem) { await loadPhoto(pickerItem, crop: false) }
        .task(id: cropPickerItem) { await loadPhoto(cropPickerItem, crop: true) }
        .task(id: selectedFile) { if let selectedFile { await openFile(selectedFile) } }
    }

    private func loadPhoto(_ item: PhotosPickerItem?, crop: Bool) async {
        guard let item else { return }
        let request = imports.begin()
        coordinator.prioritizeExplicitInput()
        defer {
            if imports.accepts(request) {
                imports.finish(request)
                if crop { cropPickerItem = nil } else { pickerItem = nil }
            }
        }
        do {
            if !crop, item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let video = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw VisualFileImport.ImportError.unavailable
                }
                try Task.checkCancellation()
                guard imports.accepts(request) else { return }
                coordinator.route = .init(kind: .video(video.reference))
                return
            }
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw VisualFileImport.ImportError.unavailable
            }
            try Task.checkCancellation()
            guard imports.accepts(request) else { return }
            if !crop, AnimatedImageImport.isAnimatedGIF(data) {
                let video = try await AnimatedImageImport.video(data)
                try Task.checkCancellation()
                guard imports.accepts(request) else { return }
                coordinator.route = .init(kind: .video(video))
                return
            }
            let image = try VisualFileImport.image(from: data)
            if crop { coordinator.restoreFloatingSelection(image, origin: .imported) }
            else { coordinator.floatImmediately(image: image, origin: .imported) }
        } catch {
            if !Task.isCancelled { imports.fail(error, for: request) }
        }
    }

    private func openFile(_ url: URL) async {
        let request = imports.begin()
        coordinator.prioritizeExplicitInput()
        defer {
            if imports.accepts(request) { imports.finish(request); selectedFile = nil }
        }
        do {
            let content = try await VisualFileImport.open(url)
            try Task.checkCancellation()
            guard imports.accepts(request) else { return }
            switch content {
            case .image(let image): coordinator.restoreFloatingSelection(image, origin: .imported)
            case .video(let reference): coordinator.route = .init(kind: .video(reference))
            case .pdf(let reference): coordinator.route = .init(kind: .pdf(reference))
            }
        } catch { if !Task.isCancelled { imports.fail(error, for: request) } }
    }

    private var importFeedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingPhoto {
                ProgressView("Loading media…")
                Text("Cloud items may need time to download. You can cancel without changing your original.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Cancel Import", role: .cancel) {
                    imports.cancel()
                    pickerItem = nil; cropPickerItem = nil; selectedFile = nil
                }.frame(minHeight: 44).accessibilityIdentifier("cancel-media-import")
            }
            if let failure = imports.failure {
                Label("Couldn't import item", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(failure).accessibilityIdentifier("media-import-error")
                Text("Choose another item below to try again.").font(.footnote).foregroundStyle(.secondary)
                Button("Dismiss") { imports.dismissFailure() }
                    .frame(minHeight: 44).accessibilityIdentifier("dismiss-import-error")
            }
        }
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep it in view", systemImage: "pip.enter")
                .font(.headline.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text("Float a reference over other apps. Start below or take a quick tour.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                NavigationLink("Quick introduction") { FloatingIntroductionView() }
                    .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
                    .accessibilityIdentifier("open-introduction")
                Button("Not now") { settings.hasCompletedIntroduction = true }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .frame(minHeight: 44).accessibilityIdentifier("dismiss-introduction")
            }
        }
    }

    private var choosePhoto: some View {
        compactRow("Photos & videos", icon: "photo.on.rectangle") {
            PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current, photoLibrary: .shared()) {
                Label("Float", systemImage: "pip.enter")
            }.buttonStyle(CodActionStyle(compact: true))
                .accessibilityLabel("Choose Photo or Video").accessibilityIdentifier("choose-photo")
            PhotosPicker(selection: $cropPickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Crop", systemImage: "crop")
            }.buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
                .accessibilityLabel("Crop Photo").accessibilityIdentifier("crop-photo")
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Float straight from Photos", systemImage: "square.and.arrow.up")
                .font(.headline.weight(.medium))
            Text("Add the Shortcut once, then use Photos → Share → Float with Cod.")
                .font(.subheadline).foregroundStyle(.secondary)
            if FloatShortcut.shareImage.fileURL != nil {
                Button {
                    installingShortcut = .shareImage
                } label: {
                    Label("Add Float with Cod", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CodActionStyle(emphasis: .secondary))
                .accessibilityIdentifier("install-share-shortcut")
                Text(
                    "Choose Shortcuts, then Add Shortcut. The image input is ready to use."
                )
                .font(.footnote).foregroundStyle(.secondary)
            } else {
                NavigationLink("Open setup instructions") { OneTapFloatGuide() }
            }
            Button("Already set up? Hide this tip") { settings.hasDismissedFloatSetupTip = true }
                .font(.footnote).frame(minHeight: 44)
                .accessibilityIdentifier("hide-float-setup")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var screenshotActions: some View {
        compactRow("Latest screenshot", icon: "iphone.gen3") {
            Button { Task { await coordinator.floatLatestScreenshot(minimalUI: true) } } label: {
                Label("Float", systemImage: "pip.enter")
            }.buttonStyle(CodActionStyle(compact: true))
                .accessibilityLabel("Float Latest Screenshot").accessibilityIdentifier("float-latest-screenshot")
            Button { Task { await coordinator.captureLatestScreenshot() } } label: {
                Label("Crop", systemImage: "crop")
            }.buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
                .accessibilityLabel("Crop Latest Screenshot").accessibilityIdentifier("crop-latest-screenshot")
        }
        Button { coordinator.pasteFromClipboard() } label: {
            CodRowLabel(isLoadingPhoto ? "Loading…" : "Paste Image from Clipboard", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).disabled(coordinator.isWorking || isLoadingPhoto)
    }

    private func compactRow<Actions: View>(_ title: String, icon: String, @ViewBuilder actions: () -> Actions) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    CodRowLabel(title, systemImage: icon)
                    HStack(spacing: 8) { actions().labelStyle(.titleOnly) }
                }
            } else {
                HStack(spacing: 12) {
                    CodRowLabel(title, systemImage: icon)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 8) { actions().labelStyle(.titleOnly) }.fixedSize()
                }
            }
        }
        .disabled(coordinator.isWorking || isLoadingPhoto)
    }

    private var quickShare: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shared image ready to retry", systemImage: "photo")
                .font(.subheadline.weight(.medium))
            Text(
                settings.useFloatNotification
                    ? "Tap Cod's notification or retry here. A newer share replaces this image."
                    : "Your last share is still here. Retry when ready; it won't restart on its own."
            )
            .font(.footnote).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    retryButton
                    removeShareButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    retryButton
                    removeShareButton
                }
            }
        }
        .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retryButton: some View {
        Button("Try Floating Again") { coordinator.receiveQuickShare(retry: true) }
            .buttonStyle(CodActionStyle(compact: true))
            .disabled(coordinator.isWorking)
    }
    private var removeShareButton: some View {
        Button("Remove", role: .destructive) { coordinator.discardQuickShare() }
            .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true)).disabled(coordinator.isWorking)
    }

    /// Compatibility UI for existing user data, not a new-image inbox workflow.
    private var sharedImages: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Earlier shared images", systemImage: "tray").font(.headline)
            if let error = coordinator.sharedInboxError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try loading earlier images again") { coordinator.refreshSharedImages() }
                    .frame(minHeight: 44)
            }
            ForEach(coordinator.sharedImages) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let thumbnail = entry.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: 64, height: 64)
                                .accessibilityLabel("Shared image preview")
                        } else {
                            Label("Unreadable image", systemImage: "photo.badge.exclamationmark")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            coordinator.removeSharedImage(entry)
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove this image from Cod's inbox")
                    }
                    HStack {
                        Button("Float") { coordinator.openSharedImage(entry, float: true) }.buttonStyle(
                            .borderedProminent
                        )
                        .tint(.codActionBackground).foregroundStyle(.white)
                        Button("Crop") { coordinator.openSharedImage(entry, float: false) }.buttonStyle(
                            .bordered)
                    }
                    .disabled(entry.thumbnail == nil || coordinator.isWorking)
                }
            }
            Text(
                "Kept from an earlier version. Remove them here; clearing history doesn't remove these copies."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var floatingStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pip.isActive || pip.status.isBusy {
                Label(
                    pip.isActive ? "Floating over other apps" : "Opening floating window…",
                    systemImage: "pip.fill"
                )
                .font(.headline.weight(.medium))
                Text(
                    pip.isActive
                        ? "Open another app yourself; Cod doesn't switch apps for you. iOS controls the floating window's size and position."
                        : "Keep Cod open while iOS prepares Picture in Picture."
                )
                .font(.footnote).foregroundStyle(.secondary)
                Button("Stop Floating", role: .destructive) { pip.stop() }
                    .buttonStyle(CodActionStyle(emphasis: .secondary, compact: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
    }
}

/// Thumbnail loading is bounded by the store's cache.
struct SnapThumbnail: View {
    let snap: Snap
    @EnvironmentObject private var store: SnapStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(4) }
        }
        .task(id: snap.id) { image = store.thumbnail(for: snap) }
        .clipped()
    }
}
