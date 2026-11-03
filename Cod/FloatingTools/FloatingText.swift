import UIKit

enum FloatingPalette: String, CaseIterable, Identifiable, Codable {
    case system, dark, light, yellow
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var background: UIColor {
        switch self {
        case .system:
            return UIColor { $0.userInterfaceStyle == .dark ? FloatingPalette.dark.background : FloatingPalette.light.background }
        case .dark: return UIColor(white: 0.07, alpha: 1)
        case .light: return .white
        case .yellow: return UIColor(red: 1, green: 0.94, blue: 0.65, alpha: 1)
        }
    }
    var foreground: UIColor {
        if self == .system { return UIColor { $0.userInterfaceStyle == .dark ? .white : .black } }
        return self == .dark ? .white : .black
    }
    func colors(for style: UIUserInterfaceStyle) -> FloatingColors {
        let traits = UITraitCollection(userInterfaceStyle: style)
        return FloatingColors(background: background.resolvedColor(with: traits), foreground: foreground.resolvedColor(with: traits))
    }
}

struct FloatingColors: Equatable, Codable {
    var background: UIColor
    var foreground: UIColor

    private enum CodingKeys: String, CodingKey { case background, foreground }
    init(background: UIColor, foreground: UIColor) {
        self.background = background; self.foreground = foreground
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func color(_ key: CodingKeys) throws -> UIColor {
            let rgba = try values.decode([Double].self, forKey: key)
            guard rgba.count == 4, rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: values, debugDescription: "Invalid color")
            }
            return UIColor(red: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
        }
        background = try color(.background); foreground = try color(.foreground)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        func rgba(_ color: UIColor) -> [Double] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b, a].map(Double.init)
        }
        try values.encode(rgba(background), forKey: .background)
        try values.encode(rgba(foreground), forKey: .foreground)
    }
}

enum FloatingTextError: LocalizedError {
    case empty, tooLong
    var errorDescription: String? {
        switch self {
        case .empty: return "Type or paste some text first."
        case .tooLong: return "This text won't fit legibly. Shorten it, reduce the text size, or use Teleprompter for a longer script."
        }
    }
}

/// Shared with the extension; no app launching, clipboard polling or networking.
enum FloatingText {
    static let maximumCharacters = 2_000
    static let example = "Keep a useful note in view.\n\nA recipe, checklist, address or a few words to remember. Use the text editor below to write your own, or paste some text."

    static func content(_ draft: String, sample: String = example) -> String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sample : draft
    }

    static func sampleColors(_ colors: FloatingColors) -> FloatingColors {
        FloatingColors(background: colors.background, foreground: colors.foreground.withAlphaComponent(0.6))
    }

    static func render(_ text: String, fontSize: CGFloat = 44, palette: FloatingPalette = .system, colors: FloatingColors? = nil) throws -> UIImage {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw FloatingTextError.empty }
        guard text.count <= maximumCharacters else { throw FloatingTextError.tooLong }
        let font = UIFont.systemFont(ofSize: min(72, max(28, fontSize)), weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: colors?.foreground ?? palette.foreground, .paragraphStyle: paragraph,
        ])
        let width: CGFloat = 900
        let padding: CGFloat = 44
        let bounds = attributed.boundingRect(
            with: CGSize(width: width - padding * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        guard bounds.height <= 1_100 else { throw FloatingTextError.tooLong }
        let size = CGSize(width: width, height: max(240, ceil(bounds.height) + padding * 2))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            (colors?.background ?? palette.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            attributed.draw(with: CGRect(x: padding, y: padding, width: width - padding * 2, height: size.height - padding * 2),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }
}
