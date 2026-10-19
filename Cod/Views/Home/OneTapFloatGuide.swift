import SwiftUI

/// Share setup comes first. Every installer contains the actual image binding.
struct OneTapFloatGuide: View {
    @Environment(\.openURL) private var openURL
    @State private var installingShortcut: FloatShortcut?

    var body: some View {
        List {
            Section {
                Label("Your image. Over any app.", systemImage: "pip.enter").font(.title2.weight(.semibold))
                Text(
                    "Choose the route that fits you. Cod opens to start Picture in Picture; switch apps once the image is floating."
                )
                .foregroundStyle(.secondary)
            }

            Section {
                shortcutButton(.shareImage)
                step(
                    1,
                    "Choose **Shortcuts** in the menu, then confirm **Add Shortcut**. Everything is already connected."
                )
                step(2, "In **Photos**, open an image → **Share** → scroll down → **Float with Cod**.")
                step(3, "Approve any first-use image-sharing prompt from iOS.")
            } header: {
                Text("Recommended · Share → Float with Cod")
            } footer: {
                Text(
                    "One-time setup. This is an action below the app icons, not the Cod app icon. It uses the photo you shared—not the clipboard or a recent photo. Choose Always Allow only if you want to avoid repeated image-sharing prompts."
                )
            }

            Section {
                Text(
                    "If a Shortcut asks for “Image,” its input may not be connected. In its editor, press and hold Image inside Float With Cod, then choose Shortcut Input. It should read “Float Shortcut Input with Cod.”"
                )
                .font(.subheadline)
                Text(
                    "Turning on Show in Share Sheet alone doesn't connect that field. The installer above includes both settings."
                )
                .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Already made your own Shortcut?")
            }

            Section {
                shortcutButton(.screenshot)
                step(1, "Choose **Shortcuts**, then confirm **Add Shortcut**.")
                step(2, "iPhone Settings → **Accessibility → Touch → Back Tap**.")
                step(3, "Assign **Screenshot and Float with Cod** to Double Tap or Triple Tap.")
            } header: {
                Label("Back Tap · a fresh screenshot", systemImage: "hand.tap")
            } footer: {
                Text(
                    "This takes a new screenshot when you trigger it and sends that image to Cod. Setup and Back Tap assignment remain under your control. You can also assign the Shortcut to an available Action Button."
                )
            }

            Section {
                step(1, "Take a screenshot and let it finish saving to **Photos**.")
                step(2, "In **Control Center**, hold an empty area → **Add a Control** → search **Cod**.")
                step(
                    3, "Add **Float Latest Screenshot**. Grant Photos access in Cod, then use the control.")
                Text(
                    "The same control can be added when customizing the Lock Screen, or in Settings → Action Button → Controls on supported iPhones."
                )
                .font(.subheadline)
            } header: {
                Label("System controls · iOS 18+", systemImage: "switch.2")
            } footer: {
                Text(
                    "Uses the newest saved screenshot, not whichever image is visible. With Limited Photos Access, only allowed screenshots are available. iOS may require unlocking. The Action Button isn't available on every iPhone."
                )
            }

            Section {
                step(1, "In Cod Settings, enable **Tap notification to float** and allow notifications.")
                step(2, "From an image, use **Share → Cod**, then tap Cod's notification.")
                Text(
                    "With One tap float off, crop and tap Float before the notification. Without notifications, Share → Cod prepares the image; open Cod yourself to continue."
                )
                .font(.subheadline)
            } header: {
                Label("Cod app icon · optional fallback", systemImage: "bell")
            } footer: {
                Text(
                    "The Cod app icon cannot automatically open Cod. Focus, summaries and banner settings can hide or delay notifications. Failed requests stay available for explicit retry. No image preview is included in the notification."
                )
            }

            Section {
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                }
            } footer: {
                Text(
                    "Cod also supplies Float Latest Screenshot, Crop Latest Screenshot and Clear Pins actions in Shortcuts. iOS controls the PiP window's buttons and resizing; Cod never switches you back to another app automatically."
                )
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
                Label(
                    shortcut == .shareImage ? "Add Share-Sheet Shortcut" : "Add Screenshot Shortcut",
                    systemImage: "plus.circle.fill"
                )
                .font(.headline).frame(minHeight: 44)
            }
            .accessibilityIdentifier(
                shortcut == .shareImage ? "install-share-shortcut" : "install-screenshot-shortcut")
        } else {
            Text(
                "The installer isn't available in this build. Open Shortcuts and use Float With Cod with its Image field connected to Shortcut Input (sharing) or the Take Screenshot output (Back Tap)."
            )
            .font(.footnote)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                .frame(minWidth: 24, minHeight: 24)
                .background(Color.accentColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            Text(.init(text)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}
