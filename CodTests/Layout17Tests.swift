import UIKit
import XCTest

@testable import Cod

final class Layout17Tests: XCTestCase {
  func testTextAndPrompterShareSourceAndAppearanceAcrossModeChanges() throws {
    var draft = TextReferenceDraft(text: "Gate 7 at 14:30")
    draft.configuration.palette = .yellow
    draft.configuration.customColors = .init(background: .blue, foreground: .white)
    draft.configuration.fontSize = 60
    draft.configuration.readingGuide = true
    draft.configuration.targetReadingDuration = 180
    let original = draft.configuration
    draft.teleprompterEnabled = true
    XCTAssertEqual(draft.content, "Gate 7 at 14:30")
    XCTAssertEqual(draft.configuration, original)
    XCTAssertEqual(draft.maximumCharacters, 20_000)
    draft.teleprompterEnabled = false
    XCTAssertEqual(draft.configuration, original)
    XCTAssertEqual(draft.maximumCharacters, 2_000)
    XCTAssertNoThrow(try draft.stillImage(for: .dark))
  }

  func testSwitchingLongScriptToStillTextDoesNotTruncateIt() {
    var draft = TextReferenceDraft(text: String(repeating: "word ", count: 600), teleprompter: true)
    let original = draft.configuration.text
    XCTAssertNoThrow(try draft.prepared(for: .light).validate())
    draft.teleprompterEnabled = false
    XCTAssertThrowsError(try draft.stillImage(for: .light))
    XCTAssertEqual(draft.configuration.text, original)
    draft.teleprompterEnabled = true
    XCTAssertEqual(draft.content, original)
  }

  func testSavedCardCanBecomeAScriptAndBackWithTheSameIdentifier() throws {
    let id = UUID()
    let card = SavedReference(
      id: id, name: "Directions", detail: "Text card",
      text: .init(text: "Turn left", fontSize: 56, palette: .yellow),
      originalFilename: "original.png")
    var draft = TextReferenceDraft(saved: card)
    XCTAssertFalse(draft.teleprompterEnabled)
    draft.teleprompterEnabled = true
    draft.configuration.prompterCountdownSeconds = 8
    let script = draft.saved(name: card.name, id: id, originalFilename: card.originalFilename)
    XCTAssertEqual(script.id, id)
    XCTAssertNil(script.text)
    XCTAssertEqual(script.tool?.text, "Turn left")
    XCTAssertEqual(script.tool?.fontSize, 56)
    XCTAssertEqual(script.tool?.palette, .yellow)
    XCTAssertEqual(script.originalFilename, "original.png")
    var reopened = TextReferenceDraft(saved: script)
    XCTAssertTrue(reopened.teleprompterEnabled)
    XCTAssertEqual(reopened.configuration.prompterCountdownSeconds, 8)
    reopened.teleprompterEnabled = false
    let restored = reopened.saved(
      name: card.name, id: id, originalFilename: script.originalFilename)
    XCTAssertNil(restored.tool)
    XCTAssertEqual(restored.text?.text, card.text?.text)
    XCTAssertEqual(restored.text?.palette, .yellow)
    XCTAssertEqual(restored.id, id)
  }

  func testSavedSampleScriptRemainsAPlaceholderNotAnEditableDraft() {
    let draft = TextReferenceDraft(teleprompter: true)
    let saved = draft.saved(name: "Example", id: UUID(), originalFilename: nil)
    XCTAssertTrue(saved.tool?.usesSampleText == true)
    let reopened = TextReferenceDraft(saved: saved)
    XCTAssertTrue(reopened.configuration.text.isEmpty)
    XCTAssertEqual(reopened.content, FloatingToolConfiguration.exampleScript)
  }

  @MainActor func testStillAndScriptUseTheirOwnValidationWithoutMutatingTheEditor() throws {
    var draft = TextReferenceDraft(text: "  \n")
    XCTAssertTrue(draft.prepared(for: .dark).usesSampleText)
    XCTAssertEqual(draft.prepared(for: .dark).interfaceStyle, .dark)
    XCTAssertNoThrow(try draft.stillImage(for: .light))
    draft.teleprompterEnabled = true
    XCTAssertTrue(draft.prepared(for: .light).usesSampleText)
    XCTAssertEqual(draft.configuration.text, "  \n")
    draft.configuration.prompterCountdownEnabled = true
    draft.configuration.prompterCountdownSeconds = 7
    draft.configuration.targetReadingDuration = 120
    let session = FloatingToolSession(configuration: draft.prepared(for: .light))
    XCTAssertEqual(session.playbackDuration, 127)
  }

  func testInlinePDFRangeValidation() {
    XCTAssertEqual(
      PDFScrollRange(first: " 2 ", last: "5", pageCount: 8),
      PDFScrollRange(first: "2", last: "5", pageCount: 8))
    XCTAssertEqual(PDFScrollRange(first: "1", last: "1", pageCount: 2)?.first, 1)
    for value in [("0", "1"), ("2", "1"), ("1", "3"), ("", "2"), ("1", "a")] {
      XCTAssertNil(PDFScrollRange(first: value.0, last: value.1, pageCount: 2))
    }
  }
}
