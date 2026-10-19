import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var pins: PinManager
    @EnvironmentObject private var pip: PiPPinController
    @EnvironmentObject private var settings: AppSettings

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var installingShortcut: FloatShortcut?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    #if DEBUG
                        if let size = coordinator.lastExternalImageSize {
                            Text("Received image \(Int(size.width))x\(Int(size.height))")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("received-image-size")
                        }
                    #endif
                    if coordinator.quickSharePreview != nil { quickShare }
                    if pip.isActive || pip.status.isBusy || !pins.isEmpty { floatingStatus }
                    choosePhoto
                    if !settings.hasDismissedFloatSetupTip { setupCard }
                    screenshotActions
                    if !coordinator.sharedImages.isEmpty || coordinator.sharedInboxError != nil { sharedImages }
                    if !store.snaps.isEmpty { recents }
                    NavigationLink {
                        OneTapFloatGuide()
                    } label: {
                        Label("Floating guide & setup", systemImage: "questionmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .navigationTitle("Cod")
            .background(Color(.systemGroupedBackground))
        }
        .sheet(item: $installingShortcut) { shortcut in
            if let url = shortcut.fileURL { ShortcutInstaller(url: url) }
        }
        .task(id: pickerItem) {
            guard let item = pickerItem else { return }
            isLoadingPhoto = true
            defer {
                isLoadingPhoto = false
                pickerItem = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                    let image = UIImage.decodedImage(data: data)
                else {
                    if !Task.isCancelled {
                        coordinator.toast = .failure(
                            "Couldn't read that image",
                            "Choose a photo saved on this device, or let it finish downloading from iCloud and try again."
                        )
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                coordinator.receiveExternalImage(image, origin: .imported)
            } catch {
                guard !Task.isCancelled else { return }
                coordinator.toast = .failure(
                    "Couldn't load photo", "Please try again once the photo is available on this device.")
            }
        }
    }

    private var choosePhoto: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            VStack(spacing: 12) {
                Image(systemName: "pip.enter").font(.system(size: 34, weight: .medium))
                Text("Keep an image in view").font(.title2.weight(.semibold))
                Text(
                    settings.oneTapFloat
                        ? "Choose a photo to float over other apps."
                        : "Choose a photo, crop it, then tap Float."
                )
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                HStack {
                    if isLoadingPhoto { ProgressView() }
                    Label(
                        isLoadingPhoto ? "Loading photo…" : "Choose Photo", systemImage: "photo.on.rectangle"
                    )
                    .font(.headline)
                }
                .padding(.horizontal, 24).padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(Color.codActionBackground, in: Capsule())
                Text("Only the photo you choose is shared with Cod.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose Photo")
        .accessibilityHint(
            settings.oneTapFloat
                ? "Floats the selected photo in Picture in Picture."
                : "Opens the selected photo in the crop editor."
        )
        .accessibilityIdentifier("choose-photo")
        .disabled(isLoadingPhoto || coordinator.isWorking)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Float straight from Photos", systemImage: "square.and.arrow.up")
                .font(.headline)
            Text("Add the ready-made Shortcut once. Then use Photos → Share → Float with Cod.")
                .font(.subheadline).foregroundStyle(.secondary)
            if FloatShortcut.shareImage.fileURL != nil {
                Button {
                    installingShortcut = .shareImage
                } label: {
                    Label("Add Float with Cod", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.codActionBackground).foregroundStyle(.white)
                .accessibilityIdentifier("install-share-shortcut")
                Text(
                    "Choose Shortcuts, then confirm Add Shortcut. The image input is already connected—no editing needed."
                )
                .font(.footnote).foregroundStyle(.secondary)
            } else {
                NavigationLink("Open setup instructions") { OneTapFloatGuide() }
            }
            Button("Already set up? Hide this tip") { settings.hasDismissedFloatSetupTip = true }
                .font(.footnote).frame(minHeight: 44)
                .accessibilityIdentifier("hide-float-setup")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var screenshotActions: some View {
        VStack(spacing: 0) {
            Button {
                Task { await coordinator.floatLatestScreenshot(minimalUI: true) }
            } label: {
                actionRow(
                    "Float Latest Screenshot",
                    detail: "Uses the newest saved screenshot · Photos access required", icon: "pip.enter")
            }
            Divider().padding(.leading, 52)
            Button {
                Task { await coordinator.captureLatestScreenshot() }
            } label: {
                actionRow(
                    "Crop Latest Screenshot", detail: "Select a region and choose an action", icon: "crop")
            }
            Divider().padding(.leading, 52)
            Button {
                coordinator.pasteFromClipboard()
            } label: {
                actionRow("Paste Image", detail: "Use an image you copied", icon: "doc.on.clipboard")
            }
        }
        .buttonStyle(.plain).disabled(coordinator.isWorking || isLoadingPhoto)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func actionRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var quickShare: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shared image ready to retry", systemImage: "photo").font(.headline)
            Text(
                settings.useFloatNotification
                    ? "Tap Cod's notification, or retry here. A newer share replaces this image."
                    : "This attempt didn't finish or has expired. Retry when you're ready; it won't restart on its own."
            )
            .font(.footnote).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack {
                    retryButton
                    removeShareButton
                }
                VStack(alignment: .leading) {
                    retryButton
                    removeShareButton
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var retryButton: some View {
        Button("Try Floating Again") { coordinator.receiveQuickShare(retry: true) }
            .buttonStyle(.borderedProminent).tint(.codActionBackground).foregroundStyle(.white)
            .disabled(coordinator.isWorking)
    }
    private var removeShareButton: some View {
        Button("Remove", role: .destructive) { coordinator.discardQuickShare() }
            .buttonStyle(.bordered).disabled(coordinator.isWorking)
    }

    /// Compatibility UI for existing user data, not a new-image inbox workflow.
    private var sharedImages: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Earlier shared images", systemImage: "tray").font(.headline)
            if let error = coordinator.sharedInboxError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Try loading earlier images again") { coordinator.refreshSharedImages() }
                    .frame(minHeight: 44)
            }
            ForEach(coordinator.sharedImages) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if let thumbnail = entry.thumbnail {
                            Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: 64, height: 64)
                                .accessibilityLabel("Shared image preview")
                        } else {
                            Label("Unreadable image", systemImage: "photo.badge.exclamationmark")
                        }
                        Spacer()
                        Button(role: .destructive) {
                            coordinator.removeSharedImage(entry)
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove this image from Cod's inbox")
                    }
                    HStack {
                        Button("Float") { coordinator.openSharedImage(entry, float: true) }.buttonStyle(
                            .borderedProminent
                        )
                        .tint(.codActionBackground).foregroundStyle(.white)
                        Button("Crop") { coordinator.openSharedImage(entry, float: false) }.buttonStyle(
                            .bordered)
                    }
                    .disabled(entry.thumbnail == nil || coordinator.isWorking)
                }
            }
            Text(
                "Kept from an earlier version. Remove them here; clearing history doesn't remove these copies."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var floatingStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pip.isActive || pip.status.isBusy {
                Label(
                    pip.isActive ? "Floating over other apps" : "Opening floating window…",
                    systemImage: "pip.fill"
                )
                .font(.headline)
                Text(
                    pip.isActive
                        ? "Switch to any app when you're ready. iOS controls the window's size and position."
                        : "Keep Cod open while iOS prepares Picture in Picture."
                )
                .font(.footnote).foregroundStyle(.secondary)
                Button("Stop Floating", role: .destructive) { pip.stop() }.buttonStyle(.bordered)
            }
            if !pins.isEmpty {
                Label("\(pins.pins.count) pinned inside Cod", systemImage: "pin.fill").font(.subheadline)
                Button("Clear Pins") { pins.removeAll() }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent images").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.snaps.prefix(12)) { snap in
                        Button {
                            coordinator.reopen(snap)
                        } label: {
                            SnapThumbnail(snap: snap).frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Open saved \(snap.origin.label.lowercased()), \(snap.dimensionLabel)")
                    }
                }
            }
        }
    }
}

/// Thumbnail loading is bounded by the store's cache.
struct SnapThumbnail: View {
    let snap: Snap
    @EnvironmentObject private var store: SnapStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(3) }
        }
        .task(id: snap.id) { image = store.thumbnail(for: snap) }
        .clipped()
    }
}
