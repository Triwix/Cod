import SwiftUI

/// Shown when Cod was launched purely to float something.
///
/// iOS requires the app to be frontmost to hand a PiP window over, so it has to
/// appear for a moment. Showing this instead of the full app makes that moment
/// read as a confirmation rather than an app switch.
struct FloatingLaunchView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pip: PiPPinController
    @EnvironmentObject private var settings: AppSettings

    var onOpenApp: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                if let image = pip.currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 260, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if pip.status.isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: statusIcon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(statusTint)
                        }
                        Text(statusTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                    Text(statusDetail)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 10) {
                    if pip.isActive {
                        Button {
                            pip.stop()
                            onOpenApp()
                        } label: {
                            Text("Stop Floating")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    Button {
                        pip.keepCodOpenAfterFloating()
                        onOpenApp()
                    } label: {
                        Text("Open Cod")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
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
        default: return .white
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
            #if COD_PERSONAL
            return settings.returnAfterFloating
                ? "Returning to the previous app if iOS permits; otherwise Home. The image stays floating."
                : "Swipe home — the snippet stays on top of whatever you open."
            #else
            return "Switch to another app when you're ready. The image stays floating. Cod doesn't automatically change your screen."
            #endif
        case .preparing:
            return "Handing the snippet to the system window."
        case .unsupported:
            return "Picture in Picture isn't available on this device."
        case let .failed(message):
            return message
        case .idle:
            return ""
        }
    }
}
