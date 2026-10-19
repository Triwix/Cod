import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pins: PinManager
    @EnvironmentObject private var settings: AppSettings

    @State private var query = ""
    @State private var confirmClear = false
    @State private var detail: Snap?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            Group {
                if store.snaps.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    grid
                }
            }
            .navigationTitle("Library")
            .background(Color(.systemGroupedBackground))
            .searchable(text: $query, prompt: "Search recognized text")
            .toolbar {
                if !store.snaps.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                confirmClear = true
                            } label: {
                                Label("Clear History", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete all \(store.snaps.count) captures?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) { store.clear() }
            } message: {
                Text("This removes them from Cod. Anything you saved to Photos stays there.")
            }
            .sheet(item: $detail) { snap in
                SnapDetailView(snap: snap)
                    .environmentObject(store)
                    .environmentObject(coordinator)
                    .environmentObject(pins)
            }
        }
    }

    private var filtered: [Snap] {
        guard !query.isEmpty else { return store.snaps }
        return store.snaps.filter { snap in
            (snap.recognizedText ?? "").localizedCaseInsensitiveContains(query)
                || snap.barcodes.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(filtered) { snap in
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
                    .contextMenu { menu(for: snap) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func badges(for snap: Snap) -> some View {
        HStack(spacing: 3) {
            if snap.hasText {
                badge("textformat")
            }
            if !snap.barcodes.isEmpty {
                badge("qrcode")
            }
        }
        .padding(6)
    }

    private func badge(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(.black.opacity(0.55), in: Circle())
    }

    @ViewBuilder
    private func menu(for snap: Snap) -> some View {
        Button {
            if let image = store.image(for: snap) {
                coordinator.floatImmediately(
                    image: image, origin: snap.origin, minimalUI: true, reusePreparedPlayback: false)
            }
        } label: {
            Label("Float", systemImage: "pip.enter")
        }
        .disabled(coordinator.isWorking)
        Button {
            coordinator.reopen(snap)
        } label: {
            Label("Re-crop", systemImage: "crop")
        }
        Button {
            if let image = store.image(for: snap) { pins.add(image: image, recognizedText: snap.recognizedText) }
        } label: {
            Label("Pin", systemImage: "pin")
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
        }
    }
}

// MARK: - Detail

struct SnapDetailView: View {
    let snap: Snap

    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pins: PinManager
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
                        Button {
                            dismiss()
                            coordinator.floatImmediately(
                                image: image, origin: snap.origin, minimalUI: true, reusePreparedPlayback: false)
                        } label: {
                            Label("Float Image", systemImage: "pip.enter")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).tint(.codActionBackground).foregroundStyle(.white)
                        .disabled(coordinator.isWorking)
                    }

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
                        Button {
                            reopen()
                        } label: {
                            Label("Re-crop", systemImage: "crop")
                        }
                        Button {
                            pin()
                        } label: {
                            Label("Pin", systemImage: "pin")
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
        guard text == nil, let image else { return }
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

    private func pin() {
        guard let image else { return }
        pins.add(image: image, recognizedText: text)
        dismiss()
    }

    private func copyImage() {
        guard let image else { return }
        UIPasteboard.general.image = image
        coordinator.toast = .success("Image copied")
    }
}
