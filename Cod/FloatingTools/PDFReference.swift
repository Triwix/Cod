import PDFKit
import UIKit

enum PDFPageSelection {
  static func index(_ input: String, count: Int) -> Int? {
    guard count > 0, let number = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
      (1...count).contains(number)
    else { return nil }
    return number - 1
  }
}

enum PDFReferenceError: LocalizedError {
  case tooLarge, unreadable, locked, invalidPage
  var errorDescription: String? {
    switch self {
    case .tooLarge: return "Choose a PDF smaller than 40 MB."
    case .unreadable: return "Cod couldn't read that PDF. Try exporting a fresh copy."
    case .locked: return "Unlock this PDF in Files or Preview and share an unlocked copy."
    case .invalidPage: return "That page isn't in this PDF."
    }
  }
}

/// Each reference owns its PDFKit document. Render one bounded page at a time.
final class PDFReference: Identifiable {
  static let maximumBytes = 40 * 1_024 * 1_024
  let id = UUID()
  let document: PDFDocument
  let name: String
  var pageCount: Int { document.pageCount }

  init(data: Data, name: String = "PDF") throws {
    guard data.count <= Self.maximumBytes else { throw PDFReferenceError.tooLarge }
    guard let document = PDFDocument(data: data) else { throw PDFReferenceError.unreadable }
    guard !document.isLocked else { throw PDFReferenceError.locked }
    guard document.pageCount > 0 else { throw PDFReferenceError.unreadable }
    self.document = document
    self.name = name
  }

  convenience init(url: URL) throws {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let bytes = values.fileSize,
      bytes <= Self.maximumBytes
    else { throw PDFReferenceError.tooLarge }
    try self.init(
      data: Data(contentsOf: url, options: .mappedIfSafe),
      name: url.deletingPathExtension().lastPathComponent)
  }

  func image(pageIndex: Int, maximumEdge: CGFloat = 1_600) throws -> UIImage {
    guard pageIndex >= 0, pageIndex < pageCount,
      let page = document.page(at: pageIndex), let cgPage = page.pageRef
    else { throw PDFReferenceError.invalidPage }
    let box = cgPage.getBoxRect(.cropBox)
    guard box.width > 0, box.height > 0, box.width.isFinite, box.height.isFinite else {
      throw PDFReferenceError.unreadable
    }
    let sideways = abs(cgPage.rotationAngle % 180) == 90
    let original = sideways ? CGSize(width: box.height, height: box.width) : box.size
    let edge = min(2_048, max(2, maximumEdge))
    let scale = edge / max(original.width, original.height)
    let size = CGSize(
      width: max(2, (original.width * scale).rounded()),
      height: max(2, (original.height * scale).rounded()))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
      UIColor.white.setFill()
      renderer.fill(CGRect(origin: .zero, size: size))
      let context = renderer.cgContext
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1, y: -1)
      // CGPDFPage's fitting transform doesn't upscale a small page to
      // fill a larger raster. Apply the raster scale ourselves, then
      // use its transform only for crop-box origin and page rotation.
      context.scaleBy(x: size.width / original.width, y: size.height / original.height)
      context.concatenate(
        cgPage.getDrawingTransform(
          .cropBox, rect: CGRect(origin: .zero, size: original), rotate: 0,
          preserveAspectRatio: true))
      context.drawPDFPage(cgPage)
    }
  }
}
