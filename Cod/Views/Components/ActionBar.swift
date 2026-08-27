import SwiftUI

/// The instant action row that appears under a fresh capture.
struct ActionBar: View {
    let actions: [SnapAction]
    var onTap: (SnapAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(actions) { action in
                    Button {
                        Haptics.tick()
                        onTap(action)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 46, height: 40)
                                .background(action.tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(action.tint.opacity(0.35), lineWidth: 0.5)
                                )
                                .foregroundStyle(action.tint)
                            Text(action.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 54)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
}
