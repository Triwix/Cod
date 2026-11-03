import CoreGraphics
import XCTest
@testable import Cod

final class SelectionGeometryTests: XCTestCase {
    func testAspectFitRoundTripsBetweenPixelsAndViewSpace() {
        let geometry = SelectionGeometry.fit(
            imageSize: CGSize(width: 1200, height: 2400),
            in: CGSize(width: 390, height: 844)
        )
        let pixels = CGRect(x: 123, y: 456, width: 321, height: 654)

        let roundTrip = geometry.pixelRect(geometry.viewRect(pixels))

        XCTAssertEqual(roundTrip.minX, pixels.minX, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minY, pixels.minY, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, pixels.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, pixels.height, accuracy: 0.001)
    }

    func testPixelRectKeyUsesTheIntegralOutputCrop() {
        let first = PixelRectKey(CGRect(x: 0.1, y: 1.1, width: 9.2, height: 8.2))
        let second = PixelRectKey(CGRect(x: 0.2, y: 1.2, width: 9.0, height: 8.0))

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.width, 10)
        XCTAssertEqual(first.height, 9)
    }

    func testZoomedAndPannedCropRoundTripsInOriginalPixels() {
        let size = CGSize(width: 1200, height: 1600)
        let container = CGSize(width: 390, height: 844)
        let base = SelectionGeometry.fit(imageSize: size, in: container)
        let zoomed = SelectionGeometry.fit(imageSize: size, in: container, zoom: 3, pan: CGSize(width: 70, height: -80))
        XCTAssertEqual(zoomed.scale, base.scale * 3, accuracy: 0.0001)
        let pixels = CGRect(x: 123, y: 456, width: 321, height: 654)
        let roundTrip = zoomed.pixelRect(zoomed.viewRect(pixels))
        XCTAssertEqual(roundTrip.minX, pixels.minX, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minY, pixels.minY, accuracy: 0.001)
        XCTAssertEqual(roundTrip.width, pixels.width, accuracy: 0.001)
        XCTAssertEqual(roundTrip.height, pixels.height, accuracy: 0.001)
    }

    func testCropZoomAndPanAreBoundedWithoutBlankOverscroll() {
        let size = CGSize(width: 1200, height: 1600)
        let container = CGSize(width: 390, height: 844)
        let maxZoom = SelectionGeometry.fit(imageSize: size, in: container, zoom: 999, pan: .init(width: 999_999, height: -999_999))
        let base = SelectionGeometry.fit(imageSize: size, in: container)
        XCTAssertEqual(maxZoom.scale, base.scale * 6, accuracy: 0.001)
        XCTAssertEqual(maxZoom.displayRect.minX, 0, accuracy: 1)
        XCTAssertEqual(maxZoom.displayRect.maxY, container.height, accuracy: 1)
        let invalid = SelectionGeometry.fit(imageSize: size, in: container, zoom: CGFloat.nan, pan: .init(width: CGFloat.infinity, height: CGFloat.nan))
        XCTAssertEqual(invalid, base)
    }

    func testCornerResizeStandardizesWhenDraggedPastOppositeCorner() {
        let original = CGRect(x: 20, y: 30, width: 80, height: 60)

        let resized = SelectionHandle.topLeft.resized(
            original,
            dx: 100,
            dy: 90
        )

        XCTAssertEqual(resized, CGRect(x: 100, y: 90, width: 20, height: 30))
    }
}
