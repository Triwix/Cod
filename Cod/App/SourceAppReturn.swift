#if COD_PERSONAL
import ObjectiveC
import UIKit

/// Restore an existing app, not a content URL or a guessed Photos/Shortcuts
/// destination. Private selectors are signature-checked and best-effort only.
@MainActor
final class SourceAppReturn {
    static let shared = SourceAppReturn()
    private var sourceBundleIdentifier: String?
    private var navigationAction: NSObject?
    #if DEBUG
    private var navigationDiagnosticObserver: NSObjectProtocol?

    /// Explicit launch-argument experiment. Observe only Cod's navigation
    /// token; no status-bar creation, swizzling or navigation is performed.
    func startNavigationDiagnostics() {
        guard navigationDiagnosticObserver == nil else { return }
        navigationDiagnosticObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationSystemNavigationActionChangedNotification"),
            object: UIApplication.shared, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inspectNavigationContext(reason: "token notification") }
        }
        inspectNavigationContext(reason: "observer started")
    }

    func inspectNavigationContext(reason: String) {
        guard navigationDiagnosticObserver != nil else { return }
        guard let action = currentNavigationAction() else {
            log("navigation probe \(reason): token=nil")
            return
        }
        let destinations = objectValue(action, getter: "destinations") as? [NSNumber] ?? []
        log("navigation probe \(reason): token=\(type(of: action)) valid=\(boolValue(action, getter: "isValid").map(String.init) ?? "unknown") destinations=\(destinations.prefix(4))")
        guard destinations.contains(where: { $0.uintValue == 0 }) else { return }
        let selector = NSSelectorFromString("bundleIdForDestination:")
        guard let method = class_getInstanceMethod(type(of: action), selector),
              signature(method, result: "@", arguments: ["Q"]) else { return }
        typealias GetBundle = @convention(c) (NSObject, Selector, UInt) -> Unmanaged<AnyObject>?
        let getter = unsafeBitCast(method_getImplementation(method), to: GetBundle.self)
        let bundle = getter(action, selector, 0)?.takeUnretainedValue() as? String
        log("navigation probe primary source=\(bundle.flatMap { ShareSourceContext.isValid($0) ? $0 : nil } ?? "unknown")")
    }
    #endif

    var shouldReturnHome: Bool {
        Self.requiresHomeFallback(for: sourceBundleIdentifier)
    }

    func discard() {
        sourceBundleIdentifier = nil
        navigationAction = nil
    }

    func capture(sourceBundleIdentifier: String? = nil) {
        #if DEBUG
        inspectNavigationContext(reason: "float context capture")
        #endif
        self.sourceBundleIdentifier = sourceBundleIdentifier.flatMap { ShareSourceContext.isValid($0) ? $0 : nil }
        navigationAction = Self.requiresHomeFallback(for: self.sourceBundleIdentifier) ? nil : currentNavigationAction()
        log("capture source=\(self.sourceBundleIdentifier ?? "unknown") navigation=\(navigationAction != nil)")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--return-probe") || ProcessInfo.processInfo.arguments.contains("--navigation-probe") {
            let scenes = UIApplication.shared.connectedScenes
            let managers = scenes.compactMap { ($0 as? UIWindowScene)?.statusBarManager }
            for object in [UIApplication.shared as NSObject] + scenes.map({ $0 as NSObject }) + managers.map({ $0 as NSObject }) {
                var currentClass: AnyClass? = type(of: object)
                while let inspectedClass = currentClass {
                    var count: UInt32 = 0
                    if let methods = class_copyMethodList(inspectedClass, &count) {
                        defer { free(methods) }
                        let names = (0..<Int(count)).compactMap { index -> String? in
                            let name = NSStringFromSelector(method_getName(methods[index]))
                            return name.lowercased().contains("navigationaction") || name.lowercased().contains("breadcrumb") ? name : nil
                        }
                        if !names.isEmpty { log("probe navigation methods \(inspectedClass): \(names.joined(separator: ","))") }
                    }
                    currentClass = class_getSuperclass(inspectedClass)
                }
            }
        }
        #endif
    }

    /// true means a request was dispatched, not proof of the exact screen.
    func returnToSource() async -> Bool {
        guard !Task.isCancelled else { return false }
        #if DEBUG
        inspectNavigationContext(reason: "return requested")
        #endif
        let source = sourceBundleIdentifier
        let capturedAction = navigationAction
        // Consume the context. A later shortcut must never inherit a previous
        // Photos share's destination.
        sourceBundleIdentifier = nil
        navigationAction = nil

        // The screenshot preview is a temporary system service, not a normal
        // app to reactivate. Reopening it after the share session completes
        // creates a black "Screenshots" screen. Do not send a breadcrumb to it
        // either: preserve PiP and let the caller use its Home fallback.
        guard !Self.requiresHomeFallback(for: source) else {
            log("source=\(source ?? "unknown") requires Home fallback; skipping app activation and Back-to")
            return false
        }
        let action = capturedAction ?? currentNavigationAction()

        if let action, sendNavigationResponse(action, expectedSource: source) {
            // The private BOOL only reports a destination context existed.
            // It doesn't acknowledge that SpringBoard actually switched apps.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return false }
            if UIApplication.shared.applicationState != .active { return true }
            log("Back-to response dispatched but Cod remains active; trying identified source")
        }
        // Keep breadcrumb experiments out of normal floating. An existing
        // selector is not proof that invoking a UIKit getter is permitted.
        #if DEBUG
        if source == nil, ProcessInfo.processInfo.arguments.contains("--breadcrumb-probe"),
           performVisibleBackBreadcrumb() {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return false }
            if UIApplication.shared.applicationState != .active { return true }
            log("visible Back-to action ran but Cod remains active")
        }
        #endif
        guard let source, source != "com.josh.cod", source != "com.josh.cod.share" else {
            log("no reliable source; no app will be guessed")
            return false
        }
        guard !Task.isCancelled else { return false }
        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace"),
              let defaultMethod = class_getClassMethod(workspaceClass, NSSelectorFromString("defaultWorkspace")),
              signature(defaultMethod, result: "@", arguments: []),
              let workspace = (workspaceClass as AnyObject).perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject,
              let method = class_getInstanceMethod(type(of: workspace), selector),
              signature(method, result: "B", arguments: ["@"]) else {
            log("source-app activation unavailable or signature changed")
            return false
        }
        typealias OpenApp = @convention(c) (NSObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(method_getImplementation(method), to: OpenApp.self)
        let accepted = open(workspace, selector, source as NSString)
        log("source-app activation source=\(source) accepted=\(accepted)")
        if accepted {
            try? await Task.sleep(nanoseconds: 500_000_000)
            log("source-app activation Cod state after request=\(UIApplication.shared.applicationState.rawValue)")
        }
        return accepted
    }

    static func requiresHomeFallback(for source: String?) -> Bool {
        // Match the host observed in device logs, not image contents, filenames,
        // or a broad "screenshot" substring. Saved screenshots shared from
        // Photos must continue returning to Photos.
        source == "com.apple.springboard" || source == "com.apple.ScreenshotServicesService"
    }

    private func currentNavigationAction() -> NSObject? {
        let application = UIApplication.shared
        let selector = NSSelectorFromString("_systemNavigationAction")
        if let method = class_getInstanceMethod(type(of: application), selector),
           signature(method, result: "@", arguments: []),
           let action = application.perform(selector)?.takeUnretainedValue() as? NSObject { return action }
        if let ivar = class_getInstanceVariable(type(of: application), "_systemNavigationAction"),
           let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64,
           let action = object_getIvar(application, ivar) as? NSObject {
            return action
        }
        // Never ask UIApplication for statusBar/_statusBar here. On physical
        // scene-based iPhones that getter asserts while creating a legacy
        // status bar, before PiP can start. Signature checks cannot prevent it.
        return nil
    }

    /// Historical DEBUG experiment, not an independent return path: published
    /// iOS 26.1 code sends the modern breadcrumb through the same UIApplication
    /// navigation token. Never fabricate an action or create a status bar.
    private func performVisibleBackBreadcrumb() -> Bool {
        guard currentNavigationAction() != nil else {
            log("modern Back-to has no independent token; experiment skipped")
            return false
        }
        guard let barClass = NSClassFromString("_UIStatusBar"),
              let navigationClass = NSClassFromString("_UIStatusBarNavigationItem"),
              let actionClass = NSClassFromString("_UIStatusBarSystemNavigationAction") else {
            log("modern Back-to runtime unavailable")
            return false
        }
        let bars = currentStatusBars()
        log("own status-bar classes=\(bars.map { String(describing: type(of: $0)) }.joined(separator: ","))")
        for bar in bars where bar.isKind(of: barClass) {
            guard let view = bar as? UIView, view.window != nil,
                  let items = objectValue(bar, getter: "items") as? NSDictionary else { continue }
            for case let item as NSObject in items.allValues where item.isKind(of: navigationClass) {
                guard let displayItems = objectValue(item, getter: "displayItems") as? NSDictionary else { continue }
                for case let display as NSObject in displayItems.allValues {
                    guard boolValue(display, getter: "visible") == true,
                          boolValue(display, getter: "isEnabled") == true,
                          let action = objectValue(display, getter: "action") as? NSObject,
                          action.isKind(of: actionClass),
                          boolValue(action, getter: "isEnabled") == true else { continue }
                    let selector = NSSelectorFromString("performWithStatusBar:completionHandler:")
                    guard let method = class_getInstanceMethod(type(of: action), selector),
                          signature(method, result: "v", arguments: ["@", "@?"]) else { continue }
                    let completion: @convention(block) (Bool) -> Void = { succeeded in
                        CodDiagnosticLog.record("return: visible Back-to action callback=\(succeeded)")
                    }
                    typealias PerformAction = @convention(c) (NSObject, Selector, NSObject, AnyObject) -> Void
                    let perform = unsafeBitCast(method_getImplementation(method), to: PerformAction.self)
                    log("dispatching existing visible Back-to breadcrumb action")
                    perform(action, selector, bar, completion as AnyObject)
                    return true
                }
            }
        }
        log("no visible enabled Back-to breadcrumb action")
        return false
    }

    private func currentStatusBars() -> [NSObject] {
        let managers = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.statusBarManager }
        var result: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        for owner in [UIApplication.shared as NSObject] + managers {
            // Read only an already-existing view. No getters, creation,
            // swizzling, KVC, or layout calls on UIApplication/status managers.
            guard let bar = Self.existingStatusBar(from: owner) else { continue }
            if visited.insert(ObjectIdentifier(bar)).inserted { result.append(bar) }
            if let modern = Self.existingStatusBar(from: bar),
               visited.insert(ObjectIdentifier(modern)).inserted { result.append(modern) }
        }
        return result
    }

    static func existingStatusBar(from object: NSObject) -> UIView? {
        guard let ivar = class_getInstanceVariable(type(of: object), "_statusBar"),
              let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64 else { return nil }
        return object_getIvar(object, ivar) as? UIView
    }

    private func objectValue(_ object: NSObject, getter name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: object), selector),
              signature(method, result: "@", arguments: []) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    private func boolValue(_ object: NSObject, getter name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: object), selector),
              signature(method, result: "B", arguments: []) else { return nil }
        typealias GetBool = @convention(c) (NSObject, Selector) -> Bool
        return unsafeBitCast(method_getImplementation(method), to: GetBool.self)(object, selector)
    }

    private func sendNavigationResponse(_ action: NSObject, expectedSource: String?) -> Bool {
        let destinations = NSSelectorFromString("destinations")
        let send = NSSelectorFromString("sendResponseForDestination:")
        guard let getMethod = class_getInstanceMethod(type(of: action), destinations),
              signature(getMethod, result: "@", arguments: []),
              let values = action.perform(destinations)?.takeUnretainedValue() as? [NSNumber],
              let method = class_getInstanceMethod(type(of: action), send),
              signature(method, result: "B", arguments: ["Q"]) else { return false }
        // Destination 0 is Back-to/primary; destination 1 is secondary. Never
        // return to a Forward-to target simply because it appears first.
        for destination in values where destination.uintValue == 0 {
            // If the share extension identified its host, reject a breadcrumb
            // pointing somewhere else rather than returning to the wrong app.
            if let expectedSource {
                let getBundle = NSSelectorFromString("bundleIdForDestination:")
                guard let bundleMethod = class_getInstanceMethod(type(of: action), getBundle),
                      signature(bundleMethod, result: "@", arguments: ["Q"]) else { continue }
                typealias GetBundle = @convention(c) (NSObject, Selector, UInt) -> Unmanaged<AnyObject>?
                let bundle = unsafeBitCast(method_getImplementation(bundleMethod), to: GetBundle.self)
                guard bundle(action, getBundle, destination.uintValue)?.takeUnretainedValue() as? String == expectedSource else { continue }
            }
            let sceneSelector = NSSelectorFromString("sceneIdentifierForDestination:")
            if let method = class_getInstanceMethod(type(of: action), sceneSelector),
               signature(method, result: "@", arguments: ["Q"]) {
                typealias GetScene = @convention(c) (NSObject, Selector, UInt) -> Unmanaged<AnyObject>?
                let getter = unsafeBitCast(method_getImplementation(method), to: GetScene.self)
                let scene = getter(action, sceneSelector, destination.uintValue)?.takeUnretainedValue() as? String
                log("Back-to primary destination has scene=\(scene != nil)")
            }
            typealias Send = @convention(c) (NSObject, Selector, UInt) -> Bool
            let response = unsafeBitCast(method_getImplementation(method), to: Send.self)
            let accepted = response(action, send, destination.uintValue)
            log("system Back-to response dispatched=\(accepted)")
            if accepted { return true }
        }
        return false
    }

    private func signature(_ method: Method, result: String, arguments: [String]) -> Bool {
        guard method_getNumberOfArguments(method) == arguments.count + 2 else { return false }
        let actualResult = method_copyReturnType(method)
        defer { free(actualResult) }
        guard String(cString: actualResult) == result else { return false }
        for (index, expected) in arguments.enumerated() {
            guard let actual = method_copyArgumentType(method, UInt32(index + 2)) else { return false }
            defer { free(actual) }
            guard String(cString: actual) == expected else { return false }
        }
        return true
    }

    private func log(_ message: String) {
        CodDiagnosticLog.record("return: \(message)")
        print("[CodReturn] \(message)")
    }
}
#endif
