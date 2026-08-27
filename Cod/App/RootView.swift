import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var pins: PinManager
    @EnvironmentObject private var settings: AppSettings

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var inbox = IntentInbox.shared
    @State private var selectedTab = 0
    @State private var wasBackgrounded = false

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
        .onChange(of: coordinator.pip.lostToBackgrounding) { _, lost in
            guard lost else { return }
            coordinator.pip.lostToBackgrounding = false
            coordinator.floatOnlyLaunch = false
            coordinator.toast = .failure(
                "Floating window closed",
                settings.keepOtherAudioPlaying
                    ? "iOS stopped it when Cod went to the background. Turn off “Keep other audio playing” in Settings → Pins to fix it."
                    : "iOS stopped it when Cod went to the background."
            )
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
            coordinator.present(image: image, origin: .screenshot)
        }
        .onChange(of: inbox.pendingFloatImage) { _, image in
            guard let image else { return }
            inbox.pendingFloatImage = nil
            coordinator.floatImmediately(image: image, minimalUI: true)
        }
        .onChange(of: inbox.wantsLatestScreenshot) { _, wants in
            guard wants else { return }
            inbox.wantsLatestScreenshot = false
            Task { await coordinator.captureLatestScreenshot() }
        }
        .onChange(of: inbox.wantsFloatLatest) { _, wants in
            guard wants else { return }
            inbox.wantsFloatLatest = false
            Task { await coordinator.floatLatestScreenshot(minimalUI: true) }
        }
        .task {
            // Cold launch from a Shortcut: the intent may have landed before
            // this view existed.
            if let image = inbox.pendingFloatImage {
                inbox.pendingFloatImage = nil
                coordinator.floatImmediately(image: image, minimalUI: true)
            } else if inbox.wantsFloatLatest {
                inbox.wantsFloatLatest = false
                await coordinator.floatLatestScreenshot(minimalUI: true)
            } else if let image = inbox.pendingImage {
                inbox.pendingImage = nil
                coordinator.present(image: image, origin: .screenshot)
            } else if inbox.wantsLatestScreenshot {
                inbox.wantsLatestScreenshot = false
                await coordinator.captureLatestScreenshot()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The one-tap float paths go straight from launch to PiP, so there
            // is no crop-surface dwell time to hide AVKit's cold start behind.
            // Warm it as soon as we're on screen.
            if phase == .active, settings.enabledActions.contains(.float) {
                coordinator.pip.prewarm()
            }
            // Coming back to Cod deliberately after a float means the user
            // wants the app, not the confirmation screen.
            if phase == .background {
                wasBackgrounded = true
            } else if phase == .active, wasBackgrounded {
                wasBackgrounded = false
                coordinator.floatOnlyLaunch = false
            }
            // Coming back to the app is the natural moment to notice that a
            // new screenshot has appeared since we were last open.
            guard phase == .active, settings.watchScreenshots else { return }
            guard coordinator.pending == nil, PhotoLibraryService.isAuthorized() else { return }
            Task { await coordinator.captureLatestScreenshot(force: false) }
        }
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
