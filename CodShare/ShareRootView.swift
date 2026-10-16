import SwiftUI
#if COD_LAUNCH_PROBE
import AppIntents
#endif

@MainActor
final class ShareFloatState: ObservableObject {
    enum Phase {
        case loading
        case opening
        case selecting(UIImage)
        #if COD_LAUNCH_PROBE
        case launchProbe
        #endif
        case failed(String)
    }

    @Published var phase: Phase = .loading
}

/// Personal builds can crop here; public builds need no confirmation tap.
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
                    #if COD_PERSONAL || COD_FAST_SHARE
                    Text("Floating image…").font(.headline)
                    #else
                    Text("Preparing image…").font(.headline)
                    #endif
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
            #if COD_LAUNCH_PROBE
            case .launchProbe:
                Text("Public launch experiment").font(.headline)
                Text("The image is ready. This tests whether an app-bound intent can bring Cod forward from the share extension.")
                Button(intent: FloatPendingWithCodIntent()) { Text("Test system Float") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("test-system-float")
            #endif
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
        #if COD_PERSONAL
        return false
        #else
        if case .opening = state.phase { return true }
        return false
        #endif
    }
}
