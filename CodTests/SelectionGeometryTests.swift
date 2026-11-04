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

    func testAccessibleEdgeAdjustmentsKeepOppositeEdgesAndStayInTheImage() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let crop = CGRect(x: 40, y: 30, width: 180, height: 120)
        XCTAssertEqual(SelectionEdge.left.adjusting(crop, to: 50, in: bounds), CGRect(x: 50, y: 30, width: 170, height: 120))
        XCTAssertEqual(SelectionEdge.top.adjusting(crop, to: 50, in: bounds), CGRect(x: 40, y: 50, width: 180, height: 100))
        XCTAssertEqual(SelectionEdge.right.adjusting(crop, to: 200, in: bounds), CGRect(x: 40, y: 30, width: 160, height: 120))
        XCTAssertEqual(SelectionEdge.bottom.adjusting(crop, to: 130, in: bounds), CGRect(x: 40, y: 30, width: 180, height: 100))
        for edge in SelectionEdge.allCases {
            for value: CGFloat in [-10_000, 0, 75.6, 10_000] {
                let result = edge.adjusting(crop, to: value, in: bounds)
                XCTAssertTrue(bounds.contains(result))
                XCTAssertGreaterThanOrEqual(result.width, 1)
                XCTAssertGreaterThanOrEqual(result.height, 1)
                XCTAssertEqual(edge.value(in: result), edge.value(in: result).rounded())
            }
            XCTAssertEqual(edge.adjusting(crop, to: .nan, in: bounds), crop)
        }
    }

    func testAccessibleEdgesHandleSinglePixelImagesAndFractionalCrops() {
        let tiny = CGRect(x: 0, y: 0, width: 1, height: 1)
        for edge in SelectionEdge.allCases {
            XCTAssertEqual(edge.adjusting(tiny, to: 5, in: tiny), tiny)
        }
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let fractional = CGRect(x: 40.4, y: 30.6, width: 180.2, height: 120.3)
        for edge in SelectionEdge.allCases {
            for value: CGFloat in [-1_000, 100_000] {
                let result = edge.adjusting(fractional, to: value, in: bounds)
                XCTAssertTrue(bounds.contains(result))
                XCTAssertGreaterThanOrEqual(result.width, 1)
                XCTAssertGreaterThanOrEqual(result.height, 1)
            }
        }
    }
}
