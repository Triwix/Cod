import SwiftUI

struct TimerDurationWheels: View {
    @Binding var seconds: Int
    private var duration: TimerDuration { .init(seconds) }

    var body: some View {
        HStack(spacing: 0) {
            wheel("Hours", identifier: "timer-hours", range: 0...23,
                  selection: Binding(get: { duration.hours }, set: { seconds = duration.changing(hours: $0).totalSeconds }))
            wheel("Minutes", identifier: "timer-minutes", range: 0...59,
                  selection: Binding(get: { duration.minutes }, set: { seconds = duration.changing(minutes: $0).totalSeconds }))
            wheel("Seconds", identifier: "timer-seconds", range: 0...59,
                  selection: Binding(get: { duration.seconds }, set: { seconds = duration.changing(seconds: $0).totalSeconds }))
        }
        .frame(height: 170)
    }

    private func wheel(_ title: String, identifier: String, range: ClosedRange<Int>, selection: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(range, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden()
            .accessibilityIdentifier(identifier)
            .frame(maxWidth: .infinity).clipped()
        }
    }
}
