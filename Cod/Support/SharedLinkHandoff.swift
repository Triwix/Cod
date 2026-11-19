import Foundation

/// One web link shared into Cod's Share extension, waiting for the person to
/// open Cod. Like the image handoff, the extension never opens the app; Cod
/// claims the link once, within a few minutes, when it next becomes active.
final class SharedLinkHandoff {
  static let shared = SharedLinkHandoff()
  static let maximumAge: TimeInterval = 300

  private struct Record: Codable {
    let url: URL
    let createdAt: Date
  }

  private let container: () -> URL?
  init(container: @escaping () -> URL? = {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "CodAppGroup") as? String,
      group.hasPrefix("group."), !group.contains("$(") else { return nil }
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }) { self.container = container }

  private var file: URL? {
    container()?.appendingPathComponent("Shared Link", isDirectory: true)
      .appendingPathComponent("link.json")
  }

  func store(_ url: URL, now: Date = Date()) throws {
    guard let file else { throw SharedImageInbox.InboxError.unavailable }
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    var directory = file.deletingLastPathComponent()
    try? directory.setResourceValues(excluded)
    try JSONEncoder().encode(Record(url: url, createdAt: now)).write(to: file, options: .atomic)
  }

  /// The pending link, removed as it's read. Old links are discarded.
  func claim(now: Date = Date()) -> URL? {
    guard let file, let data = try? Data(contentsOf: file) else { return nil }
    try? FileManager.default.removeItem(at: file)
    guard let record = try? JSONDecoder().decode(Record.self, from: data),
      now.timeIntervalSince(record.createdAt) <= Self.maximumAge
    else { return nil }
    return record.url
  }
}

/// Web addresses typed or shared into Cod's web video screen.
enum WebVideoLink {
  /// A web address from typed or shared text: the first http(s) link in it,
  /// or a bare domain such as "youtube.com/watch?v=…". Upgrades http to https.
  static func url(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
      let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      let found = match.url, let scheme = found.scheme?.lowercased(), scheme == "http" || scheme == "https"
    {
      return secure(found)
    }
    guard !trimmed.contains(" "), trimmed.contains("."),
      let url = URL(string: "https://" + trimmed), url.host?.contains(".") == true
    else { return nil }
    return url
  }

  /// Text that is nothing but one web link, as video apps share it.
  static func loneLink(in text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
      let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
      match.range.location == 0, match.range.length == (trimmed as NSString).length,
      let found = match.url, let scheme = found.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return nil }
    return secure(found)
  }

  private static func secure(_ url: URL) -> URL {
    guard url.scheme?.lowercased() == "http",
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return url }
    components.scheme = "https"
    return components.url ?? url
  }
}
