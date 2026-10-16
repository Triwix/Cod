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
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(pins)
                .environmentObject(pip)
                .environmentObject(coordinator)
        }
    }
}
