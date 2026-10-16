import AppIntents
import SwiftUI
import WidgetKit

@main
struct CodControls: WidgetBundle {
    var body: some Widget {
        FloatLatestScreenshotControl()
    }
}

struct FloatLatestScreenshotControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.josh.cod.float-latest-screenshot") {
            ControlWidgetButton(action: FloatControlIntent(target: .latestScreenshot)) {
                Label("Float Screenshot", systemImage: "pip.enter")
            }
        }
        .displayName("Float Latest Screenshot")
        .description("Open Cod and float your latest saved screenshot. Requires Photos access and an unlocked iPhone.")
    }
}
