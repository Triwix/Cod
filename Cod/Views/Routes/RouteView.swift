import SwiftUI
#if canImport(Translation)
import Translation
#endif

/// Everything an action might need to put on screen after it runs.
struct RouteView: View {
    let route: CaptureCoordinator.Route

    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch route.kind {
        case let .share(items):
            ShareSheet(items: items)
                .ignoresSafeArea()

        case let .barcodes(hits):
            BarcodeResultsView(hits: hits)

        case let .text(text):
            TextResultView(title: "Recognized Text", text: text)

        case let .translate(text):
            TranslateResultView(text: text)

        case let .annotate(image):
            AnnotateView(image: image) { edited in
                UIPasteboard.general.image = edited
                coordinator.toast = .success("Edited image copied")
                dismiss()
            }

        case .confirmUpload:
            Text("Uploads aren't included in this version.")
        }
    }
}

// MARK: - Share

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Barcodes

struct BarcodeResultsView: View {
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

// MARK: - Text

struct TextResultView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        Haptics.success()
                    } label: { Image(systemName: "doc.on.doc") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Translate

struct TranslateResultView: View {
    let text: String
    @State private var showTranslation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !systemTranslationAvailable {
                        Text("Select the text above and choose Translate from the menu to use the system translator.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                if systemTranslationAvailable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Translate") { showTranslation = true }
                    }
                }
            }
            .modifier(SystemTranslationModifier(isPresented: $showTranslation, text: text))
        }
        .presentationDetents([.medium, .large])
    }

    private var systemTranslationAvailable: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }
}

/// Wraps `translationPresentation`, which only exists on iOS 17.4+.
private struct SystemTranslationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let text: String

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
