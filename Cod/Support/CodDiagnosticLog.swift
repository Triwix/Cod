import Foundation
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
