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
