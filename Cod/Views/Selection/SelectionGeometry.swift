import CoreGraphics

/// Stable, deployment-safe key for a crop's integral pixel rectangle.
///
/// CGRect itself only conforms to Hashable on iOS 18+, while Cod supports
/// iOS 17. Two fractional selections that produce the same pixel crop should
/// also identify the same history entry.
struct PixelRectKey: Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(_ rect: CGRect) {
        let pixels = rect.integral
        x = Int(pixels.minX)
        y = Int(pixels.minY)
        width = Int(pixels.width)
        height = Int(pixels.height)
    }
}

/// Maps between the image's pixel space and the on-screen (view) space where
/// the image is drawn aspect-fit. The selection itself is always stored in
/// pixels, so the readout is exact and the crop is lossless.
struct SelectionGeometry: Equatable {
    var imageSize: CGSize
    var displayRect: CGRect

    var scale: CGFloat {
        guard imageSize.width > 0 else { return 1 }
        return displayRect.width / imageSize.width
    }

    var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    static func fit(imageSize: CGSize, in container: CGSize) -> SelectionGeometry {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return SelectionGeometry(
                imageSize: CGSize(width: 1, height: 1),
                displayRect: CGRect(origin: .zero, size: container)
            )
        }
        let ratio = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        let origin = CGPoint(
            x: ((container.width - size.width) / 2).rounded(),
            y: ((container.height - size.height) / 2).rounded()
        )
        return SelectionGeometry(imageSize: imageSize, displayRect: CGRect(origin: origin, size: size))
    }

    // MARK: - Pixels → view

    func viewRect(_ pixelRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + pixelRect.minX * scale,
            y: displayRect.minY + pixelRect.minY * scale,
            width: pixelRect.width * scale,
            height: pixelRect.height * scale
        )
    }

    func viewPoint(_ pixelPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: displayRect.minX + pixelPoint.x * scale,
            y: displayRect.minY + pixelPoint.y * scale
        )
    }

    // MARK: - View → pixels

    func pixelRect(_ viewRect: CGRect) -> CGRect {
        CGRect(
            x: (viewRect.minX - displayRect.minX) / scale,
            y: (viewRect.minY - displayRect.minY) / scale,
            width: viewRect.width / scale,
            height: viewRect.height / scale
        )
    }

    func pixelPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - displayRect.minX) / scale,
            y: (viewPoint.y - displayRect.minY) / scale
        )
    }
}

/// The eight drag handles around a selection.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: return true
        default: return false
        }
    }

    /// Unit position within the selection rect.
    var unitPoint: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: 0, y: 0.5)
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * unitPoint.x, y: rect.minY + rect.height * unitPoint.y)
    }

    /// Applies a pixel-space delta to the edges this handle owns.
    func resized(_ rect: CGRect, dx: CGFloat, dy: CGFloat) -> CGRect {
        var rect = rect
        switch self {
        case .topLeft:
            rect.origin.x += dx; rect.size.width -= dx
            rect.origin.y += dy; rect.size.height -= dy
        case .top:
            rect.origin.y += dy; rect.size.height -= dy
        case .topRight:
            rect.size.width += dx
            rect.origin.y += dy; rect.size.height -= dy
        case .right:
            rect.size.width += dx
        case .bottomRight:
            rect.size.width += dx; rect.size.height += dy
        case .bottom:
            rect.size.height += dy
        case .bottomLeft:
            rect.origin.x += dx; rect.size.width -= dx
            rect.size.height += dy
        case .left:
            rect.origin.x += dx; rect.size.width -= dx
        }
        return rect.standardized
    }
}
