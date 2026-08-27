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
                coordinator.present(image: image, origin: .imported)
            }
        }
    }

    // MARK: - Primary

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
                    Text("Set up one-tap floating")
                        .font(.subheadline.weight(.semibold))
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
