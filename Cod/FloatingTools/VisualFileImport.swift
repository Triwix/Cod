import UIKit
import UniformTypeIdentifiers

enum VisualFileImport {
  static let contentTypes: [UTType] = [.image, .movie, .pdf]
  static let maximumImageBytes = 50 * 1_024 * 1_024

  enum Content {
    case image(UIImage), video(VideoReference), pdf(PDFReference)
  }

  enum ImportError: LocalizedError, Equatable {
    case unsupported, imageTooLarge, unreadableImage, unavailable
    var errorDescription: String? {
      switch self {
      case .unsupported: return "Choose a supported image, playable video, or PDF."
      case .imageTooLarge: return "Choose an image smaller than 50 MB."
      case .unreadableImage:
        return "Cod couldn't read that image. Try exporting a PNG or JPEG copy."
      case .unavailable:
        return
          "The selected item couldn't be loaded. Open it in Photos or Files, let it finish downloading, then choose it again."
      }
    }
  }

  static func image(from data: Data?) throws -> UIImage {
    guard let data else { throw ImportError.unavailable }
    guard data.count <= maximumImageBytes else { throw ImportError.imageTooLarge }
    guard let image = ReferenceImage.decode(data) else { throw ImportError.unreadableImage }
    return image
  }

  @MainActor static func open(_ url: URL) async throws -> Content {
    try Task.checkCancellation()
    guard url.isFileURL else { throw ImportError.unsupported }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true,
      let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
    else { throw ImportError.unsupported }
    if type.conforms(to: .pdf) { return .pdf(try PDFReference(url: url)) }
    if type.conforms(to: .movie) { return .video(try await VideoReference.copy(from: url)) }
    guard type.conforms(to: .image) else { throw ImportError.unsupported }
    guard let bytes = values.fileSize, bytes <= maximumImageBytes else {
      throw ImportError.imageTooLarge
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    try Task.checkCancellation()
    if AnimatedImageImport.isAnimatedGIF(data) {
      return .video(
        try await AnimatedImageImport.video(
          data, name: url.deletingPathExtension().lastPathComponent))
    }
    return .image(try image(from: data))
  }
}
