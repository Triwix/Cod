import SwiftUI

/// Setup instructions for the three fastest routes to a floating snippet.
struct OneTapFloatGuide: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                step(1, "Open Shortcuts and make a new shortcut")
                step(2, "Add the action **Float With Cod**")
                step(3, "Open the shortcut's settings (ⓘ) and turn on **Show in Share Sheet**")
                step(4, "Back in the editor, tap the **Image** field in the Float With Cod action and choose **Shortcut Input**")
                step(5, "Name it something short — that name is the button you'll tap")
            } header: {
                Label("Share sheet button", systemImage: "square.and.arrow.up")
            } footer: {
                Text("Step 4 is the one that matters. Without it the action has no image to work with and nothing useful happens.\n\nIf you see a bar at the top of the editor saying it receives input from the share sheet, you can tap the listed types to narrow them to images — but that's optional; Cod ignores anything that isn't an image.\n\nCod's own share extension stays in the list too, but it's for cropping and OCR. An extension runs outside the app and iOS won't give one a Picture in Picture window, so floating has to go through a shortcut.")
            }

            Section {
                step(1, "In Shortcuts, make a shortcut with **Take Screenshot** → **Float With Cod**")
                step(2, "Settings → Accessibility → Touch → **Back Tap**")
                step(3, "Choose **Double Tap** and pick that shortcut")
            } header: {
                Label("Back Tap", systemImage: "iphone.gen3")
            } footer: {
                Text("Double-tap the back of the phone in any app: it screenshots, opens Cod, and floats it. No cropping — use Crop With Cod instead if you want to pick a region first.")
            }

            Section {
                step(1, "Settings → **Action Button**")
                step(2, "Swipe to **Shortcut** and pick the same shortcut")
            } header: {
                Label("Action Button", systemImage: "button.horizontal.top.press")
            } footer: {
                Text("iPhone 15 Pro and later.")
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
        .navigationTitle("One-Tap Floating")
        .navigationBarTitleDisplayMode(.inline)
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
