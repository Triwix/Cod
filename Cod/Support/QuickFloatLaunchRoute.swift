import Foundation

/// The URL carries only a one-shot request ID, never image bytes, file paths,
/// an arbitrary app destination or a source-app identifier. Shared storage
/// remains authoritative; a stale URL cannot consume a newer image.
struct QuickFloatLaunchRoute {
    let scheme: String

    static var configured: QuickFloatLaunchRoute? {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "CodFloatURLScheme") as? String,
              !scheme.isEmpty, !scheme.contains("$(") else { return nil }
        return QuickFloatLaunchRoute(scheme: scheme)
    }

    func url(for id: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "float-shared-image"
        components.queryItems = [URLQueryItem(name: "request", value: id.uuidString)]
        return components.url
    }

    func requestID(in url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme.lowercased(),
              components.host?.lowercased() == "float-shared-image",
              components.user == nil, components.password == nil, components.port == nil,
              components.path.isEmpty, components.fragment == nil,
              let items = components.queryItems, items.count == 1,
              items[0].name == "request", let value = items[0].value else { return nil }
        return UUID(uuidString: value)
    }
}
