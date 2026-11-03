import XCTest

@testable import Cod

final class Polish13Tests: XCTestCase {
  func testTextExampleDirectsPeopleToTheEditorInsteadOfThePreview() throws {
    XCTAssertTrue(FloatingText.example.contains("text editor below"))
    XCTAssertFalse(FloatingText.example.contains("Tap here"))
    XCTAssertEqual(FloatingText.content("\n  "), FloatingText.example)
    XCTAssertEqual(FloatingText.content("My note"), "My note")
    for palette in FloatingPalette.allCases {
      XCTAssertNoThrow(try FloatingText.render(FloatingText.example, palette: palette))
    }
  }
}
