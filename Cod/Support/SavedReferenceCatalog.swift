import Foundation

/// Minimal metadata shared with WidgetKit. No note text or media is placed in
/// widgets or exposed on the Lock Screen; an authenticated tap opens Cod.
struct SavedReferenceSummary: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  var detail: String
}

enum SavedReferenceCatalog {
  static var directory: URL? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "CodAppGroup") as? String,
      group.hasPrefix("group."), !group.contains("$("),
      let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    return root.appendingPathComponent("SavedReferences", isDirectory: true)
  }
  static func entries() throws -> [SavedReferenceSummary] {
    guard let directory else { return [] }
    return try ["index.json", "favorites.json"].flatMap { name -> [SavedReferenceSummary] in
      let url = directory.appendingPathComponent(name)
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      return try JSONDecoder().decode([SavedReferenceSummary].self, from: Data(contentsOf: url))
    }
  }
  static func publishFavorites(_ entries: [SavedReferenceSummary]) throws {
    guard let directory else { return }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(entries).write(
      to: directory.appendingPathComponent("favorites.json"), options: .atomic)
  }
}
