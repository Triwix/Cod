import Combine
import UIKit
import WidgetKit

struct SavedTextCard: Codable {
  var text: String
  var fontSize: Double = 44
  var palette: FloatingPalette = .system
  var colors: FloatingColors?
}

struct SavedReference: Codable, Identifiable {
  var id = UUID()
  var name: String
  var detail: String
  var text: SavedTextCard?
  var tool: FloatingToolConfiguration?
  var originalFilename: String?
}

enum SavedReferenceError: LocalizedError {
  case invalidName, invalidContent, missing
  var errorDescription: String? {
    switch self {
    case .invalidName: return "Give this reference a name of 1–80 characters."
    case .invalidContent: return "This reference couldn't be saved. Check its content and settings."
    case .missing:
      return
        "This reference was removed. Choose another saved reference or favorite in your Shortcut or control."
    }
  }
}

@MainActor final class SavedReferenceStore: ObservableObject {
  static let shared = SavedReferenceStore()
  // A bounded decoded JPEG can re-encode to a larger lossless RGBA PNG.
  static let maximumOriginalBytes = 75 * 1_024 * 1_024
  @Published private(set) var items: [SavedReference] = []
  @Published private(set) var loadError: String?
  let directory: URL
  private let publishesWidgets: Bool
  init(directory: URL? = nil) {
    publishesWidgets = directory == nil
    self.directory =
      directory ?? SavedReferenceCatalog.directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SavedReferences")
    do {
      try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
      let url = self.directory.appendingPathComponent("index.json")
      if FileManager.default.fileExists(atPath: url.path) {
        items = try JSONDecoder().decode([SavedReference].self, from: Data(contentsOf: url))
      }
    } catch { loadError = error.localizedDescription }
  }

  @discardableResult func save(
    _ input: SavedReference, original: UIImage? = nil, replacingExisting: Bool = false
  ) throws
    -> SavedReference
  {
    guard loadError == nil else { throw SavedReferenceError.invalidContent }
    let previous = items.first { $0.id == input.id }
    guard !replacingExisting || previous != nil else { throw SavedReferenceError.missing }
    var value = input
    if let name = value.originalFilename, original == nil {
      guard Self.isOriginalFilename(name), previous?.originalFilename == name else {
        throw SavedReferenceError.invalidContent
      }
    }
    value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.name.isEmpty, value.name.count <= 80 else { throw SavedReferenceError.invalidName }
    guard (value.text != nil) != (value.tool != nil) else {
      throw SavedReferenceError.invalidContent
    }
    if let text = value.text {
      guard !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.text.count <= FloatingText.maximumCharacters, text.fontSize.isFinite,
        (28...72).contains(text.fontSize)
      else { throw SavedReferenceError.invalidContent }
    }
    if let tool = value.tool {
      guard tool.kind != .document else { throw SavedReferenceError.invalidContent }
      try tool.validate()
    }
    var createdAsset: URL?
    if let original {
      let filename = "\(UUID().uuidString).png"
      guard let data = original.pngData(), data.count <= Self.maximumOriginalBytes else { throw SavedReferenceError.invalidContent }
      let asset = directory.appendingPathComponent(filename)
      try data.write(to: asset, options: .atomic)
      createdAsset = asset
      value.originalFilename = filename
    }
    var next = items
    if let index = next.firstIndex(where: { $0.id == value.id }) {
      next[index] = value
    } else {
      next.append(value)
    }
    do { try persist(next) } catch {
      if let createdAsset { try? FileManager.default.removeItem(at: createdAsset) }
      throw error
    }
    if let old = previous?.originalFilename, old != value.originalFilename { try? removeAsset(old) }
    return value
  }

  func original(for item: SavedReference) -> UIImage? {
    guard let name = item.originalFilename, Self.isOriginalFilename(name)
    else { return nil }
    let url = directory.appendingPathComponent(name)
    guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
      return nil
    }
    return ReferenceImage.decode(at: url, maximumBytes: Self.maximumOriginalBytes)
  }
  func delete(_ id: UUID) throws {
    let old = items.first { $0.id == id }
    try persist(items.filter { $0.id != id })
    if let name = old?.originalFilename { try removeAsset(name) }
  }
  func clear() throws {
    // Explicit Delete Everything is also the recovery route for a damaged index.
    // Do not silently repair it on launch or on a normal Save.
    try JSONEncoder().encode([SavedReference]()).write(
      to: directory.appendingPathComponent("index.json"), options: .atomic)
    items = []
    loadError = nil
    defer { refreshWidgets() }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    for file in files where Self.isOriginalFilename(file.lastPathComponent) {
      try removeAsset(file.lastPathComponent)
    }
  }
  static func isOriginalFilename(_ name: String) -> Bool {
    OwnedMediaFile.matches(name, extensions: ["png"])
  }
  private func removeAsset(_ name: String) throws {
    guard Self.isOriginalFilename(name) else { return }
    let url = directory.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true || values.isSymbolicLink == true else { return }
    try FileManager.default.removeItem(at: url)
  }
  private func persist(_ next: [SavedReference]) throws {
    guard loadError == nil else { throw SavedReferenceError.invalidContent }
    try JSONEncoder().encode(next).write(
      to: directory.appendingPathComponent("index.json"), options: .atomic)
    items = next
    refreshWidgets()
  }
  private func refreshWidgets() {
    if publishesWidgets {
      WidgetCenter.shared.reloadAllTimelines()
      if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
    }
  }
}
