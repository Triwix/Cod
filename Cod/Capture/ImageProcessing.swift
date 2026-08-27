import UIKit

extension UIImage {
    /// Size in real pixels, regardless of the image's `scale`.
    var pixelSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Redraws the image so its orientation is `.up` and its scale is 1.
    /// Everything downstream (cropping, Vision, PiP) is much simpler when
    /// pixel coordinates mean exactly one thing.
    func normalizedUp() -> UIImage {
        if imageOrientation == .up && scale == 1 { return self }
        let target = pixelSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Crops to a rect expressed in this image's pixel space (origin top-left).
    func cropped(toPixelRect rect: CGRect) -> UIImage? {
        let normalized = normalizedUp()
        guard let cgImage = normalized.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let cropped = cgImage.cropping(to: clamped)
        else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    /// Rounds the corners for pinned snippets so the floating card reads as a
    /// card rather than a torn-out rectangle.
    func withRoundedCorners(radius: CGFloat) -> UIImage {
        guard radius > 0 else { return self }
        let rect = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            draw(in: rect)
        }
    }
}

extension CGRect {
    /// Keeps `self` inside `bounds` without changing its size where possible.
    func clamped(to bounds: CGRect) -> CGRect {
        var rect = self
        rect.size.width = Swift.min(rect.width, bounds.width)
        rect.size.height = Swift.min(rect.height, bounds.height)
        rect.origin.x = Swift.min(Swift.max(rect.minX, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = Swift.min(Swift.max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return rect
    }

    /// Builds a rect from two opposite corners, in any drag direction.
    static func between(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: Swift.min(a.x, b.x),
            y: Swift.min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
