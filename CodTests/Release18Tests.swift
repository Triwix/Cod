import UIKit
import XCTest

@testable import Cod

final class Release18Tests: XCTestCase {
  func testIntroductionCompletionPersistsWithoutChangingPermissionsOrPreferences() {
    let suite = "Cod.Introduction.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    XCTAssertFalse(settings.hasCompletedIntroduction)
    XCTAssertFalse(settings.saveToDedicatedAlbum)
    let notifications = settings.useFloatNotification
    settings.hasCompletedIntroduction = true
    let restored = AppSettings(defaults: defaults)
    XCTAssertTrue(restored.hasCompletedIntroduction)
    XCTAssertEqual(restored.useFloatNotification, notifications)
    XCTAssertFalse(restored.saveToDedicatedAlbum)
    XCTAssertFalse(
      restored.hasDismissedFloatSetupTip, "A tour doesn't claim a Shortcut is installed")
  }

  func testCancelledImportCannotDeliverOrClearANewerImport() {
    var state = MediaImportState()
    let first = state.begin()
    state.cancel()
    XCTAssertFalse(state.isLoading)
    XCTAssertFalse(state.accepts(first))
    let second = state.begin()
    state.fail(VisualFileImport.ImportError.unavailable, for: first)
    state.finish(first)
    XCTAssertTrue(state.accepts(second))
    XCTAssertNil(state.failure)
    state.finish(second)
    XCTAssertFalse(state.isLoading)
  }

  func testNewSelectionInvalidatesOldResultAndClearsOldFailure() {
    var state = MediaImportState()
    let first = state.begin()
    state.fail(VisualFileImport.ImportError.unreadableImage, for: first)
    state.finish(first)
    XCTAssertNotNil(state.failure)
    let second = state.begin()
    XCTAssertNil(state.failure)
    XCTAssertFalse(state.accepts(first))
    XCTAssertTrue(state.accepts(second))
  }

  func testImportFailureStaysAfterLoadingUntilExplicitlyDismissed() {
    var state = MediaImportState()
    let request = state.begin()
    state.fail(VisualFileImport.ImportError.unavailable, for: request)
    state.finish(request)
    XCTAssertFalse(state.isLoading)
    XCTAssertTrue(state.failure?.contains("downloading") == true)
    state.dismissFailure()
    XCTAssertNil(state.failure)
  }

  func testPickerAndTaskCancellationAreNotFailures() {
    for error in [
      CancellationError() as Error,
      NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError),
      NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled),
    ] {
      XCTAssertNil(ImportRecovery.message(for: error))
      var state = MediaImportState()
      state.report(error)
      XCTAssertNil(state.failure)
    }
  }

  func testMissingFileAccessAndCloudErrorsExplainRecovery() {
    XCTAssertTrue(
      ImportRecovery.message(
        for: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))?.contains(
          "Choose it again") == true)
    XCTAssertTrue(
      ImportRecovery.message(
        for: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError))?.contains(
          "current location") == true)
    XCTAssertTrue(
      ImportRecovery.message(for: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))?
        .contains("let it download") == true)
    XCTAssertEqual(
      ImportRecovery.message(for: PDFReferenceError.locked),
      PDFReferenceError.locked.localizedDescription)
  }

  func testMissingCorruptAndOversizedImagesHaveDistinctErrors() {
    XCTAssertThrowsError(try VisualFileImport.image(from: nil)) { error in
      XCTAssertEqual(error as? VisualFileImport.ImportError, .unavailable)
    }
    for data in [Data(), Data("not an image".utf8)] {
      XCTAssertThrowsError(try VisualFileImport.image(from: data)) { error in
        XCTAssertEqual(error as? VisualFileImport.ImportError, .unreadableImage)
      }
    }
    XCTAssertThrowsError(
      try VisualFileImport.image(from: Data(count: VisualFileImport.maximumImageBytes + 1))
    ) { error in
      XCTAssertEqual(error as? VisualFileImport.ImportError, .imageTooLarge)
    }
  }

  @MainActor func testFileImportRejectsDirectoriesAndUnsupportedFilesWithoutDeletingThem()
    async throws
  {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let text = folder.appendingPathComponent("reference.txt")
    try Data("Reference".utf8).write(to: text)
    for url in [folder, text, URL(string: "https://example.com/photo.png")!] {
      do {
        _ = try await VisualFileImport.open(url)
        XCTFail("Unsupported input accepted")
      } catch { XCTAssertEqual(error as? VisualFileImport.ImportError, .unsupported) }
    }
    XCTAssertEqual(try String(contentsOf: text), "Reference")
  }

  @MainActor func testCorruptPDFAndImageFailThenValidImageImportsWithoutChangingOriginal()
    async throws
  {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    for ext in ["pdf", "png"] {
      let url = folder.appendingPathComponent("bad.\(ext)")
      let original = Data("broken content".utf8)
      try original.write(to: url)
      do {
        _ = try await VisualFileImport.open(url)
        XCTFail("Corrupt file accepted")
      } catch {}
      XCTAssertEqual(try Data(contentsOf: url), original)
    }
    let url = folder.appendingPathComponent("valid.png")
    let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    }
    let data = try XCTUnwrap(image.pngData())
    try data.write(to: url)
    guard case .image(let imported) = try await VisualFileImport.open(url) else {
      return XCTFail("Not an image")
    }
    XCTAssertGreaterThan(imported.size.width, 0)
    XCTAssertEqual(try Data(contentsOf: url), data)
  }

  func testInvalidVideoImportLeavesSourceAndNoPartialCopy() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("broken.mov")
    let data = Data("not a video".utf8)
    try data.write(to: url)
    let imports = FileManager.default.temporaryDirectory.appendingPathComponent("CodVideoImports")
    let before = (try? FileManager.default.contentsOfDirectory(atPath: imports.path)) ?? []
    do {
      _ = try await VideoReference.copy(from: url)
      XCTFail("Invalid video accepted")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: url), data)
    let after = (try? FileManager.default.contentsOfDirectory(atPath: imports.path)) ?? []
    XCTAssertEqual(Set(before), Set(after))
  }

  @MainActor func testExplicitInputsInvalidateEarlierDocumentWorkWithoutRequiringSetup() {
    let coordinator = CaptureCoordinator()
    let first = coordinator.explicitInputID
    coordinator.prioritizeExplicitInput()
    let second = coordinator.explicitInputID
    XCTAssertNotEqual(first, second)
    coordinator.prioritizeExplicitInput()
    XCTAssertNotEqual(second, coordinator.explicitInputID)
  }

  private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodRelease18-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }
}
