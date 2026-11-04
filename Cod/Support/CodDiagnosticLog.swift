import Foundation

/// File-backed stage logging survives foreground/background transitions and
/// can be retrieved without attaching a debugger. No image content is logged.
enum CodDiagnosticLog {
  static let maximumFileBytes = 128 * 1_024
  private static let queue = DispatchQueue(label: "com.josh.cod.stage-diagnostics")

  static func record(_ message: @autoclosure () -> String) {
    #if DEBUG
    let message = message()
    queue.async {
      guard
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      else { return }
      let url = directory.appendingPathComponent("cod-diagnostics.log")
      append(message, at: url)
    }
    #endif
  }

  /// Each caller serializes writes to its own fixed, private log URL.
  static func append(_ message: String, at url: URL) {
    guard let data = boundedLine(message).data(using: .utf8) else { return }
    defer { excludeFromBackup(url) }
    if !FileManager.default.fileExists(atPath: url.path)
      || ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) + data.count
        > maximumFileBytes
    {
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

  static func boundedLine(_ message: String, date: Date = .now) -> String {
    // Bound UTF-8 bytes, not grapheme count; flatten embedded line breaks.
    let clipped = String(decoding: message.utf8.prefix(4_000), as: UTF8.self)
      .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    return "\(ISO8601DateFormatter().string(from: date)) \(clipped)\n"
  }

  private static func excludeFromBackup(_ url: URL) {
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? target.setResourceValues(values)
  }
}
