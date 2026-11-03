import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct CodTimerActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<CodTimerAlarmMetadata>.self) { context in
            HStack {
                Label("Cod Timer", systemImage: "timer").font(.headline)
                Spacer()
                countdown(context.state).font(.title.monospacedDigit())
                Button(intent: StopCodTimerIntent(id: context.state.alarmID)) {
                    Image(systemName: "stop.fill")
                }.accessibilityLabel("Cancel timer")
            }
            .padding().foregroundStyle(.white).activityBackgroundTint(.black).activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Cod Timer", systemImage: "timer") }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopCodTimerIntent(id: context.state.alarmID)) {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                }
                DynamicIslandExpandedRegion(.bottom) { countdown(context.state).font(.largeTitle.monospacedDigit()) }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                countdown(context.state).monospacedDigit().frame(maxWidth: 60)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func countdown(_ state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let value):
            Text(timerInterval: value.startDate...max(value.startDate, value.fireDate), countsDown: true)
        case .paused:
            Text("Paused")
        case .alert:
            Text("Finished")
        @unknown default:
            Text("Timer")
        }
    }
}
