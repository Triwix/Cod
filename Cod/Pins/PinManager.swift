import SwiftUI

struct Pin: Identifiable, Equatable {
    let id = UUID()
    var image: UIImage
    /// Centre in screen coordinates.
    var center: CGPoint
    /// Rendered width in points; height follows the image's aspect ratio.
    var width: CGFloat
    var opacity: Double = 1
    var isCollapsed: Bool = false
    var recognizedText: String?
    var createdAt: Date = Date()

    var aspect: CGFloat {
        let size = image.size
        guard size.height > 0 else { return 1 }
        return size.width / size.height
    }

    var height: CGFloat { width / max(aspect, 0.05) }

    static func == (lhs: Pin, rhs: Pin) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class PinManager: ObservableObject {
    static let shared = PinManager()

    @Published var pins: [Pin] = []
    /// Which pin is drawn on top / has chrome visible.
    @Published var focusedID: Pin.ID?

    private let minWidth: CGFloat = 60
    private let maxWidth: CGFloat = 1200

    var isEmpty: Bool { pins.isEmpty }

    func add(image: UIImage, near point: CGPoint? = nil, recognizedText: String? = nil) {
        let screen = UIScreen.main.bounds
        // Fit new pins to a comfortable fraction of the screen, never wider
        // than their natural size.
        let naturalWidth = image.size.width
        let width = min(max(naturalWidth, minWidth), screen.width * 0.62)

        // Cascade so several pins don't stack perfectly on top of each other.
        let offset = CGFloat(pins.count % 6) * 22
        let center = point ?? CGPoint(
            x: screen.width / 2 + offset - 55,
            y: screen.height * 0.34 + offset
        )

        let pin = Pin(
            image: image,
            center: center,
            width: width,
            opacity: AppSettings.shared.pinOpacity,
            recognizedText: recognizedText
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            pins.append(pin)
            focusedID = pin.id
        }
        Haptics.success()
    }

    func update(_ pin: Pin) {
        guard let index = pins.firstIndex(where: { $0.id == pin.id }) else { return }
        pins[index] = pin
    }

    func setWidth(_ width: CGFloat, for id: Pin.ID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].width = min(max(width, minWidth), maxWidth)
    }

    func setCenter(_ center: CGPoint, for id: Pin.ID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].center = center
    }

    func bringToFront(_ id: Pin.ID) {
        guard let index = pins.firstIndex(where: { $0.id == id }), index != pins.count - 1 else {
            focusedID = id
            return
        }
        let pin = pins.remove(at: index)
        pins.append(pin)
        focusedID = id
    }

    func remove(_ id: Pin.ID) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            pins.removeAll { $0.id == id }
            if focusedID == id { focusedID = pins.last?.id }
        }
        Haptics.tick()
    }

    func removeAll() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            pins.removeAll()
            focusedID = nil
        }
        Haptics.tick()
    }

    func toggleCollapsed(_ id: Pin.ID) {
        guard let index = pins.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            pins[index].isCollapsed.toggle()
        }
    }
}
