import AppIntents
import SwiftUI

/// Hand-off point between an App Intent (which runs in the app's process once
/// `openAppWhenRun` brings us forward) and the running UI.
@MainActor
final class IntentInbox: ObservableObject {
    static let shared = IntentInbox()

    /// Image to open on the crop surface.
    @Published var pendingImage: UIImage?
    /// Image to send straight to the floating window, skipping the crop step.
    @Published var pendingFloatImage: UIImage?
    @Published var wantsLatestScreenshot = false
    @Published var wantsFloatLatest = false
    @Published var pendingQuickFloatRequestID: UUID?
    struct ReferenceInput: Identifiable {
        enum Content { case text(String), pdf(Data, page: Int), saved(UUID), animated(Data) }
        let id = UUID()
        let content: Content
    }
    @Published var pendingReference: ReferenceInput?

    func deliver(_ image: UIImage) {
        pendingReference = nil
        pendingImage = image
    }

    func deliverForFloat(_ image: UIImage) {
        pendingReference = nil
        pendingFloatImage = image
    }

    func requestLatestScreenshot() {
        pendingReference = nil
        wantsLatestScreenshot = true
    }

    func requestFloatLatest() {
        pendingReference = nil
        wantsFloatLatest = true
    }

    func deliverReference(_ content: ReferenceInput.Content) {
        pendingQuickFloatRequestID = nil
        pendingImage = nil
        pendingFloatImage = nil
        wantsLatestScreenshot = false
        wantsFloatLatest = false
        pendingReference = .init(content: content)
    }
}

/// A separate action preserves the installed image Shortcut's existing input
/// binding. Text is supplied explicitly, never taken silently from clipboard.
struct FloatTextWithCodIntent: AppIntent {
    static var title: LocalizedStringResource = "Float Text With Cod"
    static var description = IntentDescription("Float supplied text as a readable reference over other apps.", categoryName: "Floating")
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "Text", inputConnectionBehavior: .connectToPreviousIntentResult)
    var text: String
    static var parameterSummary: some ParameterSummary { Summary("Float \(\.$text) with Cod") }
    @MainActor func perform() async throws -> some IntentResult {
        _ = try FloatingText.render(text) // Fail with a useful message before handoff.
        IntentInbox.shared.deliverReference(.text(text))
        return .result()
    }
}

struct FloatPDFPageWithCodIntent: AppIntent {
    static var title: LocalizedStringResource = "Float PDF Page With Cod"
    static var description = IntentDescription("Float a numbered PDF page. To choose a region, open the PDF from Cod's Float tab.", categoryName: "Floating")
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @Parameter(title: "PDF", supportedTypeIdentifiers: ["com.adobe.pdf"], inputConnectionBehavior: .connectToPreviousIntentResult)
    var document: IntentFile
    @Parameter(title: "Page", default: 1, inclusiveRange: (1, 10_000))
    var page: Int
    static var parameterSummary: some ParameterSummary { Summary("Float page \(\.$page) of \(\.$document) with Cod") }
    @MainActor func perform() async throws -> some IntentResult {
        guard page >= 1 else { throw PDFReferenceError.invalidPage }
        let reference = try PDFReference(data: document.data)
        guard page <= reference.pageCount else { throw PDFReferenceError.invalidPage }
        IntentInbox.shared.deliverReference(.pdf(document.data, page: page))
        return .result()
    }
}

/// The intent that makes one-gesture capture work:
/// Shortcuts' **Take Screenshot** → **Crop With Cod**, bound to Back Tap or
/// the Action Button.
struct CropWithCodIntent: AppIntent {
    static var title: LocalizedStringResource = "Crop With Cod"
    static var description = IntentDescription(
        "Opens Cod's crop surface with an image, ready to select a region.",
        categoryName: "Capture"
    )
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    /// Required for the same reason as `FloatWithCodIntent` — an unwired
    /// optional silently fell back to "newest thing in the library", which is
    /// indistinguishable from a bug. Use `CropLatestScreenshotIntent` when you
    /// genuinely want the no-input behaviour.
    @Parameter(
        title: "Image",
        supportedTypeIdentifiers: ["public.image"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Crop \(\.$image) with Cod")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let decoded = UIImage.decodedImage(data: image.data) else {
            throw $image.needsValueError("Cod couldn't read that as an image.")
        }
        IntentInbox.shared.deliver(decoded)
        return .result()
    }
}

/// No-input variant, handy on its own for Back Tap when you'd rather take the
/// screenshot with the normal gesture first.
struct CropLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Crop Latest Screenshot"
    static var description = IntentDescription(
        "Opens Cod's crop surface with the newest item in your Screenshots album.",
        categoryName: "Capture"
    )
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.requestLatestScreenshot()
        return .result()
    }
}

/// The one-tap path: hand it an image and it goes straight to the floating
/// window, no crop surface, no action bar.
///
/// Turn on "Show in Share Sheet" for a shortcut wrapping this and it becomes a
/// share-sheet button that floats whatever you shared. A share *extension*
/// can't do this itself — extensions run out of process and AVKit won't give
/// one a Picture in Picture window.
struct FloatWithCodIntent: AppIntent {
    static var title: LocalizedStringResource = "Float With Cod"
    static var description = IntentDescription(
        "Sends an image straight to Cod's floating window, hovering it over every app.",
        categoryName: "Floating"
    )
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    /// Deliberately non-optional. As an optional it silently arrived `nil` when
    /// a shortcut didn't wire its input through, and the fallback grabbed the
    /// newest thing in the photo library — which looks exactly like the app
    /// floating a random photo. Required means Shortcuts fills it with the
    /// input only when the workflow connects it. Show in Share Sheet alone
    /// doesn't wire this field; the bundled installer supplies that binding.
    @Parameter(
        title: "Image",
        supportedTypeIdentifiers: ["public.image"],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Float \(\.$image) with Cod")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CodDiagnosticLog.record("float intent started bytes=\(image.data.count)")
        if AnimatedImageImport.isAnimatedGIF(image.data) {
            IntentInbox.shared.deliverReference(.animated(image.data))
            return .result()
        }
        guard let decoded = UIImage.decodedImage(data: image.data) else {
            CodDiagnosticLog.record("float intent couldn't decode supplied image")
            throw $image.needsValueError("Cod couldn't read that as an image.")
        }
        IntentInbox.shared.deliverForFloat(decoded)
        return .result()
    }
}

/// Same thing with no input — floats the newest screenshot whole. Ideal for
/// Back Tap or the Action Button.
struct FloatLatestScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Float Latest Screenshot"
    static var description = IntentDescription(
        "Floats your newest screenshot over every app, without cropping it first.",
        categoryName: "Floating"
    )
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.shared.requestFloatLatest()
        return .result()
    }
}

struct CodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FloatSavedReferenceIntent(),
            phrases: ["Float \(\.$target) with \(.applicationName)"],
            shortTitle: "Float Saved Reference", systemImageName: "star"
        )
        AppShortcut(
            intent: FloatLatestScreenshotIntent(),
            phrases: [
                "Float my latest screenshot with \(.applicationName)",
                "Float with \(.applicationName)",
            ],
            shortTitle: "Float Latest Screenshot",
            systemImageName: "pip.enter"
        )
        AppShortcut(
            intent: CropLatestScreenshotIntent(),
            phrases: [
                "Crop my latest screenshot with \(.applicationName)",
                "Snip with \(.applicationName)",
            ],
            shortTitle: "Crop Latest Screenshot",
            systemImageName: "viewfinder"
        )
    }
}
