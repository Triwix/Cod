import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SnapStore
    @EnvironmentObject private var pip: PiPPinController
    @State private var isEnablingNotifications = false

    var body: some View {
        NavigationStack {
            Form {
                activationSection
                shareSheetSection
                actionsSection
                recognitionSection
                historySection
                pinsSection
                savingSection
                feelSection
                #if COD_PERSONAL
                integrationsSection
                #endif
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Activation

    private var activationSection: some View {
        Section {
            Picker("When a capture arrives", selection: $settings.arrivalMode) {
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
            Text("Activation")
        } footer: {
            Text(settings.arrivalMode.detail)
        }
    }

    // MARK: - Actions

    private var shareSheetSection: some View {
        Section {
            Toggle("One tap float", isOn: Binding(
                get: { settings.oneTapFloat },
                set: { settings.setOneTapFloat($0) }
            ))
            #if !COD_PERSONAL
            Toggle("Tap notification to float", isOn: Binding(
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
                                    settings.sharePreferenceError = "Allow notifications for Cod in iPhone Settings to use this launch option."
                                }
                            } catch { settings.sharePreferenceError = error.localizedDescription }
                        }
                    }
                }
            ))
            .disabled(isEnablingNotifications)
            #endif
            NavigationLink {
                OneTapFloatGuide()
            } label: {
                Label("Set up fast floating", systemImage: "bolt")
            }
            if let error = settings.sharePreferenceError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Share Sheet")
        } footer: {
            #if COD_PERSONAL
            Text("Off by default: tapping Cod in the share sheet opens the cropping screen, where you can select a region and tap Float. Turn on to skip cropping and float the whole image immediately. This only changes Share → Cod, not your Shortcuts.")
            #elseif COD_FAST_SHARE
            Text("One tap float skips cropping. Turn it off to crop in the share sheet and tap Float.\n\nTap notification to float replaces automatic app opening with a notification you tap to launch Cod. It requires notification permission, and Focus or banner settings may delay it. If iOS won't deliver from the share extension, Cod shows an error and keeps the image for manual retry. Explicit Float Shortcuts aren't changed.")
            #else
            Text("One tap float skips cropping. Tap notification to float asks iOS to show a notification after sharing; tapping it opens Cod and floats that image. Enable notifications first. Availability from a share extension depends on iOS; if delivery fails, the image is kept for manual retry. Without notifications, open Cod manually after sharing. Explicit Float Shortcuts aren't changed.")
            #endif
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
            Text("Actions")
        } footer: {
            Text("Choose which actions appear after a crop, and in what order.")
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
                    Text(settings.ocrLanguages.isEmpty ? "Automatic" : settings.ocrLanguages.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Toggle("Language correction", isOn: $settings.ocrLanguageCorrection)
        } header: {
            Text("Text Recognition")
        } footer: {
            Text(settings.ocrAccuracy.detail)
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section {
            Picker("Keep", selection: $settings.historyLimit) {
                ForEach(HistoryLimit.allCases) { limit in
                    Text(limit.label).tag(limit)
                }
            }
            .onChange(of: settings.historyLimit) { _, newValue in
                store.trim(to: newValue)
            }

            HStack {
                Text("On disk")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: store.diskUsage, countStyle: .file))
                    .foregroundStyle(.secondary)
            }

            Button("Clear History", role: .destructive) { store.clear() }
                .disabled(store.snaps.isEmpty)
        } header: {
            Text("History")
        } footer: {
            Text("Cod keeps your recent crops so you can reopen, re-crop or re-pin them.")
        }
    }

    // MARK: - Pins

    private var pinsSection: some View {
        Section {
            Picker("Shadow", selection: $settings.pinShadow) {
                ForEach(PinShadow.allCases) { shadow in
                    Text(shadow.label).tag(shadow)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int(settings.pinOpacity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.pinOpacity, in: 0.25...1, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Corner radius")
                    Spacer()
                    Text("\(Int(settings.pinCornerRadius))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.pinCornerRadius, in: 0...24, step: 1)
            }

            Toggle("Keep other audio playing", isOn: $settings.keepOtherAudioPlaying)
            #if COD_PERSONAL
            Toggle("Return automatically after floating", isOn: $settings.returnAfterFloating)
            Toggle("Open without controls", isOn: $settings.hideFloatingControls)
            #endif
        } header: {
            Text("Pins")
        } footer: {
            #if COD_PERSONAL
            Text(pip.isSupported
                 ? "Floating hands the image to the system Picture in Picture window, which stays visible over other apps.\n\nShare → Cod opens cropping by default; enable “One tap float” above to float the whole image immediately. Neither mode needs a Shortcut. iOS requires Cod's window to be active to start PiP, so Cod appears briefly. “Return automatically” attempts to resume the identified share source, such as Photos. Immediate screenshot previews currently return to Home because their original app cannot be identified reliably. Arbitrary Shortcut-origin return is also unresolved.\n\n“Open without controls” is experimental and off by default. It hides buttons during appearance, but tapping before the window settles can close PiP. Leave it off for reliable early tapping; native controls fade on their own.\n\nAutomatic return and control hiding rely on undocumented system behaviour. They aren't suitable for an App Store build.\n\n“Keep other audio playing” avoids interrupting music. If floating stops after leaving Cod, try turning it off; background playback depends on iOS's audio-session handling."
                 : "Pins float above Cod. Floating over other apps needs Picture in Picture, which the Simulator doesn't provide — that part only works on a real device.")
            #else
            #if COD_FAST_SHARE
            Text("Share → Cod opens the app and starts Picture in Picture automatically, with no extra button when One tap float is on. Once the window appears, switch apps when you're ready. This build doesn't automatically return to the previous app.\n\nFast share launching is a compatibility workaround, not an officially supported extension behavior or App Store approval. Native controls determine PiP's size and movement; no private return or control-hiding methods are used.")
            #else
            Text("New images float immediately when opened in Cod. Share → Cod prepares the image automatically; opening Cod starts it with no Save, Done or Float buttons. This remaining manual-open step is a fallback, not a solved one-tap share launch. Once Picture in Picture appears, switch apps yourself.\n\nSystem controls determine PiP's size and movement. Shadow, opacity and corner radius only affect pins inside Cod.")
            #endif
            #endif
        }
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
            Toggle("Copy image when pinning", isOn: $settings.autoCopyOnCapture)
        } header: {
            Text("Saving")
        } footer: {
            Text("Dedicated albums require Full Photos Access. With Limited or Add-Only access, Cod saves to Recents instead.")
        }
    }

    // MARK: - Feel

    private var feelSection: some View {
        Section {
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
            Toggle("Detect blocks to tap", isOn: $settings.smartRegions)
            Toggle("Magnifier while dragging", isOn: $settings.showMagnifier)
        } header: {
            Text("Crop Surface")
        } footer: {
            Text("Block detection outlines paragraphs and cards so you can snap the selection onto one with a single tap.")
        }
    }

    // MARK: - Integrations

    #if COD_PERSONAL
    private var integrationsSection: some View {
        Section {
            HStack {
                Text("Imgur Client ID")
                Spacer()
                SecureField("Optional", text: $settings.imgurClientID)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Integrations")
        } footer: {
            Text("Register an application at imgur.com/oauth2/addclient to get a Client ID. Uploads are anonymous and always ask before they leave your device.")
        }
    }

    #endif

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                CapabilitiesView()
            } label: {
                Label("What Cod can and can't do", systemImage: "info.circle")
            }
            #if !COD_PERSONAL
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
            #endif
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(action.tint)
                            .frame(width: 30, height: 30)
                            .background(action.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.title).font(.body)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { settings.enabledActions.contains(action) },
                            set: { isOn in
                                if isOn {
                                    settings.enabledActions.insert(action)
                                } else {
                                    settings.enabledActions.remove(action)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .onMove { source, destination in
                    settings.actionOrder.move(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("Drag to reorder. The order here is the order they appear under a fresh crop.")
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
                Text("Vision tries the selected languages in order. Fewer languages means faster, more accurate recognition.")
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
                row("Multiple pins floating over Cod", true)
                row("One pin floating over every app (PiP)", pip.isSupported)
                row("OCR with language + accuracy control", true)
                row("QR and barcode scanning", true)
                row("Screenshot history, searchable by text", true)
                row("Dedicated Photos album", true)
                #if COD_PERSONAL
                row("Imgur upload", true)
                #endif
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
                Text("Cod uses Picture in Picture for one floating image; only one PiP window can be active at a time. New floating windows start while Cod is open. iOS controls the floating window's appearance and resizing. Cod can't automatically return to an arbitrary source screen using public APIs.")
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
