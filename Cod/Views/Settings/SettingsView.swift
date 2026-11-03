import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @StateObject private var savedReferences = SavedReferenceStore.shared
    @State private var isEnablingNotifications = false
    @State private var confirmClearHistory = false
    @State private var pendingHistoryLimit: HistoryLimit?

    var body: some View {
        NavigationStack {
            Form {
                shareSheetSection
                playbackSection
                activationSection
                actionsSection
                recognitionSection
                historySection
                savingSection
                feelSection
                aboutSection
            }
            .codFormStyle()
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear Library?", isPresented: $confirmClearHistory, titleVisibility: .visible
            ) {
                if store.historyCount > 0 {
                    Button("Clear Recent History (\(store.historyCount))", role: .destructive) { store.clearHistory() }
                }
                Button("Delete Everything, Including Favorites", role: .destructive) {
                    do { try savedReferences.clear(); store.clear() }
                    catch { coordinator.toast = .failure("Couldn't clear saved cards", error.localizedDescription) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Clear Recent History keeps favorites and saved cards. Delete Everything removes captures, favorites, saved cards and presets. Originals in Photos or Files and pending shares aren't deleted."
                )
            }
            .confirmationDialog(
                "Remove older saved images?",
                isPresented: Binding(
                    get: { pendingHistoryLimit != nil },
                    set: { if !$0 { pendingHistoryLimit = nil } }
                ), titleVisibility: .visible
            ) {
                if let limit = pendingHistoryLimit {
                    Button(
                        "Remove \(HistoryRetentionPolicy.removalCount(total: store.historyCount, limit: limit)) Images",
                        role: .destructive
                    ) {
                        applyHistoryLimit(limit)
                        pendingHistoryLimit = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingHistoryLimit = nil }
            } message: {
                Text(
                    "Reducing the history limit removes older images saved in Cod. Choosing Off removes all saved history. Favorites, Photos and pending shares aren't removed."
                )
            }
        }
    }

    // MARK: - Activation

    private var activationSection: some View {
        Section {
            Picker("When offering a new screenshot", selection: $settings.arrivalMode) {
                ForEach(ArrivalMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            if settings.arrivalMode == .instant {
                Picker("Instant action", selection: $settings.instantAction) {
                    ForEach(SnapAction.availableCases) { action in
                        Label(action.title, systemImage: action.systemImage).tag(action)
                    }
                }
            }

            Toggle("Offer new screenshots on launch", isOn: $settings.watchScreenshots)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Capture delay")
                    Spacer()
                    Text(settings.captureDelay == 0 ? "None" : String(format: "%.1fs", settings.captureDelay))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.captureDelay, in: 0...2, step: 0.1)
            }
        } header: {
            Text("Screenshot editor")
        } footer: {
            Text(
                "These options apply to automatic screenshot offers. Explicit Float and Crop buttons and Shortcuts always do the action you choose. \(settings.arrivalMode.detail)"
            )
        }
    }

    // MARK: - Actions

    private var shareSheetSection: some View {
        Group {
            Section {
                NavigationLink("Quick introduction") { FloatingIntroductionView() }
                    .accessibilityIdentifier("reopen-introduction")
                NavigationLink {
                    OneTapFloatGuide()
                } label: {
                    CodRowLabel("Set up fast floating", systemImage: "bolt")
                }
                Toggle(
                    "One tap float",
                    isOn: Binding(
                        get: { settings.oneTapFloat },
                        set: { settings.setOneTapFloat($0) }
                    ))
            } header: {
                Text("Floating")
            } footer: {
                Text(
                    "Skip cropping for pasted and shared images. Explicit Float and Crop actions always follow your choice."
                )
            }
            Section {
                Toggle(
                    "Tap notification to float",
                    isOn: Binding(
                        get: { settings.useFloatNotification },
                        set: { enabled in
                            if !enabled {
                                settings.setUseFloatNotification(false)
                                ShareFloatNotifications().remove()
                            } else {
                                isEnablingNotifications = true
                                Task { @MainActor in
                                    defer { isEnablingNotifications = false }
                                    do {
                                        if try await ShareFloatNotifications().requestPermission() {
                                            settings.setUseFloatNotification(true)
                                        } else {
                                            settings.sharePreferenceError =
                                                "Allow notifications for Cod in iPhone Settings to use this launch option."
                                        }
                                    } catch { settings.sharePreferenceError = error.localizedDescription }
                                }
                            }
                        }
                    )
                )
                .disabled(isEnablingNotifications)
                if let error = settings.sharePreferenceError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                DisclosureGroup("Why sharing needs another step") {
                    Text("The Cod app icon runs a Share extension. iOS doesn't let that extension launch Cod directly; the full app must open to start PiP. Tap its notification or open Cod manually.")
                    Text("The Float with Cod Share Shortcut opens Cod directly and avoids the notification tap. Focus, summaries and banner settings may hide or delay a notification.")
                    Text("One tap float skips cropping; it doesn't open Cod automatically. Explicit Float Shortcuts always float their supplied image. Photo and screenshot buttons always follow the action you choose.")
                }
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("share-route-explanation")
            } header: {
                Text("Share → Cod app icon")
            } footer: {
                Text(
                    "Share → Cod, then tap its notification. You can also open Cod manually. The Share Shortcut is the faster route."
                )
            }
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle("Keep other audio playing", isOn: $settings.keepOtherAudioPlaying)
        } header: {
            Text("Picture in Picture")
        } footer: {
            Text(
                    "After PiP starts, switch apps yourself. iOS controls the window. If PiP stops when you leave Cod, try turning this off."
            )
        }
    }

    private var actionsSection: some View {
        Section {
            NavigationLink {
                ActionOrderView()
            } label: {
                HStack {
                    Text("Action bar")
                    Spacer()
                    Text("\(settings.visibleActions.count) shown")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("In-app actions")
        } footer: {
            Text(
                "Choose actions for Cod's own crop editor. The share-sheet crop screen only offers Float.")
        }
    }

    // MARK: - Recognition

    private var recognitionSection: some View {
        Section {
            Picker("Accuracy", selection: $settings.ocrAccuracy) {
                ForEach(OCRAccuracy.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)

            NavigationLink {
                OCRLanguageView()
            } label: {
                HStack {
                    Text("Languages")
                    Spacer()
                    Text(
                        settings.ocrLanguages.isEmpty
                            ? "Automatic" : settings.ocrLanguages.joined(separator: ", ")
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Toggle("Language correction", isOn: $settings.ocrLanguageCorrection)
        } header: {
            Text("Text recognition")
        } footer: {
            Text(settings.ocrAccuracy.detail)
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            Picker(
                "Keep",
                selection: Binding(
                    get: { settings.historyLimit },
                    set: { limit in
                        if HistoryRetentionPolicy.removalCount(total: store.historyCount, limit: limit) > 0 {
                            pendingHistoryLimit = limit
                        } else {
                            applyHistoryLimit(limit)
                        }
                    }
                )
            ) {
                ForEach(HistoryLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .accessibilityIdentifier("history-limit")

            HStack {
                Text("History on disk")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: store.diskUsage, countStyle: .file))
                    .foregroundStyle(.secondary)
            }

            Button("Clear Library…", role: .destructive) { confirmClearHistory = true }
                .disabled(store.snaps.isEmpty && savedReferences.items.isEmpty)
                .accessibilityIdentifier("clear-history")
        } header: {
            Text("History")
        } footer: {
            Text(
                "Saved media stay on this device and may be included in backups. Favorites, named cards and presets stay saved when History is Off or its limit is reduced. Clear Library lets you clear recent history or delete everything, including those saves, after confirmation. Photos copies and pending shares aren't removed."
            )
        }
    }

    private func applyHistoryLimit(_ limit: HistoryLimit) {
        settings.historyLimit = limit
        store.trim(to: limit)
    }

    // MARK: - Saving

    private var savingSection: some View {
        Section {
            Toggle("Save to a dedicated album", isOn: $settings.saveToDedicatedAlbum)
            if settings.saveToDedicatedAlbum {
                HStack {
                    Text("Album name")
                    Spacer()
                    TextField("Cod", text: $settings.albumName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Saving")
        } footer: {
            Text(
                "Dedicated albums require Full Photos Access. With Limited or Add-Only access, Cod saves to Recents instead."
            )
        }
    }

    // MARK: - Feel

    private var feelSection: some View {
        Section {
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
            Toggle("Detect blocks to tap", isOn: $settings.smartRegions)
            Toggle("Magnifier while dragging", isOn: $settings.showMagnifier)
        } header: {
            Text("Crop surface")
        } footer: {
            Text(
                "Block detection outlines paragraphs and cards so you can snap the selection onto one with a single tap."
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                CapabilitiesView()
            } label: {
                CodRowLabel("What Cod can and can't do", systemImage: "info.circle")
            }
            NavigationLink {
                PrivacyView()
            } label: {
                CodRowLabel("Privacy", systemImage: "hand.raised")
            }
            LabeledContent(
                "Version",
                value:
                    "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))"
            )
        }
    }
}

// MARK: - Action ordering

struct ActionOrderView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        List {
            Section {
                ForEach(settings.actionOrder) { action in
                    HStack(spacing: 12) {
                        Image(systemName: action.systemImage)
                            .font(.body).foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(action.title).font(.body)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { settings.enabledActions.contains(action) },
                                set: { isOn in
                                    if isOn {
                                        settings.enabledActions.insert(action)
                                    } else {
                                        settings.enabledActions.remove(action)
                                    }
                                }
                            )
                        )
                        .labelsHidden()
                        .accessibilityLabel("Show \(action.title) in action bar")
                    }
                }
                .onMove { source, destination in
                    settings.actionOrder.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("These actions appear in Cod's crop editor, not in the share sheet. Drag to reorder.")
            }

            Section {
                Button("Reset to Defaults") { settings.resetActions() }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Action Bar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - OCR languages

struct OCRLanguageView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var available: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(available, id: \.self) { code in
                    Button {
                        toggle(code)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(displayName(for: code))
                                Text(code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.ocrLanguages.contains(code) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(
                    "Vision tries the selected languages in order. Fewer languages means faster, more accurate recognition."
                )
            }
        }
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard available.isEmpty else { return }
            available = Recognizer.supportedLanguages
        }
    }

    private func toggle(_ code: String) {
        if let index = settings.ocrLanguages.firstIndex(of: code) {
            // Keep at least one language selected.
            guard settings.ocrLanguages.count > 1 else { return }
            settings.ocrLanguages.remove(at: index)
        } else {
            settings.ocrLanguages.append(code)
        }
        Haptics.selectionChanged()
    }

    private func displayName(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - Capabilities

struct CapabilitiesView: View {
    @EnvironmentObject private var pip: PiPPinController

    var body: some View {
        List {
            Section("Works") {
                row("Crop any region of a screenshot", true)
                row("Frozen image while you select", true)
                row("Picture in Picture over other apps", pip.isSupported)
                row("OCR with language + accuracy control", true)
                row("QR and barcode scanning", true)
                row("Screenshot history, searchable by text", true)
                row("Dedicated Photos album", true)
                row("Save shared images to Cod", true)
                row("One-gesture capture via Back Tap + Shortcuts", true)
            }

            Section("Not possible without a jailbreak") {
                row("Draw a crop box directly over another app", false)
                row("Freeze another app's live UI", false)
                row("Replace the volume-up + side button gesture", false)
                row("Silently intercept every screenshot", false)
                row("Several independent overlays over other apps", false)
            }

            Section {
                Text(
                    "Cod uses Picture in Picture for one floating image; only one PiP window can be active at a time. New floating windows start while Cod is open. iOS controls the floating window's appearance and resizing. Cod can't automatically return to an arbitrary source screen using public APIs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Capabilities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ available: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? .green : .secondary)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
