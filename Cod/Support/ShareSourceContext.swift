#if COD_PERSONAL
import Darwin
import ObjectiveC
import UIKit

/// Private, personal-build host lookup. Never use unguarded KVC: missing
/// private keys throw Objective-C exceptions rather than Swift errors.
enum ShareSourceContext {
    #if DEBUG
    /// Bounded field-name inspection only. Never log captions, dates,
    /// locations, filenames or other image metadata values.
    static func imagePropertyKeyPaths(_ properties: NSDictionary) -> [String] {
        var queue: [(NSDictionary, String, Int)] = [(properties, "", 0)]
        var visited = Set<ObjectIdentifier>()
        var paths: [String] = []
        var index = 0
        while index < queue.count, visited.count < 16, paths.count < 32 {
            let (dictionary, prefix, depth) = queue[index]
            index += 1
            guard visited.insert(ObjectIdentifier(dictionary)).inserted else { continue }
            for key in dictionary.allKeys.compactMap({ $0 as? String }).sorted().prefix(16) {
                guard paths.count < 32,
                      let match = key.range(of: "^[A-Za-z0-9_.:{}-]{1,80}$", options: .regularExpression),
                      match == (key.startIndex..<key.endIndex) else { continue }
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                paths.append(path)
                if depth < 2, let child = dictionary[key] as? NSDictionary { queue.append((child, path, depth + 1)) }
            }
        }
        return paths
    }

