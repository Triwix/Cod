import CoreGraphics

/// The floating window's shape. iOS sizes a Picture in Picture window from
/// the aspect ratio of the video it plays, so a tool picks its shape by
/// rendering frames at that ratio. People still resize and move the window.
enum FloatWindowShape: String, CaseIterable, Identifiable, Codable {
  case wide, standard, square, tall, portrait

  var id: String { rawValue }

  var title: String {
    switch self {
    case .wide: return "Wide"
    case .standard: return "Standard"
    case .square: return "Square"
    case .tall: return "Tall"
    case .portrait: return "Portrait"
    }
  }

  var ratio: String {
    switch self {
    case .wide: return "16:9"
    case .standard: return "4:3"
    case .square: return "1:1"
    case .tall: return "3:4"
    case .portrait: return "9:16"
    }
  }

  /// The shape closest to a picture's own proportions, such as a PDF page.
  static func closest(to size: CGSize) -> FloatWindowShape {
    guard size.width > 0, size.height > 0 else { return .wide }
    let ratio = log(size.width / size.height)
    return allCases.min { abs(log($0.size.width / $0.size.height) - ratio) < abs(log($1.size.width / $1.size.height) - ratio) } ?? .wide
  }

  /// Render size in points (rendered at scale 1). Areas stay close to the
  /// original 960 × 540 so encoding cost and text sharpness are similar.
  var size: CGSize {
    switch self {
    case .wide: return CGSize(width: 960, height: 540)
    case .standard: return CGSize(width: 800, height: 600)
    case .square: return CGSize(width: 680, height: 680)
    case .tall: return CGSize(width: 600, height: 800)
    case .portrait: return CGSize(width: 540, height: 960)
    }
  }
}

/// A reading System Monitor can show. People turn each one on or off.
enum SystemMetric: String, CaseIterable, Identifiable, Codable {
  case battery, temperature, download, upload, connection, storage, memory, cpu, lowPower

  var id: String { rawValue }

  static let defaults: [SystemMetric] = [.battery, .temperature, .download, .upload]

  var title: String {
    switch self {
    case .battery: return "Battery"
    case .temperature: return "Temperature"
    case .download: return "Download"
    case .upload: return "Upload"
    case .connection: return "Connection"
    case .storage: return "Free Storage"
    case .memory: return "Memory"
    case .cpu: return "CPU"
    case .lowPower: return "Low Power Mode"
    }
  }

  /// Short label drawn in the floating window.
  var label: String {
    switch self {
    case .temperature: return "Temp"
    case .storage: return "Storage"
    case .lowPower: return "Low Power"
    default: return title
    }
  }

  var icon: String {
    switch self {
    case .battery: return "battery.75percent"
    case .temperature: return "thermometer.medium"
    case .download: return "arrow.down.circle"
    case .upload: return "arrow.up.circle"
    case .connection: return "wifi"
    case .storage: return "internaldrive"
    case .memory: return "memorychip"
    case .cpu: return "cpu"
    case .lowPower: return "battery.25percent"
    }
  }
}
