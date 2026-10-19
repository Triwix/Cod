import SwiftUI

/// The post-capture actions offered in the instant action bar.
/// Actions can be disabled and reordered in Settings.
enum SnapAction: String, Codable, CaseIterable, Identifiable {
    case float
    case pin
    case copyImage
    case copyText
    case save
    case share
    case qr
    case translate
    case annotate
    // Decode older saved preferences without resetting the whole action list.
    // This retired value is filtered out before anything reaches the UI.
    case upload

    var id: String { rawValue }

    static var availableCases: [SnapAction] {
        return allCases.filter { $0 != .upload }
    }

    var title: String {
        switch self {
        case .float: return "Float"
        case .pin: return "Pin"
        case .copyImage: return "Copy"
        case .copyText: return "Copy Text"
        case .save: return "Save"
        case .share: return "Share"
        case .qr: return "Scan Code"
        case .translate: return "Translate"
        case .annotate: return "Edit"
        case .upload: return "Upload"
        }
    }

    /// Longer form used in Settings, where the row has room to explain itself.
    var subtitle: String {
        switch self {
        case .float: return "Hover the snippet over every other app"
        case .pin: return "Float the snippet above Cod itself"
        case .copyImage: return "Put the cropped image on the clipboard"
        case .copyText: return "Run OCR and copy the recognized text"
        case .save: return "Write to Photos"
        case .share: return "Open the system share sheet"
        case .qr: return "Read QR codes and barcodes in the crop"
        case .translate: return "Recognize text, then translate it"
        case .annotate: return "Draw, highlight and mark up"
        case .upload: return "Upload to Imgur and copy the link"
        }
    }

    var systemImage: String {
        switch self {
        case .float: return "pip.enter"
        case .pin: return "pin.fill"
        case .copyImage: return "doc.on.doc"
        case .copyText: return "text.viewfinder"
        case .save: return "square.and.arrow.down"
        case .share: return "square.and.arrow.up"
        case .qr: return "qrcode.viewfinder"
        case .translate: return "character.bubble"
        case .annotate: return "pencil.tip.crop.circle"
        case .upload: return "arrow.up.circle"
        }
    }

    var tint: Color {
        switch self {
        case .float: return .red
        case .pin: return .orange
        case .copyImage: return .blue
        case .copyText: return .teal
        case .save: return .green
        case .share: return .indigo
        case .qr: return .purple
        case .translate: return .pink
        case .annotate: return .yellow
        case .upload: return .cyan
        }
    }

    /// Floating is the primary action. Retired actions aren't in new defaults.
    static let defaultOrder: [SnapAction] = [
        .float, .pin, .copyImage, .copyText, .save, .share, .qr, .translate, .annotate,
    ]

    static let defaultEnabled: Set<SnapAction> = [
        .float, .pin, .copyImage, .copyText, .save, .share, .qr,
    ]
}
