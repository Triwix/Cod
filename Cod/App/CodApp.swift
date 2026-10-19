import SwiftUI

@main
struct CodApp: App {
    @UIApplicationDelegateAdaptor(CodApplicationDelegate.self) private var applicationDelegate
    @StateObject private var settings = AppSettings.shared
    @StateObject private var store = SnapStore.shared
    @StateObject private var pins = PinManager.shared
    @StateObject private var pip = PiPPinController.shared
    @StateObject private var coordinator = CaptureCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                #if DEBUG && targetEnvironment(simulator)
                .modifier(SimulatorQATraits())
                #endif
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(pins)
                .environmentObject(pip)
                .environmentObject(coordinator)
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Deterministic layout tests without changing the host's appearance settings.
private struct SimulatorQATraits: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemSize
    func body(content: Content) -> some View {
        content
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text-ui-test") ? .accessibility5 : systemSize)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark-ui-test") ? .dark : nil)
            .task { requestTestGeometry() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                requestTestGeometry()
            }
    }

    private func requestTestGeometry() {
        guard ProcessInfo.processInfo.arguments.contains("--landscape-ui-test"),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
        // Public, own-scene geometry request for deterministic simulator QA;
        // no device rotation setting or production behavior is changed.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
            CodDiagnosticLog.record("Simulator layout request failed: \(error.localizedDescription)")
        }
    }
}
#endif
