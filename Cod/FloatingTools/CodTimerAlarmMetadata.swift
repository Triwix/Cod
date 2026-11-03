import AlarmKit
import AppIntents

/// Shared by the app and its AlarmKit countdown presentation.
@available(iOS 26.0, *)
struct CodTimerAlarmMetadata: AlarmMetadata {}

/// LiveActivityIntent executes in the app process, so its type must be a
/// member of BOTH targets, not just the widget that displays the button.
@available(iOS 26.0, *)
struct StopCodTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Cod Timer"
    @Parameter(title: "Alarm") var alarmID: String
    init() {}
    init(id: UUID) { alarmID = id.uuidString }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.cancel(id: id) }
        return .result()
    }
}
