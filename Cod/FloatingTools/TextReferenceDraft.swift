import UIKit

/// One editable source, whether it is floated as a card or a finite script.
struct TextReferenceDraft: Equatable {
  var configuration: FloatingToolConfiguration
  var teleprompterEnabled: Bool

  init(text: String = "", saved: SavedReference? = nil, teleprompter: Bool = false) {
    if let tool = saved?.tool, tool.kind == .teleprompter {
      configuration = tool
      if tool.usesSampleText { configuration.text = "" }
      teleprompterEnabled = true
    } else {
      configuration = .init(kind: .teleprompter, text: saved?.text?.text ?? text)
      if let card = saved?.text {
        configuration.fontSize = card.fontSize
        configuration.palette = card.palette
        configuration.customColors = card.colors
      }
      teleprompterEnabled = teleprompter
    }
  }

  var maximumCharacters: Int { teleprompterEnabled ? 20_000 : FloatingText.maximumCharacters }
  var sample: String {
    teleprompterEnabled ? FloatingToolConfiguration.exampleScript : FloatingText.example
  }
  var content: String {
    configuration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? sample : configuration.text
  }

  func prepared(for style: UIUserInterfaceStyle) -> FloatingToolConfiguration {
    var result = configuration
    result.interfaceStyle = style
    result.text = content
    result.usesSampleText =
      configuration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return result
  }

  func stillImage(for style: UIUserInterfaceStyle) throws -> UIImage {
    let config = prepared(for: style)
    return try FloatingText.render(
      content, fontSize: config.fontSize, palette: config.palette, colors: config.colors)
  }

  func saved(name: String, id: UUID, originalFilename: String?) -> SavedReference {
    if teleprompterEnabled {
      var config = configuration
      config.text = content
      config.usesSampleText =
        configuration.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      return .init(
        id: id, name: name, detail: "Teleprompter", tool: config, originalFilename: originalFilename
      )
    }
    return .init(
      id: id, name: name, detail: "Text card",
      text: .init(
        text: content, fontSize: configuration.fontSize, palette: configuration.palette,
        colors: configuration.customColors), originalFilename: originalFilename)
  }
}

struct PDFScrollRange: Hashable {
  let first: Int
  let last: Int
  init?(first: String, last: String, pageCount: Int) {
    guard let start = PDFPageSelection.index(first, count: pageCount),
      let end = PDFPageSelection.index(last, count: pageCount), start <= end
    else { return nil }
    self.first = start + 1
    self.last = end + 1
  }
}
