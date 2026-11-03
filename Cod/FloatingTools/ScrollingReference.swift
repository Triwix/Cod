import ImageIO
import UIKit

enum ReferenceImage {
  /// Preserve tall screenshots without allowing unbounded decoded bitmaps.
  static func decode(_ data: Data) -> UIImage? {
    guard data.count <= VisualFileImport.maximumImageBytes,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return decode(source)
  }

  static func decode(at url: URL, maximumBytes: Int = VisualFileImport.maximumImageBytes) -> UIImage? {
    guard url.isFileURL, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      bytes <= maximumBytes,
      let source = CGImageSourceCreateWithURL(
        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    return decode(source)
  }

  private static func decode(_ source: CGImageSource) -> UIImage? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Double,
      let height = properties[kCGImagePropertyPixelHeight] as? Double,
      let edge = maximumEdge(
        width: (5...8).contains((properties[kCGImagePropertyOrientation] as? Int) ?? 1)
          ? height : width,
        height: (5...8).contains((properties[kCGImagePropertyOrientation] as? Int) ?? 1)
          ? width : height),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: edge,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image, scale: 1, orientation: .up)
  }

  static func maximumEdge(width: Double, height: Double) -> Int? {
    guard width.isFinite, height.isFinite, width > 0, height > 0,
      (width * height).isFinite
    else { return nil }
    let scale = min(1, 4_096 / width, 12_000 / height, sqrt(16_000_000 / (width * height)))
    return max(1, Int((max(width, height) * scale).rounded(.down)))
  }
}

enum ScrollingReferenceError: LocalizedError {
  case invalid, tooLong
  var errorDescription: String? {
    switch self {
    case .invalid: return "Choose a readable image or a valid PDF page range."
    case .tooLong:
      return
        "Choose up to 20 PDF pages or a shorter reference. The scrolling canvas is limited to 24,000 pixels in height."
    }
  }
}

/// Bounded page images, not one enormous stitched bitmap. Playback draws only
/// pages intersecting the viewport and uses real finite pause/seek semantics.
final class ScrollingReference: Identifiable {
  let id = UUID()
  let name: String
  let pages: [UIImage]
  let pageRects: [CGRect]
  let travel: CGFloat
  static let viewport = CGSize(width: 960, height: 540)

  convenience init(images: [UIImage], name: String = "Image Reference") throws {
    try self.init(pageCount: images.count, name: name) { images[$0] }
  }

  /// Load/render/discard one source page at a time, including on early rejection.
  init(pageCount: Int, name: String, loadPage: (Int) throws -> UIImage) throws {
    guard (1...20).contains(pageCount) else { throw ScrollingReferenceError.tooLong }
    var y: CGFloat = 24
    var rects: [CGRect] = []
    var bounded: [UIImage] = []
    for index in 0..<pageCount {
      let raster: UIImage = try autoreleasepool {
        let image = try loadPage(index)
        guard image.size.width > 0, image.size.height > 0 else {
          throw ScrollingReferenceError.invalid
        }
        let height = image.size.height * 912 / image.size.width
        guard height.isFinite, y + height <= 24_000 else { throw ScrollingReferenceError.tooLong }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let raster = UIGraphicsImageRenderer(
          size: CGSize(width: 912, height: max(2, ceil(height))), format: format
        ).image { context in
          UIColor.white.setFill()
          context.fill(CGRect(x: 0, y: 0, width: 912, height: ceil(height)))
          image.draw(in: CGRect(x: 0, y: 0, width: 912, height: height))
        }
        rects.append(CGRect(x: 24, y: y, width: 912, height: height))
        y += height + 24
        return raster
      }
      bounded.append(raster)
    }
    self.pages = bounded
    pageRects = rects
    self.name = name
    travel = max(0, y - Self.viewport.height)
  }

  static func pdf(_ reference: PDFReference, first: Int, last: Int) throws -> ScrollingReference {
    guard first >= 1, last >= first, last <= reference.pageCount else {
      throw ScrollingReferenceError.invalid
    }
    guard last - first < 20 else { throw ScrollingReferenceError.tooLong }
    return try .init(pageCount: last - first + 1, name: "\(reference.name) · \(first)–\(last)") {
      try reference.image(pageIndex: first + $0 - 1, maximumEdge: 1_200)
    }
  }

  func duration(speed: Double) -> TimeInterval { max(1, Double(travel) / min(120, max(10, speed))) }
  func frame(elapsed: TimeInterval, speed: Double) -> UIImage {
    let offset = min(travel, max(0, CGFloat(elapsed * min(120, max(10, speed)))))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: Self.viewport, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: Self.viewport))
      for (image, rect) in zip(pages, pageRects) {
        let visible = rect.offsetBy(dx: 0, dy: -offset)
        if visible.intersects(CGRect(origin: .zero, size: Self.viewport)) {
          image.draw(in: visible)
        }
      }
    }
  }
}
