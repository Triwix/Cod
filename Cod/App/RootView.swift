import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var pip: PiPPinController
    @EnvironmentObject private var store: SnapStore

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = IntentInbox.shared
    @State private var selectedTab = 0
    @State private var wasBackgrounded = false
    @State private var quickShareTask: Task<Void, Never>?
    @State private var quickLaunchRequestID: UUID?
    @State private var quickLaunchIsNotification = false
    @State private var suppressUnrequestedShare = false
    @State private var documentImportTask: Task<Void, Never>?

    private var overlayContent: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Float", systemImage: "pip.enter") }
                    .tag(0)

                LibraryView()
                    .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                    .tag(1)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(2)
            }

            // The crop surface sits above the tabs.
            if let pending = coordinator.pending {
                SelectionView(
                    image: pending.image,
                    onCancel: { coordinator.dismissSelection() },
                    onAction: { action, image, rect in
                        coordinator.run(action, image: image, rect: rect, origin: pending.origin)
                    },
                    onReadText: { coordinator.openReadableImage($0) }
                )
                .id(pending.id)
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(1)
            }

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
    }

    private var inputContent: some View {
        overlayContent
        .onOpenURL { url in
            CodDiagnosticLog.record("app: received URL scheme=\(url.scheme ?? "none") host=\(url.host ?? "none")")

            if let id = QuickFloatLaunchRoute.configured?.requestID(in: url) {
                documentImportTask?.cancel()
                quickLaunchRequestID = id
                quickLaunchIsNotification = false
                suppressUnrequestedShare = true
                selectedTab = 0
                scheduleQuickShare()
                return
            }

            // A source app may explicitly open an image document in Cod.
            // This is distinct from selecting our Share extension: not every
            // image source offers a direct document-opening action.
            guard url.isFileURL else { return }
            quickShareTask?.cancel()
            quickLaunchRequestID = nil
            quickLaunchIsNotification = false
            suppressUnrequestedShare = true
            documentImportTask?.cancel()
            coordinator.prioritizeExplicitInput()
            let inputID = coordinator.explicitInputID
            documentImportTask = Task {
                do {
                    let content = try await VisualFileImport.open(url)
                    try Task.checkCancellation()
                    guard inputID == coordinator.explicitInputID else { return }
                    switch content {
                    case .image(let image): coordinator.receiveExternalImage(image)
                    case .video(let video): coordinator.route = .init(kind: .video(video))
                    case .pdf(let pdf): coordinator.route = .init(kind: .pdf(pdf))
                    }
                } catch {
                    guard !Task.isCancelled, inputID == coordinator.explicitInputID else { return }
                    if let message = ImportRecovery.message(for: error) {
                        coordinator.toast = .failure("Couldn't open file", message)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codQuickFloatRequested)) { _ in
            scheduleQuickShare()
        }
        .onChange(of: store.storageIssue) { _, issue in
            if let issue { coordinator.toast = .failure("Library needs attention", issue) }
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
        .onChange(of: coordinator.pip.restorationImage) { _, image in
            guard let image else { return }
            coordinator.pip.restorationImage = nil
            coordinator.restoreFloatingSelection(image)
        }
        .onChange(of: pip.restorationTool?.id) { _, id in
            guard id != nil, let session = pip.restorationTool else { return }
            pip.restorationTool = nil
            selectedTab = 0
            coordinator.floatOnlyLaunch = false
            coordinator.route = .init(kind: .tool(session))
        }
        .onChange(of: pip.restorationVideo?.id) { _, id in
            guard id != nil, let video = pip.restorationVideo else { return }
            pip.restorationVideo = nil
            selectedTab = 0
            coordinator.floatOnlyLaunch = false
            coordinator.route = .init(kind: .video(video))
        }
        .onChange(of: inbox.pendingReference?.id) { _, _ in receiveReference() }
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
            coordinator.restoreFloatingSelection(image, origin: .screenshot)
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
    }

    var body: some View {
        inputContent
        .task {
            CodDiagnosticLog.record("app: root ready build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown") phase=\(scenePhase)")
            coordinator.refreshSharedImages()
            coordinator.refreshQuickSharePreview()
            if let id = inbox.pendingQuickFloatRequestID {
                inbox.pendingQuickFloatRequestID = nil
                receiveNotificationRequest(id)
                return
            }
            // Cold launch from a Shortcut: the intent may have landed before
            // this view existed.
            if inbox.pendingReference != nil {
                receiveReference()
            } else if let image = inbox.pendingFloatImage {
                inbox.pendingFloatImage = nil
                coordinator.receiveFloatIntentImage(image)
            } else if inbox.wantsFloatLatest {
                coordinator.prioritizeExplicitInput()
                inbox.wantsFloatLatest = false
                await coordinator.floatLatestScreenshot(minimalUI: true)
            } else if let image = inbox.pendingImage {
                coordinator.prioritizeExplicitInput()
                inbox.pendingImage = nil
                coordinator.restoreFloatingSelection(image, origin: .screenshot)
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
            // The one-tap float paths go straight from launch to PiP, so there
            // is no crop-surface dwell time to hide AVKit's cold start behind.
            // Warm it as soon as we're on screen.
            if phase == .active, settings.enabledActions.contains(.float) {
                coordinator.pip.prewarm()
            }
            if phase == .active {
                coordinator.refreshSharedImages()
                coordinator.refreshQuickSharePreview()
                scheduleQuickShare()
            } else { quickShareTask?.cancel() }
            // Coming back to Cod deliberately after a float means the user
            // wants the app, not the confirmation screen.
            if phase == .background {
                pip.stopIdlePlayback()
                wasBackgrounded = true
                suppressUnrequestedShare = false
            } else if phase == .active, wasBackgrounded {
                wasBackgrounded = false
                if !coordinator.pip.status.isBusy {
                    coordinator.floatOnlyLaunch = false
                }
            }
            // Coming back to the app is the natural moment to notice that a
            // new screenshot has appeared since we were last open.
            guard phase == .active, settings.watchScreenshots,
                  !coordinator.floatOnlyLaunch, !coordinator.pip.status.isBusy else { return }
            guard coordinator.sharedImages.isEmpty, coordinator.quickSharePreview == nil else { return }
            // Don't cover a live tool, document picker or tool draft with an
            // unrelated screenshot offer when returning to Cod.
            guard coordinator.isFloatListVisible, coordinator.route == nil, !pip.isActive else { return }
            guard coordinator.pending == nil, PhotoLibraryService.isAuthorized() else { return }
            Task { await coordinator.captureLatestScreenshot(force: false) }
        }
    }

    private func receiveReference() {
        documentImportTask?.cancel()
        guard let input = inbox.pendingReference else { return }
        inbox.pendingReference = nil
        quickShareTask?.cancel()
        quickLaunchRequestID = nil
        quickLaunchIsNotification = false
        suppressUnrequestedShare = true
        coordinator.prioritizeExplicitInput()
        do {
            switch input.content {
            case .text(let text):
                let image = try FloatingText.render(text)
                coordinator.receiveFloatIntentImage(image)
            case .pdf(let data, let page):
                let reference = try PDFReference(data: data)
                let image = try reference.image(pageIndex: page - 1)
                coordinator.receiveFloatIntentImage(image)
            case .saved(let id):
                coordinator.floatSavedReference(id)
            case .animated(let data):
                Task {
                    do {
                        let video = try await AnimatedImageImport.video(data)
                        coordinator.route = .init(kind: .video(video, autoFloat: true))
                    } catch { coordinator.toast = .failure("Couldn't open animation", error.localizedDescription) }
                }
            }
        } catch { coordinator.toast = .failure("Couldn't float reference", error.localizedDescription) }
    }

    private func scheduleQuickShare() {
        quickShareTask?.cancel()
        quickShareTask = Task { @MainActor in
            // Give explicit document/Shortcut input precedence over a queued
            // share. This wait isn't a PiP retry or an automatic app launch.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, scenePhase == .active else { return }
            let id = quickLaunchRequestID
            // A deliberate manual open is also the fallback when banners
            // are disabled/hidden. A notification preference mustn't block
            // receipt of its prepared image. Explicit other inputs still win.
            guard id != nil || !suppressUnrequestedShare else { return }
            if coordinator.receiveQuickShare(expectedID: id, fromNotification: quickLaunchIsNotification) {
                quickLaunchRequestID = nil
                quickLaunchIsNotification = false
            }
        }
    }

    private func receiveNotificationRequest(_ id: UUID) {
        documentImportTask?.cancel()
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
