import UIKit
import XCTest
@testable import Cod

final class Release23Tests: XCTestCase {
    func testPiPRenderLimitsPrecisionAndSizeWithoutMutatingTheSource() throws {
        let original = try extendedImage()
        let bitmap = try XCTUnwrap(original.cgImage)
        let rotated = UIImage(cgImage: bitmap, scale: 2, orientation: .right)
        let result = try XCTUnwrap(rotated.renderedForPiP(maximumEdge: 40))
        let output = try XCTUnwrap(result.cgImage)
        XCTAssertEqual(output.bitsPerComponent, 8)
        XCTAssertLessThanOrEqual(output.bitsPerPixel, 32)
        XCTAssertLessThanOrEqual(max(output.width, output.height), 40)
        XCTAssertEqual(output.width % 2, 0)
        XCTAssertEqual(output.height % 2, 0)
        XCTAssertEqual(result.imageOrientation, .up)
        XCTAssertEqual(result.scale, 1)
        XCTAssertTrue(rotated.cgImage === bitmap)
        XCTAssertEqual(rotated.cgImage?.bitsPerComponent, 16)
        XCTAssertEqual(rotated.imageOrientation, .right)
        XCTAssertEqual(rotated.scale, 2)
    }

    func testSmallPiPImagesAreNotUpscaledToTheRenderLimit() throws {
        let source = try extendedImage()
        let output = try XCTUnwrap(source.renderedForPiP(maximumEdge: 1_200)?.cgImage)
        XCTAssertEqual(output.width, 80)
        XCTAssertEqual(output.height, 40)
    }

    func testThinImagesStillHaveValidH264Dimensions() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 4_000), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1, height: 4_000))
        }
        let output = try XCTUnwrap(source.renderedForPiP(maximumEdge: 1_200)?.cgImage)
        XCTAssertEqual(output.width, 2)
        XCTAssertEqual(output.height, 1_200)
    }

    func testInvalidRenderSizesAreRejected() throws {
        let source = try extendedImage()
        let invalidEdges: [CGFloat] = [0, 1, .nan, .infinity]
        for maximumEdge in invalidEdges {
            XCTAssertNil(source.renderedForPiP(maximumEdge: maximumEdge))
        }
        XCTAssertNil(UIImage().renderedForPiP(maximumEdge: 1_200))
    }

    func testOnlyTheDisposableThumbnailUsesTheRequestedStandardRange() throws {
        let source = try extendedImage()
        let thumb = source.fitted(within: CGSize(width: 20, height: 20), preferredRange: .standard)
        XCTAssertEqual(thumb.cgImage?.bitsPerComponent, 8)
        XCTAssertEqual(thumb.pixelSize, CGSize(width: 20, height: 10))
        let smallThumb = source.fitted(within: CGSize(width: 400, height: 400), preferredRange: .standard)
        XCTAssertEqual(smallThumb.cgImage?.bitsPerComponent, 8)
        XCTAssertEqual(smallThumb.pixelSize, source.pixelSize)
        XCTAssertEqual(source.cgImage?.bitsPerComponent, 16)
        XCTAssertTrue(source.normalizedUp() === source)
        XCTAssertTrue(source.fitted(within: CGSize(width: 1200, height: 1200)) === source)
    }

    func testSourceAlphaIsPreservedWhilePiPUsesAnOpaqueFrame() throws {
        let source = try extendedImage()
        let output = try XCTUnwrap(source.renderedForPiP(maximumEdge: 100)?.cgImage)
        XCTAssertEqual(source.cgImage?.alphaInfo, .premultipliedLast)
        XCTAssertTrue([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(output.alphaInfo))
    }

    private func extendedImage() throws -> UIImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40,
            bitsPerComponent: 16, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        let color = try XCTUnwrap(CGColor(colorSpace: space, components: [1.4, 0.2, 0.1, 0.5]))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        return UIImage(cgImage: try XCTUnwrap(context.makeImage()), scale: 1, orientation: .up)
    }
}
