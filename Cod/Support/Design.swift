import SwiftUI

extension Color {
    /// Filled buttons use white text in both appearances. Keep their blue
    /// darker than the accent used for links on dark surfaces.
    static let codActionBackground = Color(red: 0, green: 0.408, blue: 0.780)
}

/// Shared touch targets and shape, rather than a different pill for each action.
/// Keep the system typeface, semantic surfaces and the existing Cod blue.
struct CodActionStyle: ButtonStyle {
    enum Emphasis: Equatable { case primary, secondary }
    var emphasis: Emphasis = .primary
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let primary = emphasis == .primary
        let ink: Color = primary ? .white : configuration.role == .destructive ? .red : .primary
        return configuration.label
            .font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
            .padding(.horizontal, compact ? 12 : 20)
            .padding(.vertical, 8)
            .frame(minHeight: compact ? 44 : 48)
            .foregroundStyle(ink)
            .background(
                primary ? Color.codActionBackground : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Navigation stays neutral; the content preview and Float action carry color.
struct CodRowLabel: View {
    let title: String
    let systemImage: String
    var detail: String? = nil
    @ScaledMetric(relativeTo: .body) private var iconSize = 18.0
    @ScaledMetric(relativeTo: .body) private var iconColumn = 24.0

    init(_ title: String, systemImage: String, detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}

private struct CodFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.defaultMinListRowHeight, 48)
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
    }
}

extension View {
    func codFormStyle() -> some View { modifier(CodFormStyle()) }
}
