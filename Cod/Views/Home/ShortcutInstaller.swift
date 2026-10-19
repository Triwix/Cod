import SwiftUI
import UIKit

enum FloatShortcut: String, CaseIterable, Identifiable {
    case shareImage = "Float with Cod"
    case screenshot = "Screenshot and Float with Cod"

    var id: String { rawValue }
    var fileURL: URL? {
        guard
            let infoURL = Bundle.main.url(
                forResource: "InstallerInfo", withExtension: "plist", subdirectory: "Shortcuts/Store"),
            let data = try? Data(contentsOf: infoURL),
            let info = try? PropertyListDecoder().decode(ShortcutPackageIdentity.self, from: data),
            info.matches(
                bundleID: Bundle.main.bundleIdentifier,
                teamID: Bundle.main.object(forInfoDictionaryKey: "CodShortcutTeamIdentifier") as? String)
        else { return nil }
        return Bundle.main.url(
            forResource: rawValue, withExtension: "shortcut", subdirectory: "Shortcuts/Store")
    }
}

/// Signed workflows refer to an exact app/team. Don't offer a broken installer
/// if a future publisher changes identities without regenerating the package.
struct ShortcutPackageIdentity: Decodable {
    let bundleIdentifier: String
    let teamIdentifier: String
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "BundleIdentifier"
        case teamIdentifier = "TeamIdentifier"
    }
    func matches(bundleID: String?, teamID: String?) -> Bool {
        bundleID == bundleIdentifier && teamID == teamIdentifier
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
