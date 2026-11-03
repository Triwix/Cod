import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Images, documents and text") {
                Text("Cod processes chosen images, local videos, PDF pages, typed/shared text, text recognition and barcode detection on your device. This version has no uploads, advertising, analytics or tracking.")
            }
            Section("Storage and deletion") {
                Text("Named text cards and tool/script presets are deliberate local saves, separate from History. They keep editable content, appearance and timing settings, and an original image when saved from text recognition. Delete them in Library → Saved cards & presets. Delete Everything in Library also removes these saves; Clear Recent History does not.")
                Text("Saved cards and a catalog of Library favorites are available to Cod's own widgets and controls through its shared local container. Widget labels show reference names, not text or image contents. Removing a saved item makes its old Shortcut or control stop working until you choose another item. No iCloud sync or remote service is used.")
                Text("Cod keeps one pending shared image in a local container used only by Cod and its Share extension. It is excluded from backups and removed after Picture in Picture starts successfully. A new share replaces the previous pending image. Failed or cancelled attempts remain available to retry or remove; old shares do not float automatically.")
                Text("Images saved in Shared Images by an earlier test build remain until you remove them there. Clearing history does not remove a pending share or those older images.")
                Text("History stores recent images, imported video copies and recognized text separately. Favorites survive history limits, Off and Clear Recent History. Clear Library also offers Delete Everything, Including Favorites, after confirmation. History may be included in your device's normal backup. Original media in Photos or Files, saved Photos copies and images you send to other apps aren't deleted by clearing Cod's library.")
                Text("Text and teleprompter drafts are saved locally between visits. Delete their text in the editor to clear a draft. Clearing image history doesn't clear these drafts. Selected PDFs are read to render pages; Cod doesn't keep a separate copy of the original PDF.")
                Text("Animated GIFs are converted locally into temporary videos for playback. Video cropping creates a temporary edited copy and does not modify the original. Scrolling references render only the selected image or bounded PDF page range locally.")
            }
            Section("Permissions and sharing") {
                Text("The photo picker lets you choose an image or video without giving Cod access to your whole library. Reading the latest screenshot requires Photos permission. Saving to Photos asks for permission when needed.")
                Text("Cod reads the clipboard only when you tap Paste, and writes when you choose a copy action. The Share extension doesn't use your clipboard to transfer images.")
                Text("Share, opening a scanned link, and the system Translate interface are explicit actions. The destination app, website or Apple service handles that data under its own policies.")
                Text("Optional Shortcuts use the image you share or a screenshot you explicitly trigger. You approve installing them in Shortcuts. Optional local float notifications contain only a request identifier, with no image preview.")
                Text("Text and PDF Shortcut actions use only the input you supply. Timers measure elapsed time locally; no timing data is sent anywhere. On iOS 26 or later, enabling Alarm when finished asks permission to schedule a local system alarm. Cod stores its identifier and finish time locally so you can cancel it even after reopening the app. A native countdown Live Activity also lets you cancel the timer. Keep running when PiP closes is on by default; turning it off makes closing PiP cancel that timer's alarm.")
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
