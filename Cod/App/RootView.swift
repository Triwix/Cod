import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pins: PinManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var pip: PiPPinController

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = IntentInbox.shared
    @State private var selectedTab = 0
    @State private var wasBackgrounded = false
    @State private var sharedFloatInFlight = false
    @State private var quickShareTask: Task<Void, Never>?
    @State private var quickLaunchRequestID: UUID?
    @State private var quickLaunchIsNotification = false
    @State private var suppressUnrequestedShare = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Capture", systemImage: "viewfinder") }
                    .tag(0)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                    .tag(1)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(2)
            }

            // The crop surface sits above the tabs but below the pins, so a
            // snippet you just pinned floats over the screenshot you're still
            // cropping — exactly the Snapper behaviour.
            if let pending = coordinator.pending {
                SelectionView(
                    image: pending.image,
                    onCancel: { coordinator.dismissSelection() },
                    onAction: { action, image, rect in
                        coordinator.run(action, image: image, rect: rect, origin: pending.origin)
                    }
                )
                .id(pending.id)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(1)
            }

            PinOverlay(manager: pins) { action, pin in
                coordinator.run(pinAction: action, pin: pin)
            }
            .zIndex(2)

            // Launched purely to float: keep the app out of the way.
            if coordinator.floatOnlyLaunch {
                FloatingLaunchView {
                    withAnimation(.easeOut(duration: 0.2)) { coordinator.floatOnlyLaunch = false }
                }
                .transition(.opacity)
                .zIndex(4)
            }

            if coordinator.isWorking {
                workingIndicator.zIndex(3)
            }
        }
        .toast($coordinator.toast)
        .onOpenURL { url in
            CodDiagnosticLog.record("app: received URL scheme=\(url.scheme ?? "none") host=\(url.host ?? "none")")
            #if DEBUG && COD_PERSONAL
            // Controlled browser-to-app return test, without image transfer,
            // clipboard access, PiP or a guessed app destination.
            if url.scheme == "cod", url.host == "return-probe" {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard UIApplication.shared.applicationState == .active else { return }
                    SourceAppReturn.shared.capture()
                    let requested = await SourceAppReturn.shared.returnToSource()
                    CodDiagnosticLog.record("URL Back-to-only probe requested=\(requested); PiP not tested")
                }
                return
            }
            #endif
            #if COD_PERSONAL
            if ShareFloatHandoff.matches(url) {
                guard let payload = ShareFloatHandoff.takePayload() else {
                    coordinator.floatOnlyLaunch = false
                    coordinator.toast = .failure(
                        "Couldn't receive image",
                        "The Share sheet opened Cod, but its image handoff was missing."
                    )
                    return
                }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--return-probe") {
                    SourceAppReturn.shared.capture(sourceBundleIdentifier: payload.sourceBundleIdentifier)
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        let accepted = await SourceAppReturn.shared.returnToSource()
                        CodDiagnosticLog.record("simulator return-only probe accepted=\(accepted); PiP not tested")
                    }
                    return
                }
                #endif
                sharedFloatInFlight = true
                coordinator.floatImmediately(
                    image: payload.image,
                    origin: .shared,
                    minimalUI: true,
                    reusePreparedPlayback: false,
                    sourceBundleIdentifier: payload.sourceBundleIdentifier
                )
                return
            }
            #endif

            #if !COD_PERSONAL
            if let id = QuickFloatLaunchRoute.configured?.requestID(in: url) {
                quickLaunchRequestID = id
                quickLaunchIsNotification = false
                suppressUnrequestedShare = true
                selectedTab = 0
                scheduleQuickShare()
                return
            }
            #endif

            // A source app may explicitly open an image document in Cod.
            // This is distinct from selecting our Share extension: not every
            // image source offers a direct document-opening action.
            guard url.isFileURL else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            quickShareTask?.cancel()
            quickLaunchRequestID = nil
            quickLaunchIsNotification = false
            coordinator.prioritizeExplicitInput()
            guard let image = UIImage.decodedImage(at: url) else {
                coordinator.toast = .failure("Couldn't open image")
                return
            }
            #if COD_PERSONAL
            coordinator.present(image: image, origin: .shared)
            #else
            coordinator.receiveExternalImage(image)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .codQuickFloatRequested)) { _ in
            scheduleQuickShare()
        }
        .onChange(of: inbox.pendingQuickFloatRequestID) { _, id in
            guard let id else { return }
            inbox.pendingQuickFloatRequestID = nil
            receiveNotificationRequest(id)
        }
        .onChange(of: coordinator.isWorking) { _, working in
            if !working, quickLaunchRequestID != nil { scheduleQuickShare() }
        }
        .onChange(of: pip.status) { _, status in
            if !status.isBusy, quickLaunchRequestID != nil { scheduleQuickShare() }
        }
        .onChange(of: coordinator.pip.lostToBackgrounding) { _, lost in
            guard lost else { return }
            coordinator.pip.lostToBackgrounding = false
            coordinator.floatOnlyLaunch = false
            coordinator.toast = .failure(
                "Floating window closed",
                settings.keepOtherAudioPlaying
                    ? "The window closed soon after Cod moved to the background. Try floating again. If it keeps happening, try turning off “Keep other audio playing” in Settings → Pins."
                    : "The window closed soon after Cod moved to the background. Try floating again."
            )
        }
        .onChange(of: coordinator.pip.restorationImage) { _, image in
            guard let image else { return }
            coordinator.pip.restorationImage = nil
            sharedFloatInFlight = false
            coordinator.restoreFloatingSelection(image)
        }
        .sheet(item: $coordinator.route) { route in
            RouteView(route: route)
                .environmentObject(coordinator)
                .environmentObject(settings)
        }
        // A Shortcut can hand us an image directly (Take Screenshot → Crop With
        // Cod), or just ask for the newest screenshot.
        .onChange(of: inbox.pendingImage) { _, image in
            guard let image else { return }
            inbox.pendingImage = nil
            coordinator.prioritizeExplicitInput()
            coordinator.present(image: image, origin: .screenshot)
        }
        .onChange(of: inbox.pendingFloatImage) { _, image in
            guard let image else { return }
            inbox.pendingFloatImage = nil
            coordinator.receiveFloatIntentImage(image)
        }
        .onChange(of: inbox.wantsLatestScreenshot) { _, wants in
            guard wants else { return }
            inbox.wantsLatestScreenshot = false
            coordinator.prioritizeExplicitInput()
            Task { await coordinator.captureLatestScreenshot() }
        }
        .onChange(of: inbox.wantsFloatLatest) { _, wants in
            guard wants else { return }
            inbox.wantsFloatLatest = false
            coordinator.prioritizeExplicitInput()
            Task { await coordinator.floatLatestScreenshot(minimalUI: true) }
        }
        .task {
            CodDiagnosticLog.record("app: root ready build=fast-share-20261015 phase=\(scenePhase)")
            #if COD_PERSONAL
            CodDiagnosticLog.record("app: private last-app return available=\(UIApplication.shared.responds(to: NSSelectorFromString("suspendReturningToLastApp:")))")
            #endif
            #if DEBUG && COD_PERSONAL
            if ProcessInfo.processInfo.arguments.contains("--return-context-probe") {
                SourceAppReturn.shared.startNavigationDiagnostics()
            }
            if ProcessInfo.processInfo.arguments.contains("--foreground-identity-probe") {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                ShareSourceContext.probeForegroundIdentifier { message in
                    CodDiagnosticLog.record(message)
                    print("[CodReturnProbe] \(message)")
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--navigation-probe") {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let source = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--return-source=") })
                    .map { String($0.dropFirst("--return-source=".count)) }
                SourceAppReturn.shared.capture(sourceBundleIdentifier: source)
                if source != nil {
                    let accepted = await SourceAppReturn.shared.returnToSource()
                    CodDiagnosticLog.record("source-only probe requested=\(accepted); PiP not tested")
                }
                return
            }
            #endif
            #if !COD_PERSONAL
            coordinator.refreshSharedImages()
            coordinator.refreshQuickSharePreview()
            #endif
            if let id = inbox.pendingQuickFloatRequestID {
                inbox.pendingQuickFloatRequestID = nil
                receiveNotificationRequest(id)
                return
            }
            // Cold launch from a Shortcut: the intent may have landed before
            // this view existed.
            if let image = inbox.pendingFloatImage {
                inbox.pendingFloatImage = nil
                coordinator.receiveFloatIntentImage(image)
            } else if inbox.wantsFloatLatest {
                coordinator.prioritizeExplicitInput()
                inbox.wantsFloatLatest = false
                await coordinator.floatLatestScreenshot(minimalUI: true)
            } else if let image = inbox.pendingImage {
                coordinator.prioritizeExplicitInput()
                inbox.pendingImage = nil
                coordinator.present(image: image, origin: .screenshot)
            } else if inbox.wantsLatestScreenshot {
                coordinator.prioritizeExplicitInput()
                inbox.wantsLatestScreenshot = false
                await coordinator.captureLatestScreenshot()
            } else {
                scheduleQuickShare()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            CodDiagnosticLog.record("app: scene phase=\(phase)")
            #if DEBUG && COD_PERSONAL
            SourceAppReturn.shared.inspectNavigationContext(reason: "scene \(phase)")
            #endif
            // The one-tap float paths go straight from launch to PiP, so there
            // is no crop-surface dwell time to hide AVKit's cold start behind.
            // Warm it as soon as we're on screen.
            if phase == .active, settings.enabledActions.contains(.float) {
                coordinator.pip.prewarm()
            }
            #if DEBUG && COD_PERSONAL && targetEnvironment(simulator)
            if phase == .active, ProcessInfo.processInfo.arguments.contains("--navigation-probe") {
                SourceAppReturn.shared.capture()
            }
            #endif
            #if !COD_PERSONAL
            if phase == .active {
                coordinator.refreshSharedImages()
                coordinator.refreshQuickSharePreview()
                scheduleQuickShare()
            } else { quickShareTask?.cancel() }
            #endif
            // Coming back to Cod deliberately after a float means the user
            // wants the app, not the confirmation screen.
            if phase == .background {
                wasBackgrounded = true
                sharedFloatInFlight = false
                suppressUnrequestedShare = false
            } else if phase == .active, wasBackgrounded {
                wasBackgrounded = false
                if !sharedFloatInFlight, !coordinator.pip.status.isBusy {
                    coordinator.floatOnlyLaunch = false
                }
            }
            // Coming back to the app is the natural moment to notice that a
            // new screenshot has appeared since we were last open.
            guard phase == .active, settings.watchScreenshots,
                  !coordinator.floatOnlyLaunch, !coordinator.pip.status.isBusy else { return }
            #if !COD_PERSONAL
            guard coordinator.sharedImages.isEmpty, coordinator.quickSharePreview == nil else { return }
            #endif
            guard coordinator.pending == nil, PhotoLibraryService.isAuthorized() else { return }
            Task { await coordinator.captureLatestScreenshot(force: false) }
        }
    }

    private func scheduleQuickShare() {
        #if !COD_PERSONAL
        quickShareTask?.cancel()
        quickShareTask = Task { @MainActor in
            // Give explicit document/Shortcut input precedence over a queued
            // share. This wait isn't a PiP retry or an automatic app launch.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, scenePhase == .active else { return }
            let id = quickLaunchRequestID
            guard id != nil || (!settings.useFloatNotification && !suppressUnrequestedShare) else { return }
            if coordinator.receiveQuickShare(expectedID: id, fromNotification: quickLaunchIsNotification) {
                quickLaunchRequestID = nil
                quickLaunchIsNotification = false
            }
        }
        #endif
    }

    private func receiveNotificationRequest(_ id: UUID) {
        quickLaunchRequestID = id
        quickLaunchIsNotification = true
        suppressUnrequestedShare = true
        selectedTab = 0
        scheduleQuickShare()
    }

    private var workingIndicator: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(radius: 12)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}
