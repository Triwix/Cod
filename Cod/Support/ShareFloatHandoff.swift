import Foundation
import UIKit

/// A short-lived bridge from the Share extension to the containing app.
///
/// A free provisioning profile cannot use an App Group, so the extension and
/// app do not have a shared directory. The system pasteboard is the one local
/// bridge both processes can access. A private type keeps the handoff out of
/// ordinary paste operations, and `takePayload()` removes only Cod's payload.
#if COD_PERSONAL
enum ShareFloatHandoff {
    static let pasteboardType = "com.josh.cod.float-image"
    static let sourcePasteboardType = "com.josh.cod.float-source"

    struct Payload {
        let image: UIImage
        let sourceBundleIdentifier: String?
    }

    static let url = URL(string: "cod://float-shared-image")!

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "cod" && url.host?.lowercased() == "float-shared-image"
    }

    static func store(_ image: UIImage, sourceBundleIdentifier: String? = nil) -> Bool {
        CodDiagnosticLog.record("handoff: encoding crop")
        guard let data = image.pngData() else { return false }

        let pasteboard = UIPasteboard.general
        pasteboard.items = itemsWithPayload(
            pasteboard.items,
            imageData: data,
            sourceBundleIdentifier: sourceBundleIdentifier
        )
        CodDiagnosticLog.record("handoff: stored crop bytes=\(data.count)")
        return true
    }

    static func itemsWithPayload(
        _ existing: [[String: Any]], imageData: Data, sourceBundleIdentifier: String?
    ) -> [[String: Any]] {
        var items = itemsWithoutPayload(existing)
        if items.isEmpty {
            items = [[pasteboardType: imageData]]
        } else {
            items[0][pasteboardType] = imageData
        }
        // Always clear stale metadata, including on shares from unknown hosts.
        items[0].removeValue(forKey: sourcePasteboardType)
        if let sourceBundleIdentifier, ShareSourceContext.isValid(sourceBundleIdentifier) {
            items[0][sourcePasteboardType] = Data(sourceBundleIdentifier.utf8)
        }
        return items
    }

    static func takePayload(from pasteboard: UIPasteboard = .general) -> Payload? {
        CodDiagnosticLog.record("handoff: reading crop representation")
        guard let data = pasteboard.data(forPasteboardType: pasteboardType) else {
            CodDiagnosticLog.record("handoff: crop representation missing")
            return nil
        }
        // Claim once even when decoding fails. A broken image must not linger
        // and be replayed by a later launch; unrelated clipboard items survive.
        defer { pasteboard.items = itemsWithoutPayload(pasteboard.items) }
        guard let image = UIImage(data: data) else {
            CodDiagnosticLog.record("handoff: crop decode failed bytes=\(data.count)")
            return nil
        }
        CodDiagnosticLog.record("handoff: received crop=\(Int(image.pixelSize.width))x\(Int(image.pixelSize.height))")
        let source = pasteboard.data(forPasteboardType: sourcePasteboardType)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { ShareSourceContext.isValid($0) ? $0 : nil }

        // Preserve anything the user already had copied. Remove only Cod's
        // private representation after the app has claimed it.
        return Payload(image: image, sourceBundleIdentifier: source)
    }

    static func itemsWithoutPayload(_ items: [[String: Any]]) -> [[String: Any]] {
        items.compactMap { item -> [String: Any]? in
            var item = item
            item.removeValue(forKey: pasteboardType)
            item.removeValue(forKey: sourcePasteboardType)
            return item.isEmpty ? nil : item
        }
    }
}

#endif

/// File-backed stage logging survives foreground/background transitions and
/// can be retrieved without attaching a debugger. No image content is logged.
enum CodDiagnosticLog {
    private static let queue = DispatchQueue(label: "com.josh.cod.stage-diagnostics")

    static func record(_ message: String) {
        queue.async {
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = directory.appendingPathComponent("cod-diagnostics.log")
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: url.path)
                || ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 128 * 1_024 {
                try? data.write(to: url, options: .atomic)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Logging must not interfere with the action being diagnosed.
            }
        }
    }
}
