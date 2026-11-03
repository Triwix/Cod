import UIKit
import XCTest

@testable import Cod

final class MediaPerformance19Tests: XCTestCase {
  private func reference() throws -> PDFReference {
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData {
      context in
      for page in 1...12 {
        context.beginPage()
        ("Reference page \(page)" as NSString).draw(
          at: CGPoint(x: 30, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 40)])
      }
    }
    return try PDFReference(data: data)
  }

  func testMeasurePriorEagerPDFPreparationBaseline() throws {
    let pdf = try reference()
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      autoreleasepool {
        do {
          let pages = try (0..<12).map { try pdf.image(pageIndex: $0, maximumEdge: 1_200) }
          let result = try ScrollingReference(images: pages)
          XCTAssertEqual(result.pages.count, 12)
        } catch { XCTFail(error.localizedDescription) }
      }
    }
  }

  func testMeasureStreamedPDFPreparation() throws {
    let pdf = try reference()
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
      autoreleasepool {
        do {
          let result = try ScrollingReference.pdf(pdf, first: 1, last: 12)
          XCTAssertEqual(result.pages.count, 12)
        } catch { XCTFail(error.localizedDescription) }
      }
    }
  }
}
