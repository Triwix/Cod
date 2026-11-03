import SwiftUI

private struct FloatingPreviewHeight: EnvironmentKey {
  static let defaultValue: CGFloat = 180
}

extension EnvironmentValues {
  var floatingPreviewHeight: CGFloat {
    get { self[FloatingPreviewHeight.self] }
    set { self[FloatingPreviewHeight.self] = newValue }
  }
}

/// Keep the result and primary action visible; only the settings scroll.
/// The header shrinks with the available height, including the keyboard.
struct FloatingEditorLayout<Preview: View, Settings: View>: View {
  @ViewBuilder var preview: () -> Preview
  @ViewBuilder var settings: () -> Settings

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        VStack(spacing: 12) {
          Text("Preview")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("floating-preview-label")
          preview()
        }
        .environment(\.floatingPreviewHeight, max(32, min(176, geometry.size.height * 0.27 - 24)))
        .frame(maxWidth: 720)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        Divider()
        Form(content: settings)
          .codFormStyle()
          .accessibilityIdentifier("float-settings")
          .scrollDismissesKeyboard(.interactively)
      }
    }
    .background(Color(.systemGroupedBackground))
  }
}

struct FloatingPreviewImage: View {
  let image: UIImage
  let label: String
  var value: String? = nil
  @Environment(\.floatingPreviewHeight) private var height

  var body: some View {
    FittedPreviewLayout(imageSize: image.size, maximumHeight: height) {
      Image(uiImage: image).resizable()
        // Clip the image's fitted bounds, not its surrounding letterbox.
        // Short/wide and tall text must have rounded corners too.
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
  }

  static func fittedSize(_ image: CGSize, within bounds: CGSize) -> CGSize {
    guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else {
      return .zero
    }
    let scale = min(bounds.width / image.width, bounds.height / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
  }
}

/// The available height is a ceiling. A short text card should not reserve
/// an entire video-sized rectangle above the editor.
private struct FittedPreviewLayout: Layout {
  let imageSize: CGSize
  let maximumHeight: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
      ?? min(720, imageSize.width)
    let fitted = FloatingPreviewImage.fittedSize(imageSize, within: CGSize(width: width, height: maximumHeight))
    return CGSize(width: width, height: fitted.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let fitted = FloatingPreviewImage.fittedSize(imageSize, within: bounds.size)
    subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                         proposal: ProposedViewSize(width: fitted.width, height: fitted.height))
  }
}
