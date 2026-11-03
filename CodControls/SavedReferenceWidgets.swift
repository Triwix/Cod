import AppIntents
import SwiftUI
import WidgetKit

struct SavedReferenceControlConfiguration: ControlConfigurationIntent {
  static var title: LocalizedStringResource = "Choose a Cod Reference"
  @Parameter(title: "Reference") var reference: CodSavedReferenceEntity?
}

struct SavedReferenceControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    AppIntentControlConfiguration(
      kind: "com.josh.cod.saved-reference", intent: SavedReferenceControlConfiguration.self
    ) { configuration in
      ControlWidgetButton(
        action: FloatSavedReferenceIntent(target: configuration.reference ?? .unconfigured)
      ) {
        Label(configuration.reference?.name ?? "Choose a reference", systemImage: "pip.enter")
      }
    }
    .displayName("Float Saved Reference")
    .description(
      "Choose a saved card, preset or Library favorite. Opens Cod; requires an unlocked iPhone.")
  }
}

struct SavedReferenceWidgetConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Choose a Cod Reference"
  @Parameter(title: "Reference") var reference: CodSavedReferenceEntity?
}

struct SavedReferenceEntry: TimelineEntry {
  var date: Date
  var reference: CodSavedReferenceEntity?
}

struct SavedReferenceProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> SavedReferenceEntry { .init(date: .now, reference: nil) }
  func snapshot(for configuration: SavedReferenceWidgetConfiguration, in context: Context) async
    -> SavedReferenceEntry
  {
    .init(date: .now, reference: configuration.reference)
  }
  func timeline(for configuration: SavedReferenceWidgetConfiguration, in context: Context) async
    -> Timeline<SavedReferenceEntry>
  {
    let current = try? await CodSavedReferenceQuery().entities(
      for: configuration.reference.map { [$0.id] } ?? []
    ).first
    return Timeline(entries: [.init(date: .now, reference: current)], policy: .never)
  }
}

struct SavedReferenceWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: "com.josh.cod.saved-reference-widget", intent: SavedReferenceWidgetConfiguration.self,
      provider: SavedReferenceProvider()
    ) { entry in
      Button(intent: FloatSavedReferenceIntent(target: entry.reference ?? .unconfigured)) {
        VStack(alignment: .leading, spacing: 8) {
          Label("Float with Cod", systemImage: "pip.enter").font(.headline)
          Text(entry.reference?.name ?? "Choose a saved reference").font(.body).lineLimit(3)
          Text(entry.reference?.detail ?? "Edit this widget to choose a card or favorite.").font(
            .caption
          ).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .containerBackground(.fill.tertiary, for: .widget)
      .privacySensitive()
    }
    .configurationDisplayName("Float Saved Reference")
    .description(
      "Open a saved card or favorite in Cod's floating window. Content isn't shown in the widget."
    )
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
