import SwiftUI

/// User-opened, not a modal gate: incoming Shortcuts and shares need no setup.
struct FloatingIntroductionView: View {
  @EnvironmentObject private var settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var installingShortcut: FloatShortcut?

  var body: some View {
    List {
      Section {
        Label("Keep it in view", systemImage: "pip.enter")
          .font(.title2.weight(.medium)).accessibilityAddTraits(.isHeader)
        Text(
          "Float a photo, reference, video or tool while you use another app. No account or setup is needed to start inside Cod."
        )
      }
      Section("1 · Try a float") {
        Text(
          "On Float, choose a photo or video, paste an image, or choose a file. Text includes an optional Teleprompter. Time & focus contains the timer and other tools."
        )
        Text(
          "Keep Cod open until the floating window appears. Then open another app yourself. Pinch the window to resize it; iOS controls its available sizes and buttons."
        )
      }
      Section {
        Text(
          "For the fewest steps from Photos: add the ready-made Shortcut once, then use Photos → Share → Float with Cod in the action list below the app icons."
        )
        if FloatShortcut.shareImage.fileURL != nil {
          Button {
            installingShortcut = .shareImage
          } label: {
            Label("Add Float with Cod", systemImage: "plus.circle.fill")
              .frame(minHeight: 44)
          }
          .buttonStyle(CodActionStyle())
          .accessibilityIdentifier("intro-install-shortcut")
          Text(
            "Choose Shortcuts, then confirm Add Shortcut. The shared-image input is already connected. iOS may ask permission the first time you run it."
          )
        }
        Text(
          "Adding the Shortcut is optional. Cod cannot install it or assign Back Tap, the Action Button or system controls without your involvement."
        )
        .font(.footnote).foregroundStyle(.secondary)
      } header: {
        Text("2 · Share directly with the Shortcut")
      }
      Section("3 · Why the app icon takes another step") {
        Text(
          "Share → Cod runs a small extension. iOS doesn't let that extension launch the full app directly, and Cod needs to open to start Picture in Picture."
        )
        Text(
          "With Tap notification to float enabled, tap Cod's notification after sharing. Otherwise open Cod manually. Focus and notification settings can hide the banner; your shared image remains available in Cod."
        )
        Text(
          "Cod uses the most direct supported routes available for each action, without private app-launch tricks. It cannot silently open in the background or switch you back to another app."
        )
      }
      Section {
        NavigationLink("All setup options & troubleshooting") { OneTapFloatGuide() }
        Button("Start Floating") { finish() }
          .buttonStyle(CodActionStyle()).frame(minHeight: 44)
          .accessibilityIdentifier("finish-introduction")
      } footer: {
        Text(
          "Permissions are requested only when you use a feature that needs them. You can reopen this introduction in Settings."
        )
      }
    }
    .codFormStyle()
    .navigationTitle("Quick introduction").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Skip") { finish() }.accessibilityIdentifier("skip-introduction")
      }
    }
    .sheet(item: $installingShortcut) { shortcut in
      if let url = shortcut.fileURL { ShortcutInstaller(url: url) }
    }
  }

  private func finish() {
    settings.hasCompletedIntroduction = true
    dismiss()
  }
}
