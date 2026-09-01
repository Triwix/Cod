import SwiftUI

struct ShareRootView: View {
    let image: UIImage
    var onFinish: () -> Void

    @StateObject private var settings = AppSettings.shared
    @State private var toast: Toast?
    @State private var isWorking = false
    @State private var barcodes: [Recognizer.BarcodeHit] = []
    @State private var showBarcodes = false

    /// Pinning and PiP need the host app's window; an extension can't do
    /// either, so they're left out of the bar entirely rather than failing.
    private let actions: [SnapAction] = [.copyImage, .copyText, .save, .qr]

    var body: some View {
        ZStack {
            SelectionView(
                image: image,
                availableActions: actions,
                onCancel: onFinish,
                onAction: handle
            )
            .environmentObject(settings)

            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .toast($toast)
        .sheet(isPresented: $showBarcodes) {
            BarcodeResultsSheet(hits: barcodes)
        }
    }

    private func handle(_ action: SnapAction, image cropped: UIImage, rect: CGRect) {
        Task {
            isWorking = true
            defer { isWorking = false }

            switch action {
            case .copyImage:
                UIPasteboard.general.image = cropped
                toast = .success("Image copied")
                Haptics.success()
                await dismissShortly()

            case .copyText:
                guard let result = try? await Recognizer.recognizeText(in: cropped), !result.isEmpty else {
                    toast = .failure("No text found")
                    Haptics.warning()
                    return
                }
                UIPasteboard.general.string = result.text
                toast = .success("Text copied", String(result.text.prefix(60)))
                Haptics.success()
                await dismissShortly()

            case .save:
                do {
                    let album = settings.saveToDedicatedAlbum ? settings.albumName : nil
                    let destination = try await PhotoLibraryService.save(cropped, toAlbumNamed: album)
                    switch destination {
                    case let .album(name):
                        toast = .success("Saved to Photos", "Album: \(name)")
                    case .library where album?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false:
                        toast = .success("Saved to Photos", "Saved to Recents; album access is unavailable here.")
                    case .library:
                        toast = .success("Saved to Photos")
                    }
                    Haptics.success()
                    await dismissShortly()
                } catch {
                    toast = .failure("Couldn't save", error.localizedDescription)
                    Haptics.warning()
                }

            case .qr:
                guard let hits = try? await Recognizer.detectBarcodes(in: cropped), !hits.isEmpty else {
                    toast = .failure("No codes found")
                    Haptics.warning()
                    return
                }
                barcodes = hits
                showBarcodes = true

            default:
                break
            }
        }
    }

    /// Let the toast be read before the sheet disappears.
    private func dismissShortly() async {
        try? await Task.sleep(nanoseconds: 900_000_000)
        onFinish()
    }
}

private struct BarcodeResultsSheet: View {
    let hits: [Recognizer.BarcodeHit]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(hits) { hit in
                        BarcodePayloadRow(payload: hit.payload, symbology: hit.symbology)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(hits.count == 1 ? "1 Code" : "\(hits.count) Codes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
