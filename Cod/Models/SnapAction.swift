import SwiftUI

/// The post-capture actions offered in the instant action bar.
/// Snapper 3 lets you disable and reorder these; so does Cod (see `AppSettings`).
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
    case upload

    var id: String { rawValue }

    static var availableCases: [SnapAction] {
        #if COD_PERSONAL
        return allCases
        #else
        return allCases.filter { $0 != .upload }
        #endif
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

    /// The order Snapper 3 ships with, roughly — with Float first, because
    /// hovering a snippet over other apps is the whole point.
    static let defaultOrder: [SnapAction] = [
        .float, .pin, .copyImage, .copyText, .save, .share, .qr, .translate, .annotate, .upload,
    ]

    static let defaultEnabled: Set<SnapAction> = [
        .float, .pin, .copyImage, .copyText, .save, .share, .qr,
    ]
}
