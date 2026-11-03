import SwiftUI

/// Own the native picker's presentation so the live preview remains undimmed.
struct FloatingAppearancePicker: View {
  @Binding var palette: FloatingPalette
  @Binding var customColors: FloatingColors?
  @Environment(\.colorScheme) private var colorScheme

  private var colors: FloatingColors {
    customColors ?? palette.colors(for: colorScheme == .dark ? .dark : .light)
  }

  var body: some View {
    Picker(
      "Preset",
      selection: Binding(
        get: { palette },
        set: {
          palette = $0
          customColors = nil
        })
    ) {
      ForEach(FloatingPalette.allCases) { Text($0.title).tag($0) }
    }
    .accessibilityIdentifier("floating-preset")
    if palette == .system, customColors == nil {
      Text("Uses your device's Light or Dark appearance.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    FloatingColorPicker(
      "Background color",
      selection: Binding(
        get: { colors.background },
        set: { customColors = FloatingColors(background: $0, foreground: colors.foreground) }
      )
    ).accessibilityIdentifier("floating-background-color")
    FloatingColorPicker(
      "Text color",
      selection: Binding(
        get: { colors.foreground },
        set: { customColors = FloatingColors(background: colors.background, foreground: $0) }
      )
    ).accessibilityIdentifier("floating-text-color")
    if customColors != nil {
      Button("Reset colors to preset") { customColors = nil }
    }
  }
}

private struct FloatingColorPicker: View {
  let title: String
  @Binding var selection: UIColor
  @State private var isPresented = false

  init(_ title: String, selection: Binding<UIColor>) {
    self.title = title
    _selection = selection
  }

  var body: some View {
    Button {
      isPresented = true
    } label: {
      HStack {
        Text(title).foregroundStyle(.primary)
        Spacer()
        Circle().fill(Color(uiColor: selection))
          .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
          .frame(width: 28, height: 28)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityHint("Opens the color picker. Changes appear in the preview immediately.")
    .sheet(isPresented: $isPresented) {
      NavigationStack {
        NativeFloatingColorPicker(selection: $selection, onFinish: { isPresented = false })
          .navigationTitle(title)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isPresented = false }
                .accessibilityIdentifier("floating-color-done")
            }
          }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationBackgroundInteraction(.enabled)
    }
  }
}

/// SwiftUI hosts the documented UIKit controller; no system hierarchy inspection.
private struct NativeFloatingColorPicker: UIViewControllerRepresentable {
  @Binding var selection: UIColor
  let onFinish: () -> Void

  func makeUIViewController(context: Context) -> UIColorPickerViewController {
    let picker = UIColorPickerViewController()
    picker.supportsAlpha = false
    picker.selectedColor = selection
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
    context.coordinator.parent = self
    if !picker.selectedColor.isEqual(selection) { picker.selectedColor = selection }
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
    var parent: NativeFloatingColorPicker
    init(parent: NativeFloatingColorPicker) { self.parent = parent }

    func colorPickerViewController(
      _ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool
    ) {
      parent.selection = color
    }

    func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
      parent.onFinish()
    }
  }
}
