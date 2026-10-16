import CoreVideo
import ImageIO
import UIKit

extension UIImage {
    static func decodedImage(data: Data, maximumEdge: Int = 2_048) -> UIImage? {
        guard maximumEdge > 0, data.count <= SharedImageInbox.maximumImageBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    static func decodedImage(at url: URL, maximumEdge: Int = 2_048) -> UIImage? {
        guard maximumEdge > 0 else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumEdge,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// Typed UIImage fallback for providers whose file is a UIKit archive.
    /// Limit the source bitmap too: drawing a huge archived object in a share
    /// extension is not as memory-safe as ImageIO thumbnail decoding.
    func boundedShareImage(maximumEdge: CGFloat = 2_048) -> UIImage? {
        let pixels = pixelSize
        guard maximumEdge > 0, pixels.width > 0, pixels.height > 0,
              pixels.width.isFinite, pixels.height.isFinite,
              pixels.width * pixels.height <= 16_000_000 else { return nil }
        if imageOrientation == .up, scale == 1, max(pixels.width, pixels.height) <= maximumEdge { return self }
        let ratio = min(1, maximumEdge / max(pixels.width, pixels.height))
        let target = CGSize(width: max(1, (pixels.width * ratio).rounded()), height: max(1, (pixels.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
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

    /// Aspect-fit resize used by thumbnails and the Picture in Picture encoder.
    /// Never upscales.
    func fitted(within bounds: CGSize) -> UIImage {
        let ratio = min(bounds.width / size.width, bounds.height / size.height, 1)
        guard ratio < 1 else { return self }
        let target = CGSize(width: max(1, (size.width * ratio).rounded()), height: max(1, (size.height * ratio).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    func pixelBuffer() -> CVPixelBuffer? {
        guard let cgImage else { return nil }
        let width = max(2, cgImage.width - (cgImage.width % 2))
        let height = max(2, cgImage.height - (cgImage.height % 2))

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            attributes as CFDictionary, &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
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
