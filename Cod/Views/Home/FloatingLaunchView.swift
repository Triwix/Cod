import SwiftUI

/// Shown when Cod was launched purely to float something.
///
/// iOS requires the app to be frontmost to hand a PiP window over, so it has to
/// appear for a moment. Showing this instead of the full app makes that moment
/// read as a confirmation rather than an app switch.
struct FloatingLaunchView: View {
    @EnvironmentObject private var pip: PiPPinController

    var onOpenApp: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)

                        if let image = pip.currentImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                                )
                                .accessibilityLabel("Image being floated")
                        }

                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                if pip.status.isBusy {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(Color.accentColor)
                                } else {
                                    Image(systemName: statusIcon)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(statusTint)
                                }
                                Text(statusTitle)
                                    .font(.title2.weight(.medium))
                                    .foregroundStyle(.primary)
                            }

                            Text(statusDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 400)
                                .padding(.horizontal, 24)
                        }

                        Spacer(minLength: 24)

                        VStack(spacing: 12) {
                            if pip.isActive {
                                Button {
                                    pip.stop()
                                    onOpenApp()
                                } label: {
                                    Text("Stop Floating").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(CodActionStyle(emphasis: .secondary))
                            }

                            Button {
                                onOpenApp()
                            } label: {
                                Text("Back to Cod").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(CodActionStyle())
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: 640, minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var statusIcon: String {
        switch pip.status {
        case .active: return "checkmark.circle.fill"
        case .failed, .unsupported: return "exclamationmark.triangle.fill"
        default: return "pip.enter"
        }
    }

    private var statusTint: Color {
        switch pip.status {
        case .active: return .green
        case .failed, .unsupported: return .orange
        default: return .accentColor
        }
    }

    private var statusTitle: String {
        switch pip.status {
        case .active: return "Floating"
        case .preparing: return "Opening…"
        case .unsupported: return "Not available"
        case .failed: return "Couldn't float"
        case .idle: return "Ready"
        }
    }

    private var statusDetail: String {
        switch pip.status {
        case .active:
            return
                "Open another app yourself; the image will stay floating above it. Cod doesn't switch apps for you."
        case .preparing:
            return "Handing the snippet to the system window."
        case .unsupported:
            return "Picture in Picture isn't available on this device."
        case .failed(let message):
            return message
        case .idle:
            return ""
        }
    }
}
