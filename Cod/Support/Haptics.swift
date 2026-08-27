import UIKit

/// Thin wrapper so every call site can stay one line and respect the setting.
enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()

    private static var enabled: Bool { AppSettings.shared.hapticsEnabled }

    static func prepare() {
        guard enabled else { return }
        selection.prepare()
        impactLight.prepare()
    }

    static func selectionChanged() {
        guard enabled else { return }
        selection.selectionChanged()
    }

    static func tick() {
        guard enabled else { return }
        impactLight.impactOccurred(intensity: 0.6)
    }

    static func snap() {
        guard enabled else { return }
        impactRigid.impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }
}
