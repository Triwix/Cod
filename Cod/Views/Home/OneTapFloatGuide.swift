import SwiftUI

/// Setup instructions for the fastest routes to a floating snippet.
struct OneTapFloatGuide: View {
    @Environment(\.openURL) private var openURL
    @State private var installingShortcut: FloatShortcut?

    var body: some View {
        List {
            Section {
                Text("For photos in another app, use Share → Float with Cod in the action list. Add that Shortcut below once. The Cod app icon cannot open Cod automatically.")
            }
            Section {
                step(1, "Take a screenshot and let it finish saving to **Photos**")
                step(2, "Open **Control Center**, hold an empty area, then **Add a Control**")
                step(3, "Search for **Cod** and add **Float Latest Screenshot**")
                step(4, "After a screenshot, open Control Center and tap the button")
            } header: {
                Label("Control Center · iOS 18+", systemImage: "switch.2")
            } footer: {
                Text("This floats your newest saved screenshot, not an arbitrary photo on screen. Cod opens to start PiP. Allow Photos access in Cod first; with Limited Access, only screenshots you have allowed are visible. iOS may require you to unlock before it runs.")
            }

            Section {
                step(1, "Hold your **Lock Screen**, choose **Customize**, then **Lock Screen**")
                step(2, "Replace a bottom control with Cod's **Float Latest Screenshot**")
                step(3, "On an iPhone with an **Action Button**, choose **Controls** in Settings → Action Button and select the same Cod control")
            } header: {
                Label("Lock Screen & Action Button", systemImage: "lock.iphone")
            } footer: {
                Text("iOS 18 or later. The Action Button is hardware-dependent; it isn't on every iPhone. These controls open Cod and require a saved screenshot plus Photos permission. They don't automatically return to the previous app.")
            }
            Section {
                step(1, "Open a photo or screenshot, tap **Share**, then **Cod**")
                step(2, "Cod prepares the image and dismisses the share screen automatically")
                step(3, "Open **Cod**; the image begins floating with no extra button")
                step(4, "Once the floating window appears, switch to the app you want to use")
            } header: {
                Label("Share app icon · manual fallback", systemImage: "square.and.arrow.up")
            } footer: {
                Text("For fewer steps, use the Float with Cod Shortcut in the share action list instead. If an app offers a direct Open in Cod image action, that can also open Cod. Choose Photo inside Cod floats directly. Turn off One tap float in Settings to crop first.")
            }

            Section {
                shortcutButton(.screenshot)
                if FloatShortcut.screenshot.fileURL != nil {
                    step(1, "Tap **Add Screenshot Shortcut** above, choose **Shortcuts**, and confirm **Add Shortcut**")
                } else {
                    step(1, "In **Shortcuts**, create **Screenshot and Float with Cod**: add **Take Screenshot**, then **Float With Cod**. Long-press the Image field and choose the Screenshot action's output")
                }
                step(2, "Settings → Accessibility → Touch → **Back Tap**")
                step(3, "Choose **Double Tap** or **Triple Tap**, then **Screenshot and Float with Cod**")
            } header: {
                Label("Back Tap", systemImage: "iphone.gen3")
            } footer: {
                Text("One-time setup is required by iOS. This Shortcut takes a new screenshot and passes that exact image to Cod; it doesn't search your photo library or read the clipboard. iOS may ask permission to share the image with Cod: Always Allow avoids repeating that prompt; Allow Once asks again next time. Wait for PiP, then switch apps yourself. If Shortcuts isn't offered for the file, save it to Files and open it there.")
            }

            Section {
                shortcutButton(.shareImage)
                if FloatShortcut.shareImage.fileURL != nil {
                    step(1, "Tap **Add Share-Sheet Shortcut**, choose **Shortcuts**, and confirm **Add Shortcut**")
                } else {
                    step(1, "In **Shortcuts**, create **Float with Cod**, add **Float With Cod**, then enable **Show in Share Sheet** in Details. Accept only **Images**; long-press the action's Image field and choose **Shortcut Input**")
                }
                step(2, "In Photos, tap **Share**, scroll to the action list, then **Float with Cod**")
                step(3, "When iOS asks to share the image with Cod, choose **Always Allow** if you want future runs without that prompt")
            } header: {
                Label("Share → Float with Cod", systemImage: "square.and.arrow.up")
            } footer: {
                Text("The installed Shortcut already enables Show in Share Sheet, accepts Images, and connects Float With Cod's Image field to Shortcut Input. It appears in the action list, not the row of app icons. First-run permission prompts are controlled by iOS; Allow Once repeats the prompt on the next run. After permission, Cod opens and starts floating. If you build it manually, long-press Image and choose Shortcut Input—don't choose a file.")
            }

            Section {
                step(1, "In **Cod → Settings → Share Sheet**, turn on **Tap notification to float** and allow notifications")
                step(2, "From an image, tap **Share → Cod**; then tap Cod's notification")
                step(3, "Keep **One tap float** on to skip cropping, or turn it off to crop before the notification")
            } header: {
                Label("Notification handoff", systemImage: "bell")
            } footer: {
                Text("This path doesn't use automatic app-opening workarounds. Delivery from the Share extension must be supported by your iOS version. If it fails, Cod shows an error and preserves the image: open Cod and tap Try Floating Again. Focus, notification summaries and disabled banners can delay or hide a notification. No image preview is included.")
            }

            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("Cod also registers **Float Latest Screenshot** and **Clear Cod Pins** automatically — search for them in Shortcuts or ask Siri.")
            }
        }
        .navigationTitle("Floating Guide")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $installingShortcut) { shortcut in
            if let url = shortcut.fileURL { ShortcutInstaller(url: url) }
        }
    }

    @ViewBuilder
    private func shortcutButton(_ shortcut: FloatShortcut) -> some View {
        if shortcut.fileURL != nil {
            Button {
                installingShortcut = shortcut
            } label: {
                Label(shortcut == .screenshot ? "Add Screenshot Shortcut" : "Add Share-Sheet Shortcut", systemImage: "square.and.arrow.down")
            }
        } else {
            Text("Shortcut file unavailable in this build. Use Open Shortcuts below to create it manually.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(.init(text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
