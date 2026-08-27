import CoreGraphics
import Foundation

/// A single captured snippet. The image bytes live on disk next to the index;
/// this struct is only the metadata that gets serialized into `index.json`.
struct Snap: Identifiable, Codable, Hashable {
    enum Origin: String, Codable {
        case screenshot
        case imported
        case pasted
        case shared
        case unknown

        var label: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .imported: return "Imported"
            case .pasted: return "Pasted"
            case .shared: return "Shared"
            case .unknown: return "Capture"
            }
        }

        var systemImage: String {
            switch self {
            case .screenshot: return "iphone.gen3"
            case .imported: return "photo"
            case .pasted: return "doc.on.clipboard"
            case .shared: return "square.and.arrow.up"
            case .unknown: return "square.dashed"
            }
        }
    }

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var pixelWidth: Int
    var pixelHeight: Int
    var origin: Origin = .unknown

    /// Cached OCR result, filled in lazily the first time text is requested.
    var recognizedText: String?
    /// Cached barcode/QR payloads found in the snippet.
    var barcodes: [String] = []

    var imageFilename: String { "\(id.uuidString).png" }
    var thumbnailFilename: String { "\(id.uuidString)-thumb.jpg" }

    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }

    var dimensionLabel: String { "\(pixelWidth) × \(pixelHeight)" }

    var hasText: Bool {
        guard let recognizedText else { return false }
        return !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
