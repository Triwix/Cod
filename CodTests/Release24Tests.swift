import AppIntents
import CoreVideo
import UIKit
import XCTest
@testable import Cod

final class Release24Tests: XCTestCase {
    func testTransparentDarkAndLightArtworkKeepContrastInTheVideo() throws {
        for color in [UIColor.black, .white] {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            let source = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
                color.setFill(); context.fill(CGRect(x: 8, y: 8, width: 16, height: 16))
            }
            let originalBytes = source.pngData()
            let frame = try XCTUnwrap(source.renderedForPiP(maximumEdge: 32))
            let pixels = try XCTUnwrap(frame.pixelBuffer())
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            let bytes = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            let center = 16 * CVPixelBufferGetBytesPerRow(pixels) + 16 * 4
            // BGRA: sample an originally transparent corner and opaque center.
            XCTAssertEqual(bytes[3], 255)
            XCTAssertEqual(bytes[center + 3], 255)
            XCTAssertGreaterThan(abs(Int(bytes[0]) - Int(bytes[center])), 230)
            XCTAssertEqual(source.pngData(), originalBytes)
        }
    }

    @MainActor
    func testExplicitCropIntentDeliversTheImageWithoutRequestingImmediateFloat() async throws {
        let inbox = IntentInbox.shared
        inbox.pendingImage = nil; inbox.pendingFloatImage = nil
        defer { inbox.pendingImage = nil; inbox.pendingFloatImage = nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 37, height: 19), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 37, height: 19))
        }
        let intent = CropWithCodIntent()
        intent.image = IntentFile(data: try XCTUnwrap(source.pngData()), filename: "fresh-screenshot.png", type: .png)
        _ = try await intent.perform()
        XCTAssertEqual(inbox.pendingImage?.pixelSize, source.pixelSize)
        XCTAssertNil(inbox.pendingFloatImage)
        XCTAssertTrue(CropWithCodIntent.openAppWhenRun)
    }
}