    /// Diagnostic only. Never used to choose a return destination: a system
    /// query may identify a transient overlay rather than the app underneath.
    /// No entitlements, process enumeration, polling or app-history lookup.
    static func probeForegroundIdentifier(diagnostic: (String) -> Void) {
        let path = "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
            diagnostic("foreground probe: framework unavailable")
            return
        }
        defer { dlclose(library) }
        let name = "SBSCopyFrontmostApplicationDisplayIdentifier"
        guard let symbol = dlsym(library, name) else {
            diagnostic("foreground probe: symbol unavailable")
            return
        }
        typealias CopyIdentifier = @convention(c) () -> Unmanaged<CFString>?
        let copyIdentifier = unsafeBitCast(symbol, to: CopyIdentifier.self)
        let start = CFAbsoluteTimeGetCurrent()
        let identifier = copyIdentifier()?.takeRetainedValue() as String?
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        diagnostic("foreground probe: identifier=\(identifier ?? "nil") elapsed=\(elapsed)ms")
    }
    #endif

    /// ScreenshotServices keeps the captured app in SSEnvironmentDescription.
    /// It may not forward that object into third-party share extensions. Look
    /// only in this share's existing items/providers, never global app state,
    /// old share history, image recognition, URLs, or a guessed Spotify target.
    static func screenshotOrigin(from items: [NSExtensionItem], diagnostic: ((String) -> Void)? = nil) -> String? {
        var queue: [(NSObject, Int)] = []
        for item in items.prefix(4) {
            queue.append((item, 0))
            if let info = item.userInfo { queue.append((info as NSDictionary, 0)) }
            for provider in (item.attachments ?? []).prefix(4) {
                queue.append((provider, 0))
                if let info = objectValue(provider, getter: "userInfo") as? NSDictionary { queue.append((info, 0)) }
                if let ivar = class_getInstanceVariable(type(of: provider), "_metadata"),
                   let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64,
                   let metadata = object_getIvar(provider, ivar) as? NSDictionary {
                    queue.append((metadata, 0))
                }
            }
        }
        var visited = Set<ObjectIdentifier>()
        var inspectedClasses = Set<String>()
        var index = 0
        while index < queue.count, visited.count < 32 {
            let (object, depth) = queue[index]
            index += 1
            guard visited.insert(ObjectIdentifier(object)).inserted else { continue }
            let name = NSStringFromClass(type(of: object))
            inspectedClasses.insert(name)
            if name == "SSEnvironmentDescription", let origin = bundleIdentifier(fromScreenshotEnvironment: object) {
                diagnostic?("screenshot captured-app metadata source=\(origin)")
                return origin
            }
            guard depth < 3 else { continue }
            if let dictionary = object as? NSDictionary {
                for case let child as NSObject in dictionary.allValues.prefix(16) { queue.append((child, depth + 1)) }
            } else if let array = object as? NSArray {
                for case let child as NSObject in array.prefix(8) { queue.append((child, depth + 1)) }
            } else if name.hasPrefix("SSSScreenshot") {
                for getter in ["screenshot", "environmentDescription"] {
                    if let child = objectValue(object, getter: getter) as? NSObject { queue.append((child, depth + 1)) }
                }
            }
        }
        // Classes only: no metadata values, titles, URLs or screenshot content.
        diagnostic?("screenshot original-app metadata unavailable; inspected classes=\(inspectedClasses.sorted().joined(separator: ","))")
        return nil
    }

    static func bundleIdentifier(fromScreenshotEnvironment environment: NSObject) -> String? {
        guard let source = objectValue(environment, getter: "currentApplicationBundleID") as? String,
              isValid(source),
              !["com.josh.cod", "com.josh.cod.share", "com.apple.ScreenshotServicesService", "com.apple.UIKit.ShareSheet"].contains(source)
        else { return nil }
        return source
    }

    static func bundleIdentifier(from controller: UIViewController, diagnostic: ((String) -> Void)? = nil) -> String? {
        var candidates: [NSObject] = []
        var candidateIDs = Set<ObjectIdentifier>()
        var visitedResponders = Set<ObjectIdentifier>()
        func addCandidate(_ candidate: NSObject) {
            if candidateIDs.insert(ObjectIdentifier(candidate)).inserted { candidates.append(candidate) }
        }
        var responder: UIResponder? = controller
        // Device share extensions use a hosted scene/root controller rather
        // than the legacy operator used by this Simulator. Include both paths.
        while let current = responder, visitedResponders.insert(ObjectIdentifier(current)).inserted, visitedResponders.count <= 32 {
            addCandidate(current)
            var parent = (current as? UIViewController)?.parent
            var visitedParents = Set<ObjectIdentifier>()
            while let currentParent = parent, visitedParents.insert(ObjectIdentifier(currentParent)).inserted, visitedParents.count <= 32 {
                addCandidate(currentParent)
                parent = currentParent.parent
            }
            responder = current.next
        }
        if let context = controller.extensionContext { addCandidate(context) }
        let scene = controller.viewIfLoaded?.window?.windowScene
        if let scene { addCandidate(scene) }

        for candidate in candidates {
            for name in ["_hostApplicationBundleIdentifier", "_hostBundleIdentifier", "_hostBundleID", "_hostBundleId"] {
                if let identifier = objectValue(candidate, getter: name) as? String, isValid(identifier) {
                    diagnostic?("source via \(type(of: candidate)).\(name)=\(identifier)")
                    return identifier
                }
                if let ivar = class_getInstanceVariable(type(of: candidate), name),
                   let encoding = ivar_getTypeEncoding(ivar), encoding.pointee == 64,
                   let identifier = object_getIvar(candidate, ivar) as? String, isValid(identifier) {
                    diagnostic?("source via \(type(of: candidate)) ivar \(name)=\(identifier)")
                    return identifier
                }
            }
        }

        // iOS 26 hosted scenes no longer expose the legacy controller's
        // _hostBundleID. Read only our own scene and existing host connection.
        if let scene, let source = bundleIdentifier(fromSceneObject: scene, diagnostic: diagnostic) {
            return source
        }
        if let context = controller.extensionContext,
           let connection = objectValue(context, getter: "_auxiliaryConnection") as? NSXPCConnection,
           let handle = processHandle(for: connection, selector: "processHandleForNSXPCConnection:"),
           let source = sourceIdentifier(fromProcess: handle, diagnostic: diagnostic) {
            diagnostic?("source via extension host connection=\(source)")
            return source
        }

        if let scene {
            var identifiers = [scene.session.persistentIdentifier]
            // Read only the extension's own scene identity, not other apps or
            // a foreground-app enumeration. Never interpret arbitrary text as
            // an app identifier: require the complete UIKit hosting format.
            for getter in ["_FBSScene", "_scene", "_fbsScene"] {
                if let underlying = objectValue(scene, getter: getter) as? NSObject {
                    let identities = [underlying] + ["identity", "_identity"].compactMap {
                        objectValue(underlying, getter: $0) as? NSObject
                    }
                    for identity in identities {
                        if let identifier = objectValue(identity, getter: "identifier") as? String {
                            identifiers.append(identifier)
                            // FrontBoard may store the hosting namespace and
                            // hosted scene identifier as separate fields.
                            if let workspace = objectValue(identity, getter: "workspaceIdentifier") as? String {
                                identifiers.append("\(workspace):\(identifier)")
                            }
                        }
                    }
                }
            }
            if let identifier = objectValue(scene, getter: "_identifier") as? String { identifiers.append(identifier) }
            for identifier in identifiers {
                diagnostic?("hosted scene identifier=\(identifier.prefix(350))")
                if let source = bundleIdentifier(fromHostedSceneIdentifier: identifier) {
                    diagnostic?("source via hosted scene=\(source)")
                    return source
                }
            }
        }
        // Bounded, names-only diagnostics make future device differences
        // inspectable without a debugger or logging shared-image content.
        for candidate in candidates {
            var inspectedClass: AnyClass? = type(of: candidate)
            while let currentClass = inspectedClass, currentClass != NSObject.self {
                var count: UInt32 = 0
                if let ivars = class_copyIvarList(currentClass, &count) {
                    defer { free(ivars) }
                    let names = (0..<Int(count)).compactMap { index -> String? in
                        guard let name = ivar_getName(ivars[index]) else { return nil }
                        let value = String(cString: name)
                        return value.lowercased().contains("host") || value.lowercased().contains("bundle") ? value : nil
                    }
                    if !names.isEmpty { diagnostic?("source lookup \(currentClass) fields=\(names.joined(separator: ","))") }
                }
                inspectedClass = class_getSuperclass(currentClass)
            }
        }
        return nil
    }

    /// Object-only getters are signature checked. Keep this path testable
    /// without constructing UIKit's private scene classes.
    static func bundleIdentifier(fromSceneObject scene: NSObject, diagnostic: ((String) -> Void)? = nil) -> String? {
        guard let underlying = objectValue(scene, getter: "_FBSScene") as? NSObject else { return nil }
        diagnostic?("modern hosted scene class=\(type(of: underlying))")
        if let process = objectValue(underlying, getter: "hostProcess") as? NSObject,
           let source = sourceIdentifier(fromProcess: process, diagnostic: diagnostic) {
            diagnostic?("source via scene host process=\(source)")
            return source
        }
        let handle = objectValue(underlying, getter: "hostHandle") as? NSObject
        let token = (objectValue(underlying, getter: "hostAuditToken") as? NSObject)
            ?? handle.flatMap { objectValue($0, getter: "auditToken") as? NSObject }
        if let token, let process = processHandle(for: token, selector: "processHandleForAuditToken:"),
           let source = sourceIdentifier(fromProcess: process, diagnostic: diagnostic) {
            diagnostic?("source via scene host audit token=\(source)")
            return source
        }
        diagnostic?("modern scene host did not identify an originating app")
        return nil
    }

    private static func sourceIdentifier(fromProcess process: NSObject, diagnostic: ((String) -> Void)?) -> String? {
        let objects = [process] + ["handle", "identity"].compactMap { objectValue(process, getter: $0) as? NSObject }
        for object in objects {
            for getter in ["bundleIdentifier", "embeddedApplicationIdentifier"] {
                guard let identifier = objectValue(object, getter: getter) as? String, isValid(identifier) else { continue }
                // A scene's host can be SpringBoard/ShareSheet, even when the
                // user shared from another app. That isn't proof of Home.
                guard !["com.josh.cod", "com.josh.cod.share", "com.apple.springboard", "com.apple.UIKit.ShareSheet"].contains(identifier) else {
                    diagnostic?("ignoring intermediary scene/connection host=\(identifier)")
                    continue
                }
                return identifier
            }
        }
        return nil
    }

    private static func processHandle(for hostObject: NSObject, selector name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let handleClass = NSClassFromString("BSProcessHandle"),
              let method = class_getClassMethod(handleClass, selector),
              method_getNumberOfArguments(method) == 3 else { return nil }
        let result = method_copyReturnType(method)
        let argument = method_copyArgumentType(method, 2)
        defer { free(result); free(argument) }
        guard String(cString: result) == "@", let argument, String(cString: argument) == "@" else { return nil }
        return (handleClass as AnyObject).perform(selector, with: hostObject)?.takeUnretainedValue() as? NSObject
    }

    static func bundleIdentifier(fromHostedSceneIdentifier identifier: String) -> String? {
        let prefix = "UISceneHosting-"
        let separator = ":UIHostedScene-"
        guard identifier.hasPrefix(prefix),
              let range = identifier.range(of: separator),
              !identifier[range.upperBound...].isEmpty else { return nil }
        let source = String(identifier[identifier.index(identifier.startIndex, offsetBy: prefix.count)..<range.lowerBound])
        return isValid(source) ? source : nil
    }

    private static func objectValue(_ object: NSObject, getter name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector),
              let method = class_getInstanceMethod(type(of: object), selector),
              method_getNumberOfArguments(method) == 2 else { return nil }
        let result = method_copyReturnType(method)
        defer { free(result) }
        guard String(cString: result) == "@" else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    static func isValid(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 255 && identifier.contains(".")
            && identifier.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0)
            }
    }
}
#endif
