import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Images and text") {
                Text("Cod processes images, text recognition and barcode detection on your device. This version has no Imgur uploads, advertising, analytics or tracking.")
            }
            Section("Storage and deletion") {
                Text("Cod keeps one pending shared image in a local container used only by Cod and its Share extension. It is excluded from backups and removed after Picture in Picture starts successfully. A new share replaces the previous pending image. Failed or cancelled attempts remain available to retry or remove; old shares do not float automatically.")
                Text("Images saved in Shared Images by an earlier test build remain until you remove them there. Clearing history does not remove a pending share or those older images.")
                Text("History stores recent crops and recognized text separately. Change its limit or use Settings → Clear History to remove it. History may be included in your device's normal backup. Saved copies in Photos and images you send to other apps aren't deleted by clearing Cod's history.")
            }
            Section("Permissions and sharing") {
                Text("The photo picker lets you choose an image without giving Cod access to your whole library. Reading the latest screenshot requires Photos permission. Saving to Photos asks for permission when needed.")
                Text("Cod reads the clipboard only when you tap Paste, and writes when you choose a copy action. The Share extension doesn't use your clipboard to transfer images.")
                Text("Share, opening a scanned link, and the system Translate interface are explicit actions. The destination app, website or Apple service handles that data under its own policies.")
            }
            if let policyURL {
                Section {
                    Link("Privacy policy and contact", destination: policyURL)
                }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var policyURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CodPrivacyPolicyURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
