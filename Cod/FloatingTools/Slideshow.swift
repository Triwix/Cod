import UIKit

/// Image sets: several pictures floated as one PiP window that steps through
/// them on a timer or with PiP's skip buttons. Pictures are copied into Cod's
/// Application Support folder so a set keeps working if the originals change.
enum Slideshow {
  static let maximumImages = 30
  static let intervalRange: ClosedRange<Double> = 2...120
  /// Long edge for stored slides: sharp in PiP, small on disk.
  static let storedEdge = 1_600

  enum SlideshowError: LocalizedError {
    case empty, tooMany, unreadable
    var errorDescription: String? {
      switch self {
      case .empty: return "Choose at least two images for an image set."
      case .tooMany: return "Choose up to \(Slideshow.maximumImages) images."
      case .unreadable: return "Cod couldn't read one of these images."
      }
    }
  }

  static var directory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Image Sets", isDirectory: true)
  }

  /// Stores decoded images and returns their file names, in order.
  static func store(_ images: [UIImage]) throws -> [String] {
    guard images.count >= 2 else { throw SlideshowError.empty }
    guard images.count <= maximumImages else { throw SlideshowError.tooMany }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try images.map { image in
      let bounded = image.fitted(within: CGSize(width: storedEdge, height: storedEdge), preferredRange: .standard)
      guard let data = bounded.jpegData(compressionQuality: 0.9) else { throw SlideshowError.unreadable }
      let name = UUID().uuidString + ".jpg"
      try data.write(to: directory.appendingPathComponent(name), options: .atomic)
      return name
    }
  }

  /// Stores rendered pages of an auto-scroll document (one or more).
  static func storePages(_ images: [UIImage]) throws -> [String] {
    guard !images.isEmpty else { throw SlideshowError.empty }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try images.map { image in
      guard let data = image.jpegData(compressionQuality: 0.88) else { throw SlideshowError.unreadable }
      let name = UUID().uuidString + ".jpg"
      try data.write(to: directory.appendingPathComponent(name), options: .atomic)
      return name
    }
  }

  /// Full-size stored page (not bounded to the slide edge).
  static func page(named name: String) -> UIImage? {
    guard !name.contains("/") else { return nil }
    return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
  }

  /// At launch, nothing is floating yet, so only saved presets and Recents
  /// need their images. Anything else is left over from an earlier session.
  @MainActor static func removeUnusedAtLaunch() {
    let configurations = SavedReferenceStore.shared.items.compactMap(\.tool)
      + RecentFloats.shared.items.map(\.configuration)
    removeUnused(keeping: Set(configurations.flatMap { $0.slideNames + $0.documentPages }))
  }

  /// Removes stored sets that no saved reference or live float still uses.
  static func removeUnused(keeping names: Set<String>) {
    let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    for file in files where !names.contains(file.lastPathComponent) && file.pathExtension == "jpg" {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 6
    return cache
  }()

  static func image(named name: String) -> UIImage? {
    if let hit = cache.object(forKey: name as NSString) { return hit }
    guard !name.contains("/"),
      let image = UIImage.decodedImage(at: directory.appendingPathComponent(name), maximumEdge: storedEdge)
    else { return nil }
    cache.setObject(image, forKey: name as NSString)
    return image
  }

  /// Which slide shows at a point on the set's timeline.
  static func index(elapsed: TimeInterval, interval: TimeInterval, count: Int) -> Int {
    guard count > 0 else { return 0 }
    let step = interval.isFinite && interval > 0 ? interval : 5
    let safe = elapsed.isFinite ? max(0, elapsed) : 0
    return min(count - 1, Int(safe / step))
  }
}
