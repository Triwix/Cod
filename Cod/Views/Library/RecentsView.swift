import SwiftUI

/// Everything floated or captured recently, newest first. Starred items stay
/// pinned at the top and survive history limits. Tap a row to float it again.
struct RecentsView: View {
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var savedReferences = SavedReferenceStore.shared
    @ObservedObject private var tools = RecentFloats.shared

    @State private var query = ""
    @State private var starredOnly = false
    @State private var confirmClear = false
    @State private var detail: Snap?

    var body: some View {
        NavigationStack {
            List {
                if let issue = store.storageIssue {
                    Section {
                        Text(issue).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("library-storage-issue")
                        if store.canRetryLoading {
                            Button("Try Loading Recents Again") { store.retryLoading() }
                                .accessibilityIdentifier("retry-library-load")
                        }
                    }
                }
                Section {
                    Picker("Show", selection: $starredOnly) {
                        Text("All").tag(false)
                        Text("Starred").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("library-filter")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if settings.historyLimit == .off {
                    Section {
                        Text("Image and video history is off, so only starred items and tools are kept.")
                            .font(.footnote).foregroundStyle(.secondary)
                        enableHistory
                    }
                }
                let starred = entries.filter(\.isStarred)
                if !starred.isEmpty {
                    Section {
                        rows(starred)
                    } header: {
                        Text("Starred").accessibilityIdentifier("library-favorites-heading")
                    }
                }
                if !starredOnly {
                    let recent = entries.filter { !$0.isStarred }
                    if !recent.isEmpty {
                        Section {
                            rows(recent)
                        } header: {
                            Text("Recent").accessibilityIdentifier("library-history-heading")
                        }
                    }
                }
                Section {
                    NavigationLink { SavedReferencesView() } label: {
                        CodRowLabel("Saved cards & presets", systemImage: "text.book.closed",
                                    detail: savedReferences.items.isEmpty
                                        ? "Named text cards, scripts and tool setups"
                                        : "\(savedReferences.items.count) saved")
                    }
                    .accessibilityIdentifier("saved-references")
                }
            }
            .overlay {
                if entries.isEmpty, store.storageIssue == nil {
                    if !query.isEmpty { ContentUnavailableView.search(text: query) }
                    else if starredOnly, hasAnything {
                        ContentUnavailableView(
                            "Nothing starred", systemImage: "star",
                            description: Text("Star anything you float often to keep it at the top."))
                    } else if !hasAnything {
                        ContentUnavailableView(
                            "Nothing floated yet", systemImage: "clock.arrow.circlepath",
                            description: Text("Images, videos, text and tools you float show up here, so you can float them again in one tap."))
                    }
                }
            }
            .navigationTitle("Recents")
            .searchable(text: $query, prompt: "Search recents and recognized text")
            .toolbar {
                if hasAnything || !savedReferences.items.isEmpty || savedReferences.loadError != nil || store.storageIssue != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) { confirmClear = true } label: {
                                Label("Clear Recents…", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Recents options")
                        .accessibilityIdentifier("library-options")
                    }
                }
            }
            .confirmationDialog("Clear Recents?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Recents, Keep Starred", role: .destructive) {
                    store.clearHistory()
                    tools.clearUnstarred()
                }
                Button("Delete Everything, Including Starred", role: .destructive) {
                    do { try SavedReferenceStore.shared.clear(); store.clear(); tools.clear() }
                    catch { coordinator.toast = .failure("Couldn't clear saved cards", error.localizedDescription) }
                }
            } message: {
                Text("Clear Recents keeps starred items and saved cards. Delete Everything also removes starred items, saved cards and presets. Originals in Photos or Files aren't deleted.")
            }
            .sheet(item: $detail) { snap in
                SnapDetailView(snap: snap)
                    .environmentObject(store)
                    .environmentObject(coordinator)
            }
        }
    }

    private var hasAnything: Bool { !store.snaps.isEmpty || !tools.items.isEmpty }

