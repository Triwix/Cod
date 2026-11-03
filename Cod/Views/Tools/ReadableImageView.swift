import SwiftUI

enum RecognizedReferenceText {
  static func reflow(_ text: String) -> String {
    text.components(separatedBy: "\n\n").map { paragraph in
      paragraph.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct ReadableImageView: View {
  let image: UIImage
  var body: some View {
    FloatingTextView(originalImage: image, recognizeInitially: true)
  }
}
