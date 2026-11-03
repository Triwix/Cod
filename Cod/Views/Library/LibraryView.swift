import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var savedReferences = SavedReferenceStore.shared

    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var confirmClear = false
    @State private var detail: Snap?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let issue = store.storageIssue {
                    Text(issue).font(.footnote).foregroundStyle(.secondary).padding()
                        .accessibilityIdentifier("library-storage-issue")
                    if store.canRetryLoading {
                        Button("Try Loading Library Again") { store.retryLoading() }
                            .frame(minHeight: 44).accessibilityIdentifier("retry-library-load")
                    }
                }
                VStack(spacing: 16) {
                    NavigationLink { SavedReferencesView() } label: {
                        HStack(spacing: 12) {
                            CodRowLabel("Saved cards & presets", systemImage: "text.book.closed",
                                        detail: savedReferences.items.isEmpty
                                            ? "Text cards, scripts and time tools"
                                            : "\(savedReferences.items.count) saved")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.medium)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("saved-references")
                    Picker("Show", selection: $favoritesOnly) {
                        Text("All").tag(false)
                        Text("Favorites").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("library-filter")
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                if settings.historyLimit == .off, !store.snaps.isEmpty { enableHistory }
                if store.snaps.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("No favorites yet", systemImage: "star", description: Text("Open a capture and tap the star to keep it for later."))
                    } else { ContentUnavailableView.search(text: query) }
                } else {
                    grid
                }
            }
            .navigationTitle("Library")
            .background(Color(.systemGroupedBackground))
            .searchable(text: $query, prompt: "Search recognized text")
            .toolbar {
                if !store.snaps.isEmpty || !savedReferences.items.isEmpty || savedReferences.loadError != nil || store.storageIssue != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                confirmClear = true
                            } label: {
                                Label("Clear Library…", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("library-options")
                    }
                }
            }
            .confirmationDialog(
                "Clear Library?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                if store.historyCount > 0 {
                    Button("Clear Recent History (\(store.historyCount))", role: .destructive) { store.clearHistory() }
                }
                Button("Delete Everything, Including Favorites", role: .destructive) {
                    do { try SavedReferenceStore.shared.clear(); store.clear() }
                    catch { coordinator.toast = .failure("Couldn't clear saved cards", error.localizedDescription) }
                }
            } message: {
                Text("Clear Recent History keeps favorites and saved cards. Delete Everything removes all captures, favorites, saved cards and presets. Originals in Photos or Files aren't deleted.")
            }
            .sheet(item: $detail) { snap in
                SnapDetailView(snap: snap)
                    .environmentObject(store)
                    .environmentObject(coordinator)
            }
        }
    }

    private var filtered: [Snap] {
        let candidates = store.snaps.filter { !favoritesOnly || $0.isFavorite }
        guard !query.isEmpty else { return candidates }
        return candidates.filter { snap in
            (snap.recognizedText ?? "").localizedCaseInsensitiveContains(query)
                || snap.barcodes.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                let matching = Set(filtered.map(\.id))
                let favorites = store.favorites.filter { matching.contains($0.id) }
                if !favorites.isEmpty {
                    Section {
                        thumbnails(favorites)
                    } header: {
                        Text("Favorites").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("library-favorites-heading")
                    }
                }
                if !favoritesOnly {
                    let history = filtered.filter { !$0.isFavorite }
                    if !history.isEmpty {
                        Section {
                            thumbnails(history)
                        } header: {
                            Text("Recent history").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, favorites.isEmpty ? 0 : 16)
                                .accessibilityIdentifier("library-history-heading")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func thumbnails(_ snaps: [Snap]) -> some View {
                ForEach(snaps) { snap in
                    Button {
                        detail = snap
                    } label: {
                        SnapThumbnail(snap: snap)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .bottomLeading) { badges(for: snap) }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Saved \(snap.origin.label.lowercased()), \(snap.dimensionLabel)")
                    .accessibilityIdentifier("library-capture-\(snap.id)")
                    .contextMenu { menu(for: snap) }
                }
    }

    private func badges(for snap: Snap) -> some View {
        HStack(spacing: 4) {
            if snap.isVideo { badge("play.fill") }
            if snap.isFavorite { badge("star.fill") }
            if snap.hasText {
                badge("textformat")
            }
            if !snap.barcodes.isEmpty {
                badge("qrcode")
            }
        }
        .padding(8)
    }

    private func badge(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func menu(for snap: Snap) -> some View {
        Button {
            if snap.isVideo { coordinator.reopenVideo(snap, float: true) }
            else if let image = store.image(for: snap) {
                coordinator.floatImmediately(
                    image: image, origin: snap.origin, minimalUI: true, reusePreparedPlayback: false)
            }
        } label: {
            Label("Float", systemImage: "pip.enter")
        }
        .disabled(coordinator.isWorking)
        if !snap.isVideo {
            Button { coordinator.reopen(snap) } label: { Label("Re-crop", systemImage: "crop") }
        }
        Button { store.toggleFavorite(snap.id) } label: {
            Label(snap.isFavorite ? "Remove Favorite" : "Favorite", systemImage: snap.isFavorite ? "star.slash" : "star")
        }
        Button {
            if let image = store.image(for: snap) {
                UIPasteboard.general.image = image
                coordinator.toast = .success("Image copied")
            }
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }
        if snap.hasText {
            Button {
                UIPasteboard.general.string = snap.recognizedText
                coordinator.toast = .success("Text copied")
            } label: {
                Label("Copy Text", systemImage: "text.viewfinder")
            }
        }
        Divider()
        Button(role: .destructive) {
            store.delete(snap)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No captures yet", systemImage: "square.grid.2x2")
        } description: {
            Text(
                settings.historyLimit == .off
                    ? "History is turned off in Settings, so nothing is being kept."
                    : "Images you float or crop appear here. Choose a photo from the Float tab to get started.")
        } actions: {
            if settings.historyLimit == .off { enableHistory }
        }
    }
    private var enableHistory: some View {
        Button("Enable History") { settings.historyLimit = .ten }
            .buttonStyle(CodActionStyle())
            .accessibilityIdentifier("enable-history")
            .padding(8)
    }
}

// MARK: - Detail

struct SnapDetailView: View {
    let snap: Snap

    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var text: String?
    @State private var isRecognizing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image {
                        // Live Text makes the snippet's contents selectable
                        // right here, the way Snapper's OCR view does.
                        LiveTextImageView(image: image)
                            .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    }

                    if let image {
                        if !snap.isVideo {
                            NavigationLink("Use in Text") { ReadableImageView(image: image) }.buttonStyle(.bordered)
                        }
                        Button {
                            dismiss()
                            if snap.isVideo { coordinator.reopenVideo(snap, float: true) }
                            else { coordinator.floatImmediately(
                                image: image, origin: snap.origin, minimalUI: true, reusePreparedPlayback: false)
                            }
                        } label: {
                            Label(snap.isVideo ? "Float Video" : "Float Image", systemImage: "pip.enter")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(CodActionStyle())
                        .disabled(coordinator.isWorking)
                    }

                    Button { store.toggleFavorite(snap.id) } label: {
                        Label(isFavorite ? "Remove Favorite" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                    }.buttonStyle(CodActionStyle(emphasis: .secondary)).accessibilityIdentifier("favorite-capture")

                    metadata

                    if let text, !text.isEmpty {
                        recognizedTextCard(text)
                    } else if isRecognizing {
                        ProgressView("Recognizing text…").padding()
                    }

                    if !snap.barcodes.isEmpty {
                        barcodeCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(snap.origin.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !snap.isVideo {
                            Button { reopen() } label: { Label("Re-crop", systemImage: "crop") }
                        }
                        Button {
                            copyImage()
                        } label: {
                            Label("Copy Image", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            store.delete(snap)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                image = store.image(for: snap)
                text = snap.recognizedText
                await recognizeIfNeeded()
            }
        }
    }

    private var isFavorite: Bool { store.snaps.first(where: { $0.id == snap.id })?.isFavorite ?? false }

    private var metadata: some View {
        HStack {
            Label(snap.dimensionLabel, systemImage: "aspectratio")
            Spacer()
            Text(snap.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func recognizedTextCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recognized text", systemImage: "text.viewfinder")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Copy") {
                    UIPasteboard.general.string = text
                    coordinator.toast = .success("Text copied")
                }
                .font(.subheadline)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var barcodeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Codes", systemImage: "qrcode")
                .font(.subheadline.weight(.semibold))
            ForEach(snap.barcodes, id: \.self) { payload in
                BarcodePayloadRow(payload: payload)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func recognizeIfNeeded() async {
        guard !snap.isVideo, text == nil, let image else { return }
        isRecognizing = true
        defer { isRecognizing = false }
        if let result = try? await Recognizer.recognizeText(in: image), !result.isEmpty {
            text = result.text
            store.setRecognizedText(result.text, for: snap.id)
        } else {
            text = ""
        }
    }

    private func reopen() {
        coordinator.reopen(snap)
        dismiss()
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        coordinator.toast = .success("Image copied")
    }
}
