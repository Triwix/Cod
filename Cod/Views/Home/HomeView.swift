import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var pins: PinManager
    @EnvironmentObject private var pip: PiPPinController
    @EnvironmentObject private var settings: AppSettings

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    #if DEBUG
                    if showsLaunchDiagnostics, let size = coordinator.lastExternalImageSize {
                        Text("Received image \(Int(size.width))x\(Int(size.height))")
                            .accessibilityIdentifier("received-image-size")
                    }
                    #endif
                    #if !COD_PERSONAL
                    if coordinator.quickSharePreview != nil { quickShare }
                    if !coordinator.sharedImages.isEmpty { sharedImages }
                    #endif
                    primaryCapture
                    if pip.isSupported { floatLatest }
                    secondaryRow
                    if !pins.isEmpty || pip.isActive || pip.status.isBusy { floatingStatus }
                    if !store.snaps.isEmpty { recents }
                    activationHint
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .navigationTitle("Cod")
            .background(Color(.systemGroupedBackground))
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    coordinator.toast = .failure("Couldn't read that image")
                    return
                }
                #if COD_PERSONAL
                coordinator.present(image: image, origin: .imported)
                #else
                coordinator.receiveExternalImage(image, origin: .imported)
                #endif
            }
        }
    }

    // MARK: - Primary

    #if DEBUG
    private var showsLaunchDiagnostics: Bool {
        #if COD_FAST_SHARE
        // System URL launches don't inherit XCTest process arguments. Keep
        // this diagnostic in FastDebug so cold-launch receipt is testable.
        return true
        #else
        return ProcessInfo.processInfo.arguments.contains("--launch-ui-test")
        #endif
    }
    #endif

    private var quickShare: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shared image", systemImage: "pip.enter").font(.headline)
            Text(settings.useFloatNotification
                 ? "Tap Cod's notification to float this image, or use Try Floating Again below. A newer share replaces this request."
                 : "A previous attempt didn't finish, or this image was shared more than five minutes ago. It won't reopen automatically.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Try Floating Again") { coordinator.receiveQuickShare(retry: true) }
                    .buttonStyle(.borderedProminent)
                Button("Remove", role: .destructive) { coordinator.discardQuickShare() }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var sharedImages: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Shared Images", systemImage: "tray")
                    .font(.headline)
                Spacer()
                Button { coordinator.refreshSharedImages() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh shared images")
            }
            if let error = coordinator.sharedInboxError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            } else if coordinator.sharedImages.isEmpty {
                Text("Images from the earlier test build. New shares no longer need inbox buttons.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(coordinator.sharedImages) { entry in
                    HStack(spacing: 12) {
                        Group {
                            if let thumbnail = entry.thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFit()
                            } else {
                                Image(systemName: "photo.badge.exclamationmark")
                            }
                        }
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Shared image preview")
                        VStack(alignment: .leading, spacing: 8) {
                            if let date = entry.receivedAt {
                                Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Unreadable image").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Float") { coordinator.openSharedImage(entry, float: true) }
                                    .buttonStyle(.borderedProminent)
                                Button("Crop") { coordinator.openSharedImage(entry, float: false) }
                                    .buttonStyle(.bordered)
                            }
                            .disabled(entry.thumbnail == nil || coordinator.pip.status.isBusy)
                        }
                        Spacer(minLength: 0)
                        Button(role: .destructive) { coordinator.removeSharedImage(entry) } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remove this image from Cod's inbox")
                    }
                }
                Text("Images stay here until you remove them. History is separate; clearing it doesn't empty this inbox.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 4)
    }

    private var primaryCapture: some View {
        Button {
            Task { await coordinator.captureLatestScreenshot() }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 36, weight: .light))
                Text("Crop Latest Screenshot")
                    .font(.headline)
                Text("Pulls the newest item from your Screenshots album")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    /// One tap from launch to a floating snippet.
    private var floatLatest: some View {
        Button {
            Task { await coordinator.floatLatestScreenshot() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "pip.enter")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Float Latest Screenshot")
                        .font(.subheadline.weight(.semibold))
                    Text("Straight to the hovering window, no cropping")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var secondaryRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                tile(title: "Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)

            Button {
                coordinator.pasteFromClipboard()
            } label: {
                tile(title: "Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
        }
    }

    private func tile(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Floating status

    private var floatingStatus: some View {
        VStack(spacing: 0) {
            if !pins.isEmpty {
                statusRow(
                    icon: "pin.fill",
                    tint: .orange,
                    title: "\(pins.pins.count) pinned snippet\(pins.pins.count == 1 ? "" : "s")",
                    detail: "Drag to move · pinch or corner-drag to resize",
                    actionTitle: "Clear All"
                ) {
                    pins.removeAll()
                }
            }

            if pip.isActive || pip.status.isBusy {
                if !pins.isEmpty { Divider().padding(.leading, 52) }
                statusRow(
                    icon: pip.isActive ? "pip.fill" : "hourglass",
                    tint: pip.isActive ? .red : .secondary,
                    title: pip.isActive ? "Floating over other apps" : "Opening floating window…",
                    detail: pip.isActive
                        ? "Swipe home — it stays on screen"
                        : "Waiting for iOS to hand over the window",
                    actionTitle: "Stop"
                ) {
                    pip.stop()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func statusRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(14)
    }

    // MARK: - Recents

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.snaps.prefix(12)) { snap in
                        Button {
                            coordinator.reopen(snap)
                        } label: {
                            SnapThumbnail(snap: snap)
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Hint

    private var activationHint: some View {
        NavigationLink {
            OneTapFloatGuide()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    #if COD_PERSONAL
                    Text("Set up one-tap floating")
                        .font(.subheadline.weight(.semibold))
                    #else
                    Text("How to float an image")
                        .font(.subheadline.weight(.semibold))
                    #endif
                    Text("Share sheet, Back Tap and the Action Button")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Thumbnail that loads lazily from the store's cache.
struct SnapThumbnail: View {
    let snap: Snap
    @EnvironmentObject private var store: SnapStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                // Fit, not fill: a snippet is only recognizable if you can see
                // its whole shape.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            }
        }
        .task(id: snap.id) {
            guard image == nil else { return }
            image = store.thumbnail(for: snap)
        }
        .clipped()
    }
}
