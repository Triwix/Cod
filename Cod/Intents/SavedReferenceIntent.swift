import AppIntents
import Foundation

struct CodSavedReferenceEntity: AppEntity {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Saved Cod reference")
  static var defaultQuery = CodSavedReferenceQuery()
  var id: UUID
  var name: String
  var detail: String
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)", subtitle: "\(detail)", image: .init(systemName: "pip.enter"))
  }
  init(_ value: SavedReferenceSummary) {
    id = value.id
    name = value.name
    detail = value.detail
  }
  static var unconfigured: Self {
    .init(
      .init(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Choose a reference",
        detail: "Configure this control"))
  }
}

struct CodSavedReferenceQuery: EntityStringQuery {
  func entities(for identifiers: [UUID]) async throws -> [CodSavedReferenceEntity] {
    let all = try SavedReferenceCatalog.entries()
    return identifiers.compactMap { id in
      all.first(where: { $0.id == id }).map(CodSavedReferenceEntity.init)
    }
  }
  func suggestedEntities() async throws -> [CodSavedReferenceEntity] {
    try SavedReferenceCatalog.entries().map(CodSavedReferenceEntity.init)
  }
  func entities(matching string: String) async throws -> [CodSavedReferenceEntity] {
    try SavedReferenceCatalog.entries().filter { $0.name.localizedCaseInsensitiveContains(string) }
      .map(CodSavedReferenceEntity.init)
  }
}

/// WidgetKit routes this authenticated OpenIntent into the containing app.
struct FloatSavedReferenceIntent: OpenIntent {
  static var title: LocalizedStringResource = "Float Saved Reference"
  static var description = IntentDescription(
    "Open Cod and float a saved card, preset or Library favorite.")
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  @Parameter(title: "Reference") var target: CodSavedReferenceEntity
  static var parameterSummary: some ParameterSummary { Summary("Float \(\.$target) with Cod") }
  init() {}
  init(target: CodSavedReferenceEntity) { self.target = target }
  @MainActor func perform() async throws -> some IntentResult {
    #if !COD_CONTROLS_EXTENSION
      IntentInbox.shared.deliverReference(.saved(target.id))
    #endif
    return .result()
  }
}
