import SwiftUI

@MainActor
final class ShareFloatState: ObservableObject {
  enum Phase {
    case loading
    case opening
    case selecting(UIImage)
    case ready(ReadyReason)
    case failed(String)
  }

  enum ReadyReason: Equatable {
    /// The normal app-icon route: the image is queued for the next Cod launch.
    case openCod(crop: Bool)
    /// Notification mode saved the image but couldn't schedule the banner.
    case notificationUnavailable
    /// A web link waits for Cod's web video screen.
    case openCodForLink
  }

  @Published var phase: Phase = .loading
}

/// Notification handoffs can crop here; the manual-open route prepares its
/// request without a confirmation tap, then says to open Cod to continue.
struct ShareRootView: View {
  @ObservedObject var state: ShareFloatState
  var onFinish: () -> Void
  var onRetry: () -> Void
  var onFloat: (UIImage) -> Void

  var body: some View {
    if case .selecting(let image) = state.phase {
      VStack(spacing: 0) {
        SelectionView(
          image: image,
          availableActions: [.float],
          smartRegionsEnabled: false,
          onCancel: onFinish,
          onAction: { _, cropped, _ in onFloat(cropped) }
        )
        .environmentObject(AppSettings.shared)
        Text(
          "After Float, tap Cod's notification or open Cod yourself. For automatic opening, use the Float with Cod Shortcut instead."
        )
        .font(.footnote).foregroundStyle(.secondary).padding(12)
        .background(Color(.systemBackground))
      }
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
          .tint(.codActionBackground).foregroundStyle(.white)
      case .ready(let reason):
        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
        Text(reason == .openCodForLink ? "Link ready" : "Image ready").font(.headline)
          .accessibilityIdentifier("share-image-ready")
        Group {
          switch reason {
          case .openCod(let crop):
            Text("Tap Done, then open Cod to \(crop ? "crop and float" : "float") it.")
          case .openCodForLink:
            Text("Tap Done, then open Cod within 5 minutes. The page opens there; start the video and tap Float.")
          case .notificationUnavailable:
            Text(
              "Your image is saved, but notifications are off or unavailable. Tap Done, then open Cod manually to float it."
            )
          }
        }
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("share-ready-instructions")
        Text(
          reason == .openCodForLink
            ? "iOS doesn't let this Share extension open the app, so open Cod yourself."
            : "The Cod icon in Share prepares the image; iOS doesn't let this Share extension open the app. The Float with Cod Shortcut can open it directly."
        )
        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
      case .selecting:
        EmptyView()
      }
      Button(isReady ? "Done" : "Cancel", action: onFinish)
        .buttonStyle(.bordered)
        .accessibilityIdentifier(isReady ? "share-ready-done" : "share-cancel")
        .disabled(isSaving)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemBackground))
  }

  private var isReady: Bool {
    if case .ready = state.phase { return true }
    return false
  }

  private var isSaving: Bool {
    if case .opening = state.phase { return true }
    return false
  }
}
