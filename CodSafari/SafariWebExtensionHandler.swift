import SafariServices

/// The extension works entirely inside Safari. It keeps the required native
/// handler but never opens Cod or exchanges data with it.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        context.completeRequest(returningItems: [], completionHandler: nil)
    }
}
