import SwiftUI

struct Toast: Equatable, Identifiable {
    enum Kind: Equatable {
        case success
        case failure
        case info

        var systemImage: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .green
            case .failure: return .orange
            case .info: return .blue
            }
        }
    }

    let id = UUID()
    var kind: Kind = .success
    var title: String
    var detail: String?

    static func success(_ title: String, _ detail: String? = nil) -> Toast {
        Toast(kind: .success, title: title, detail: detail)
    }

    static func failure(_ title: String, _ detail: String? = nil) -> Toast {
        Toast(kind: .failure, title: title, detail: detail)
    }

    static func info(_ title: String, _ detail: String? = nil) -> Toast {
        Toast(kind: .info, title: title, detail: detail)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.kind.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(toast.kind.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }
}

extension View {
    /// Presents a transient toast at the top of the screen.
    func toast(_ toast: Binding<Toast?>) -> some View {
        overlay(alignment: .top) {
            if let current = toast.wrappedValue {
                ToastView(toast: current)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(current.id)
                    .task(id: current.id) {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            toast.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.wrappedValue)
    }
}
