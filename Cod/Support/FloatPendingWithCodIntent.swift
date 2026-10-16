#if COD_LAUNCH_PROBE
import AppIntents
import Foundation

/// Diagnostic-only experiment. Public Button(intent:) is not evidence that
/// Share extensions are supported launch surfaces; verify actual execution.
struct FloatPendingWithCodIntent: AppIntent {
    static var title: LocalizedStringResource = "Float Pending Image With Cod"
    static var openAppWhenRun: Bool = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }
    @MainActor
    func perform() async throws -> some IntentResult {
        CodDiagnosticLog.record("launch-intent perform bundle=\(Bundle.main.bundleIdentifier ?? "unknown")")
        NotificationCenter.default.post(name: .codQuickFloatRequested, object: nil)
        return .result()
    }
}
#endif