    /// Images, videos and tool setups in one list, most recently used first.
    private var entries: [RecentEntry] {
        let all = store.snaps.map(RecentEntry.snap) + tools.items.map(RecentEntry.tool)
        return all
            .filter { !starredOnly || $0.isStarred }
            .filter { query.isEmpty || $0.matches(query) }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder private func rows(_ entries: [RecentEntry]) -> some View {
        ForEach(entries) { entry in
            switch entry {
            case let .snap(snap): snapRow(snap)
            case let .tool(item): toolRow(item)
            }
        }
    }

    private func snapRow(_ snap: Snap) -> some View {
        RecentRow(
            title: snap.isVideo ? "Video" : snap.origin.label,
            detail: [snap.recognizedText.flatMap(Self.snippet) ?? snap.dimensionLabel,
                     snap.usedAt.formatted(.relative(presentation: .named))].joined(separator: " · "),
            floatLabel: "Float \(snap.isVideo ? "video" : snap.origin.label.lowercased()) again, \(snap.dimensionLabel)",
            floatIdentifier: "library-capture-\(snap.id)",
            isStarred: snap.isFavorite,
            starIdentifier: "star-\(snap.id)",
            onStar: { store.toggleFavorite(snap.id) },
            onFloat: { coordinator.floatSnap(snap) }
        ) {
            SnapThumbnail(snap: snap)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if snap.isVideo {
                        Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).padding(4)
                            .background(.black.opacity(0.6), in: Circle()).padding(3)
                    }
                }
        }
        .disabled(coordinator.isWorking)
        .contextMenu { menu(for: snap) }
        .swipeActions { deleteButton { store.delete(snap) } }
    }

    private func toolRow(_ item: RecentFloat) -> some View {
        RecentRow(
            title: item.title,
            detail: [item.detail, item.floatedAt.formatted(.relative(presentation: .named))]
                .filter { !$0.isEmpty }.joined(separator: " · "),
            floatLabel: "Float \(item.title) again" + (item.detail.isEmpty ? "" : ", \(item.detail)"),
            floatIdentifier: "recents-tool-\(item.configuration.kind.rawValue)",
            isStarred: item.isStarred,
            starIdentifier: "star-\(item.id)",
            onStar: { tools.toggleStar(item.id) },
            onFloat: { coordinator.floatRecent(item.configuration) }
        ) {
            Image(systemName: item.configuration.kind.icon)
                .font(.title3.weight(.medium)).foregroundStyle(Color.codActionBackground)
                .frame(width: 52, height: 52)
                .background(Color.codActionBackground.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .disabled(coordinator.isWorking)
        .contextMenu {
            Button("Float", systemImage: "pip.enter") { coordinator.floatRecent(item.configuration) }
            // Auto-scroll documents have no editor; reopen the file to change them.
            if item.configuration.kind != .document {
                Button("Edit Before Floating", systemImage: "slider.horizontal.3") {
                    coordinator.route = .init(kind: .editor(item.configuration))
                }
            }
            Button(item.isStarred ? "Unstar" : "Star", systemImage: item.isStarred ? "star.slash" : "star") {
                tools.toggleStar(item.id)
            }
            Divider()
            Button("Remove from Recents", systemImage: "trash", role: .destructive) { tools.remove(item) }
        }
        .swipeActions { deleteButton { tools.remove(item) } }
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Label("Remove", systemImage: "trash") }
    }

    private static func snippet(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? nil : String(line.prefix(40))
    }

    @ViewBuilder
    private func menu(for snap: Snap) -> some View {
        Button { coordinator.floatSnap(snap) } label: {
            Label(snap.isVideo ? "Float Video" : "Float", systemImage: "pip.enter")
        }
        .disabled(coordinator.isWorking)
        Button { detail = snap } label: { Label("Details & Text", systemImage: "info.circle") }
        if !snap.isVideo {
            Button { coordinator.reopen(snap) } label: { Label("Re-crop", systemImage: "crop") }
        }
        Button { store.toggleFavorite(snap.id) } label: {
            Label(snap.isFavorite ? "Unstar" : "Star", systemImage: snap.isFavorite ? "star.slash" : "star")
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
        Button(role: .destructive) { store.delete(snap) } label: { Label("Remove", systemImage: "trash") }
    }

    private var enableHistory: some View {
        Button("Keep Image History") { settings.historyLimit = .ten }
            .accessibilityIdentifier("enable-history")
    }
}

/// One row in Recents or anything mixing images and tool setups.
enum RecentEntry: Identifiable {
    case snap(Snap)
    case tool(RecentFloat)

    var id: String {
        switch self {
        case let .snap(snap): return "snap-\(snap.id)"
        case let .tool(item): return "tool-\(item.id)"
        }
    }

    var date: Date {
        switch self {
        case let .snap(snap): return snap.usedAt
        case let .tool(item): return item.floatedAt
        }
    }

    var isStarred: Bool {
        switch self {
        case let .snap(snap): return snap.isFavorite
        case let .tool(item): return item.isStarred
        }
    }

    func matches(_ query: String) -> Bool {
        switch self {
        case let .snap(snap):
            return (snap.recognizedText ?? "").localizedCaseInsensitiveContains(query)
                || snap.barcodes.contains { $0.localizedCaseInsensitiveContains(query) }
                || snap.origin.label.localizedCaseInsensitiveContains(query)
        case let .tool(item):
            return item.title.localizedCaseInsensitiveContains(query)
                || item.detail.localizedCaseInsensitiveContains(query)
                || item.configuration.text.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct RecentRow<Thumbnail: View>: View {
    let title: String
    let detail: String
    let floatLabel: String
    let floatIdentifier: String
    let isStarred: Bool
    let starIdentifier: String
    let onStar: () -> Void
    let onFloat: () -> Void
    @ViewBuilder var thumbnail: () -> Thumbnail

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onFloat) {
                HStack(spacing: 12) {
                    thumbnail().accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(floatLabel)
            .accessibilityIdentifier(floatIdentifier)
            Button(action: onStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isStarred ? "Unstar" : "Star")
            .accessibilityIdentifier(starIdentifier)
        }
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
                        // right here, next to the image.
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
                        Label(isFavorite ? "Unstar" : "Star", systemImage: isFavorite ? "star.fill" : "star")
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
