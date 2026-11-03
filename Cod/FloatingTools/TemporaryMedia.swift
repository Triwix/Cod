import Foundation

enum OwnedMediaFile {
  static func matches(_ name: String, extensions: Set<String>, suffix: String = "") -> Bool {
    guard name == URL(fileURLWithPath: name).lastPathComponent else { return false }
    let url = URL(fileURLWithPath: name)
    guard extensions.contains(url.pathExtension.lowercased()) else { return false }
    var stem = url.deletingPathExtension().lastPathComponent
    if !suffix.isEmpty {
      guard stem.hasSuffix(suffix) else { return false }
      stem.removeLast(suffix.count)
    }
    return UUID(uuidString: stem) != nil
  }
}

enum TemporaryMedia {
  enum Kind: String, CaseIterable {
    case imports = "CodVideoImports", animations = "CodAnimations", crops = "CodVideoCrops"
  }

  static func directory(_ kind: Kind) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      kind.rawValue, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Only at process launch, before Cod starts creating playback references.
  /// Never sweep the temp root, provider folders, or legacy anonymous crop files.
  static func cleanUpAfterPreviousLaunch(base: URL = FileManager.default.temporaryDirectory) {
    for kind in Kind.allCases {
      let folder = base.appendingPathComponent(kind.rawValue, isDirectory: true)
      guard let folderValues = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]),
        folderValues.isSymbolicLink != true,
        let files = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      else { continue }
      for file in files
      where OwnedMediaFile.matches(file.lastPathComponent, extensions: ["mp4", "mov", "m4v"]) {
        guard
          let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          values.isRegularFile == true, values.isSymbolicLink != true
        else { continue }
        try? FileManager.default.removeItem(at: file)
      }
    }
  }
}
