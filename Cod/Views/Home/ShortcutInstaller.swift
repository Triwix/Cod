import SwiftUI
import UIKit

enum FloatShortcut: String, CaseIterable, Identifiable {
    case shareImage = "Float with Cod"
    case screenshot = "Screenshot and Float with Cod"

    var id: String { rawValue }
    var fileURL: URL? {
        #if COD_PERSONAL
        let folder = "Personal"
        #else
        let folder = "Store"
        #endif
        return Bundle.main.url(forResource: rawValue, withExtension: "shortcut", subdirectory: "Shortcuts/\(folder)")
    }
}

/// The system's Shortcuts activity imports the signed file after the user
/// approves it. Apps cannot silently install or assign a user's Shortcuts.
struct ShortcutInstaller: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
