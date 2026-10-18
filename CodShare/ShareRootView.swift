import SwiftUI

@MainActor
final class ShareFloatState: ObservableObject {
    enum Phase {
        case loading
        case opening
        case selecting(UIImage)
        case failed(String)
    }

    @Published var phase: Phase = .loading
}

/// Notification handoffs can crop here; the manual-open fallback prepares its
/// request without a confirmation tap and opens cropping in Cod when needed.
struct ShareRootView: View {
    @ObservedObject var state: ShareFloatState
    var onFinish: () -> Void
    var onRetry: () -> Void
    var onFloat: (UIImage) -> Void

    var body: some View {
        if case .selecting(let image) = state.phase {
            SelectionView(
                image: image,
                availableActions: [.float],
                smartRegionsEnabled: false,
                onCancel: onFinish,
                onAction: { _, cropped, _ in onFloat(cropped) }
            )
            .environmentObject(AppSettings.shared)
        } else {
            statusView
        }
    }

    private var statusView: some View {
        VStack(spacing: 20) {
            switch state.phase {
            case .loading, .opening:
                ProgressView()
                    .controlSize(.large)
                if case .loading = state.phase {
                    Text("Loading image…").font(.headline)
                } else {
                    Text("Preparing image…").font(.headline)
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text("Couldn't start floating")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            case .selecting:
                EmptyView()
            }
            Button("Cancel", action: onFinish)
                .buttonStyle(.bordered)
                .disabled(isSaving)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var isSaving: Bool {
        if case .opening = state.phase { return true }
        return false
    }
}
