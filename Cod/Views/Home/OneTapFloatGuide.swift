import SwiftUI

/// Setup instructions for the fastest routes to a floating snippet.
struct OneTapFloatGuide: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                #if COD_PERSONAL
                step(1, "Open a photo or screenshot and tap **Share**")
                step(2, "Tap **Cod** in the row of apps, choose a crop, then tap **Float**")
                step(3, "If Cod isn't visible, swipe to **More**, tap **Edit**, and add Cod to your favourites")
                #elseif COD_FAST_SHARE
                step(1, "Open a photo or screenshot, tap **Share**, then **Cod Test**")
                step(2, "Cod opens and starts the floating window automatically")
                step(3, "Once the window appears, switch apps when you're ready")
                #else
                step(1, "Open a photo or screenshot, tap **Share**, then **Cod**")
                step(2, "Cod prepares the image and dismisses the share screen automatically")
                step(3, "Open **Cod**; the image begins floating with no extra button")
                step(4, "Once the floating window appears, switch to the app you want to use")
                #endif
            } header: {
                Label("Share sheet floating", systemImage: "square.and.arrow.up")
            } footer: {
                #if COD_PERSONAL
                Text("Cropping is the default. For immediate whole-image floating, turn on Settings → Share Sheet → One tap float. No Shortcut setup is needed for either share-sheet mode. Cod briefly opens to create Picture in Picture; automatic return to the source screen is still unresolved on the tested phone and currently falls back to Home.")
                #elseif COD_FAST_SHARE
                Text("One tap float defaults on. Turn it off in Settings to crop inside the share sheet before tapping Float. No Shortcut setup is required. This fast-share test uses an unsupported launch workaround; it is not App Store approval. Returning to the previous app is manual in this build.")
                #else
                Text("This is the current public-only fallback, not one-tap Share → PiP. If an app offers Open in Cod for an image, that direct route needs no separate app-open or Float button. You can also choose a photo inside Cod to float it directly. Turn off One tap float in Settings to crop first.")
                #endif
            }

            Section {
                step(1, "In Shortcuts, make a shortcut with **Take Screenshot** → **Float With Cod**")
                step(2, "Settings → Accessibility → Touch → **Back Tap**")
                step(3, "Choose **Double Tap** and pick that shortcut")
            } header: {
                Label("Back Tap", systemImage: "iphone.gen3")
            } footer: {
                Text("The Shortcut takes a screenshot and opens Cod to float it. Wait for the floating window, then switch apps yourself. Use Crop With Cod instead to select a region first.")
            }

            Section {
                step(1, "Settings → **Action Button**")
                step(2, "Swipe to **Shortcut** and pick the same shortcut")
            } header: {
                Label("Action Button", systemImage: "button.horizontal.top.press")
            } footer: {
                Text("Available on iPhones with an Action Button.")
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
