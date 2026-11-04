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
                Text("Cod opens to start Picture in Picture. After it appears, open another app yourself; Cod doesn't switch apps for you.")
                Text("The Cod app icon in Share runs a small extension, not the full Cod app. iOS doesn't let that extension launch Cod directly. A Shortcut or system control can open Cod; tapping a notification or opening Cod yourself also works.")
                Text("For the fewest steps from a shared image, use Float with Cod in the Share action list below the app icons. One tap float only skips cropping—it doesn't change how iOS opens apps.")
                Text("Cod uses the most direct supported route for each entry point, without private app-launch tricks. These steps follow iOS's app-opening rules; they're not an extra confirmation needed by Cod.")
            } header: { Text("Why these steps?") }

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
                Label("Back Tap · float immediately", systemImage: "hand.tap")
            } footer: {
                Text(
                    "This takes a new screenshot when you trigger it and sends that image to Cod. Setup and Back Tap assignment remain under your control. You can also assign the Shortcut to an available Action Button."
                )
            }

            Section {
                step(1, "In **Shortcuts**, create a new shortcut with **Take Screenshot**.")
                step(2, "Add Cod's **Crop With Cod** action. Press and hold its **Image** field → **Select Variable** → choose the **Screenshot** output from Take Screenshot.")
                step(3, "Name it **Screenshot, Crop, then Float**. In iPhone Settings → **Accessibility → Touch → Back Tap**, assign it to Double Tap or Triple Tap.")
                step(4, "Back Tap to open the fresh screenshot in Cod's crop editor. Draw a region, then **double-tap inside it** or tap **Float**.")
            } header: {
                Label("Back Tap · crop first", systemImage: "crop")
            } footer: {
                Text("Choose one Back Tap flow, or assign one to Double Tap and the other to Triple Tap. Crop With Cod always opens the editor, even when One tap float is on. Crop Latest Screenshot uses a previously saved photo instead of taking a new screenshot.")
            }

            Section {
                step(1, "Take a screenshot and let it finish saving to **Photos**.")
                step(2, "In **Control Center**, hold an empty area → **Add a Control** → search **Cod**.")
                step(
                    3, "Add **Float Latest Screenshot**. Grant Photos access in Cod, then use the control.")
                Text(
                    "On supported iPhones, you can also assign it in Settings → Action Button → Controls."
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
                step(1, "Touch and hold your **Lock Screen**, then choose **Customize → Lock Screen**.")
                step(2, "Remove one of the bottom-corner controls, such as Camera or Flashlight, then tap **+**.")
                step(3, "Search **Cod**, select **Float Latest Screenshot**, then finish customization.")
                Text("This is optional and isn't added automatically. It uses the latest saved screenshot; iOS may ask you to unlock before Cod opens. It's separate from a timer's Lock Screen alarm display.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Label("Lock Screen control · add it yourself", systemImage: "lock") }

            Section {
                Text("Tap the floating window once to show iOS's playback buttons. The expand/return-to-full-screen button opens Cod and may close PiP. Apple calls it Restore Full Screen; its appearance and position are controlled by iOS.")
                Text("If you don't see that button, open Cod normally. You don't need a separate restore option in Cod's settings.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Label("Return to Cod from PiP", systemImage: "pip.exit") }

            Section {
                step(1, "In Cod Settings, enable **Tap notification to float** and allow notifications.")
                step(2, "From an image, use **Share → Cod**, then tap Cod's notification.")
                Text(
                    "With One tap float off, crop and tap Float before the notification. If notifications are unavailable, follow the message to open Cod manually. With notification handoff turned off in Cod, just open Cod after sharing, cropping there if needed."
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
                    "Cod also supplies Float Latest Screenshot and Crop Latest Screenshot actions in Shortcuts. iOS controls the PiP window's buttons and resizing; Cod never switches you back to another app automatically."
                )
            }
        }
        .codFormStyle()
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
                .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(CodActionStyle())
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
                .font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 24, minHeight: 24)
                .accessibilityHidden(true)
            Text(.init(text)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}
