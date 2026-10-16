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

    func deliver(_ image: UIImage) {
        pendingImage = image
    }

    func deliverForFloat(_ image: UIImage) {
        pendingFloatImage = image
    }

    func requestLatestScreenshot() {
        wantsLatestScreenshot = true
    }

    func requestFloatLatest() {
        wantsFloatLatest = true
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
    /// share-sheet input automatically, and complains if it can't.
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
        guard let decoded = UIImage.decodedImage(data: image.data) else {
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

/// Clears every floating pin — the equivalent of Snapper's Control Center
/// "remove pinned snippets" module.
struct ClearCodPinsIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Cod Pins"
    static var description = IntentDescription(
        "Removes every pinned snippet and stops the floating window.",
        categoryName: "Pins"
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PinManager.shared.removeAll()
        PiPPinController.shared.stop()
        return .result()
    }
}

struct CodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
        AppShortcut(
            intent: ClearCodPinsIntent(),
            phrases: ["Clear \(.applicationName) pins"],
            shortTitle: "Clear Pins",
            systemImageName: "pin.slash"
        )
    }
}
