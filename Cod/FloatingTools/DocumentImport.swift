import UIKit
import UniformTypeIdentifiers
import WebKit

/// Office and text documents. Word, PowerPoint, Excel and iWork files are
/// laid out by WebKit (the same viewer Files uses) and printed to PDF pages,
/// so they float like any PDF: one page, Flip Pages or Auto-scroll. Plain
/// text, Markdown and RTF become editable text for a card or teleprompter.
enum DocumentImport {
  static let maximumBytes = 40 * 1_024 * 1_024
  static let maximumTextCharacters = 100_000

  /// By file extension, so the system's own type for each format is used
  /// (iWork types have different identifiers across OS versions).
  static let officeTypes: [UTType] = ["docx", "doc", "pptx", "ppt", "xlsx", "xls", "pages", "key", "numbers"]
    .compactMap { UTType(filenameExtension: $0) }

  static let textTypes: [UTType] = [.plainText, .rtf, .rtfd, .flatRTFD]
    + ["net.daringfireball.markdown"].compactMap(UTType.init)

  enum ImportError: LocalizedError, Equatable {
    case tooLarge, unreadable, empty
    var errorDescription: String? {
      switch self {
      case .tooLarge: return "Choose a document smaller than 40 MB."
      case .unreadable: return "Cod couldn't lay out this document. Export it as a PDF and choose that instead."
      case .empty: return "This document has no text to float."
      }
    }
  }

  static func isOffice(_ type: UTType) -> Bool { officeTypes.contains { type.conforms(to: $0) } }
  static func isText(_ type: UTType) -> Bool {
    // Plain text conforms to many source-code types; all read the same way.
    textTypes.contains { type.conforms(to: $0) }
  }

  // MARK: Text

  /// Plain text from a text, Markdown or RTF file, trimmed to a sensible length.
  static func text(at url: URL, type: UTType) throws -> String {
    let raw: String
    if type.conforms(to: .rtf) || type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD) {
      let documentType: NSAttributedString.DocumentType = type.conforms(to: .rtf) ? .rtf : .rtfd
      raw = try NSAttributedString(url: url, options: [.documentType: documentType], documentAttributes: nil).string
    } else {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      guard let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        ?? String(data: data, encoding: .isoLatin1)
      else { throw ImportError.unreadable }
      raw = isMarkdown(type) ? plainText(fromMarkdown: decoded) : decoded
    }
    let text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw ImportError.empty }
    return String(text.prefix(maximumTextCharacters))
  }

  static func isMarkdown(_ type: UTType) -> Bool {
    UTType("net.daringfireball.markdown").map { type.conforms(to: $0) } ?? false
  }

  /// Markdown read for display: formatting marks removed, paragraphs kept.
  static func plainText(fromMarkdown markdown: String) -> String {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
      var text = String(line)
      // Headings, quotes and list bullets are block syntax; drop their marks.
      while let first = text.first, "#>".contains(first) { text.removeFirst() }
      if let range = text.range(of: #"^\s*([-*+]|\d+\.)\s+"#, options: .regularExpression) {
        text.replaceSubrange(range, with: "• ")
      }
      text = text.trimmingCharacters(in: .whitespaces)
      return (try? AttributedString(markdown: text, options: options)).map { String($0.characters) } ?? text
    }.joined(separator: "\n")
  }

  // MARK: Office

  /// Lays out an Office or iWork document and prints it to PDF pages.
  @MainActor static func pdf(from url: URL) async throws -> PDFReference {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maximumBytes else { throw ImportError.tooLarge }
    // WebKit reads from its own process, so give it a private copy.
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Cod Documents", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let copy = folder.appendingPathComponent(url.lastPathComponent)
    try FileManager.default.copyItem(at: url, to: copy)
    let data = try await DocumentPrinter().printedPDF(of: copy)
    let name = url.deletingPathExtension().lastPathComponent
    do { return try PDFReference(data: data, name: name.isEmpty ? "Document" : name) }
    catch { throw ImportError.unreadable }
  }
}

/// US Letter pages with half-inch margins. Overriding the page rectangles is
/// how UIPrintPageRenderer is meant to be given a page size outside printing.
private final class DocumentPageRenderer: UIPrintPageRenderer {
  static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
  override var paperRect: CGRect { Self.page }
  override var printableRect: CGRect { Self.page.insetBy(dx: 36, dy: 36) }
}

@MainActor
private final class DocumentPrinter: NSObject, WKNavigationDelegate {
  private var webView: WKWebView?
  private var continuation: CheckedContinuation<Void, Error>?

  func printedPDF(of file: URL) async throws -> Data {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: configuration)
    view.navigationDelegate = self
    webView = view
    defer { webView = nil }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      self.continuation = continuation
      view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
      Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        self?.finish(DocumentImport.ImportError.unreadable)
      }
    }
    // Give the document viewer a moment to finish its own layout.
    try await Task.sleep(nanoseconds: 600_000_000)
    let renderer = DocumentPageRenderer()
    renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
    let pages = renderer.numberOfPages
    guard pages > 0 else { throw DocumentImport.ImportError.unreadable }
    let data = NSMutableData()
    UIGraphicsBeginPDFContextToData(data, DocumentPageRenderer.page, nil)
    renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
    for index in 0..<pages {
      UIGraphicsBeginPDFPage()
      renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
    }
    UIGraphicsEndPDFContext()
    return data as Data
  }

  private func finish(_ error: Error?) {
    guard let continuation else { return }
    self.continuation = nil
    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
  }

  nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in self.finish(nil) }
  }

  nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    Task { @MainActor in self.finish(DocumentImport.ImportError.unreadable) }
  }

  nonisolated func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
  ) {
    Task { @MainActor in self.finish(DocumentImport.ImportError.unreadable) }
  }
}
