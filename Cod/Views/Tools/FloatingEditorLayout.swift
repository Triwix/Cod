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

/// The floating window's preview, drawn in every shape side by side. Swipe
/// it to choose the window's shape: the one in the middle is what floats,
/// and the shapes on either side show faded so it's clear you can swipe.
struct ShapeCarousel: View {
  @Binding var selection: FloatWindowShape
  let label: String
  var value: String? = nil
  let render: (FloatWindowShape) -> UIImage
  @State private var position: FloatWindowShape?
  @Environment(\.floatingPreviewHeight) private var height

  /// The middle preview takes most of the width; the rest shows neighbours.
  private static let itemShare: CGFloat = 0.6
  /// Pulls neighbours in so about half of each one is visible.
  private static let overlap: CGFloat = -36
  /// The editor pads its header; let the strip run to the screen edges.
  private static let bleed: CGFloat = 20

  var body: some View {
    VStack(spacing: 8) {
      GeometryReader { geometry in
        let itemWidth = geometry.size.width * Self.itemShare
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Self.overlap) {
            ForEach(FloatWindowShape.allCases) { shape in
              let selected = shape == selection
              FloatingPreviewImage(
                image: render(shape),
                label: selected ? label : "\(shape.title) window",
                value: selected ? value : nil)
                .padding(.horizontal, 8)
                .frame(width: itemWidth, height: height)
                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                  content
                    .opacity(phase.isIdentity ? 1 : 0.4)
                    .scaleEffect(phase.isIdentity ? 1 : 0.78)
                }
                .onTapGesture {
                  withAnimation(.snappy) { position = shape }
                  selection = shape
                }
                .accessibilityHidden(!selected)
                .id(shape)
            }
          }
          .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (geometry.size.width - itemWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .accessibilityIdentifier("window-shape-carousel")
      }
      .frame(height: height)
      .padding(.horizontal, -Self.bleed)
      caption
    }
    .onAppear { position = selection }
    .onChange(of: position) { _, shape in
      if let shape, shape != selection { selection = shape }
    }
    .onChange(of: selection) { _, shape in
      if position != shape { withAnimation(.snappy) { position = shape } }
    }
    .sensoryFeedback(.selection, trigger: selection)
  }

  private var caption: some View {
    HStack(spacing: 10) {
      Text("\(selection.ratio) · \(selection.title)")
        .font(.footnote.weight(.semibold)).monospacedDigit()
        .foregroundStyle(.secondary)
      HStack(spacing: 5) {
        ForEach(FloatWindowShape.allCases) { shape in
          Circle()
            .fill(shape == selection ? Color.primary : Color.secondary.opacity(0.4))
            .frame(width: 6, height: 6)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Window shape")
    .accessibilityValue("\(selection.title), \(selection.ratio)")
    .accessibilityHint("Swipe the preview, or swipe up or down here, to change it")
    .accessibilityAdjustableAction { direction in
      let all = FloatWindowShape.allCases
      guard let index = all.firstIndex(of: selection) else { return }
      switch direction {
      case .increment: if index + 1 < all.count { selection = all[index + 1] }
      case .decrement: if index > 0 { selection = all[index - 1] }
      @unknown default: break
      }
    }
    .accessibilityIdentifier("window-shape-caption")
  }
}
