import AppIntents

enum FloatControlDestination: String, AppEnum {
    case latestScreenshot

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cod action")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .latestScreenshot: "Float Latest Screenshot",
    ]
}

/// Included in both bundles, as required by WidgetKit. OpenIntent asks the
/// system to run this in the containing app, not in the widget process.
struct FloatControlIntent: OpenIntent {
    static var title: LocalizedStringResource = "Float Latest Screenshot"
    static var description = IntentDescription("Open Cod and float the latest screenshot you have saved to Photos.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Action")
    var target: FloatControlDestination

    init() { target = .latestScreenshot }
    init(target: FloatControlDestination) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !COD_CONTROLS_EXTENSION
        IntentInbox.shared.requestFloatLatest()
        #endif
        return .result()
    }
}
