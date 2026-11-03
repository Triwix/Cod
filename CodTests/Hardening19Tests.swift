import AVKit
import Combine
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import Cod

final class Hardening19Tests: XCTestCase {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodHardening19-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  private func image(_ size: CGSize = CGSize(width: 80, height: 60)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }

  @MainActor func testDeletedSavedReferenceCannotBeResurrectedByAStaleEditor() throws {
    let store = SavedReferenceStore(directory: try folder())
    var item = try store.save(
      .init(name: "Directions", detail: "Text", text: .init(text: "Gate 7")))
    try store.delete(item.id)
    item.text?.text = "Gate 9"
    XCTAssertThrowsError(try store.save(item, replacingExisting: true)) { error in
      XCTAssertTrue(error.localizedDescription.contains("removed"))
    }
    XCTAssertTrue(SavedReferenceStore(directory: store.directory).items.isEmpty)
  }

  @MainActor func testFailedSavedReferenceWritePreservesOldContentAndRemovesNewOriginal() throws {
    let store = SavedReferenceStore(directory: try folder())
    var item = try store.save(
      .init(name: "Keep", detail: "Text", text: .init(text: "Original")), original: image())
    let original = try XCTUnwrap(item.originalFilename)
    let index = store.directory.appendingPathComponent("index.json")
    // A directory at the index target models a real atomic-write failure.
    try FileManager.default.removeItem(at: index)
    try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
    item.text?.text = "Changed"
    XCTAssertThrowsError(try store.save(item, original: image(), replacingExisting: true))
    XCTAssertEqual(store.items.first?.text?.text, "Original")
    let assets = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).filter(
      SavedReferenceStore.isOriginalFilename)
    XCTAssertEqual(assets, [original])
  }

  @MainActor func testConfirmedClearRepairsCorruptIndexAndRemovesOnlyOwnedOriginals() throws {
    let directory = try folder()
    let asset = directory.appendingPathComponent("\(UUID()).png")
    try image().pngData()!.write(to: asset)
    let unrelated = directory.appendingPathComponent("keep.txt")
    try Data("Not a Cod asset".utf8).write(to: unrelated)
    try Data("bad index".utf8).write(to: directory.appendingPathComponent("index.json"))
    let store = SavedReferenceStore(directory: directory)
    XCTAssertNotNil(store.loadError)
    XCTAssertThrowsError(
      try store.save(.init(name: "New", detail: "Text", text: .init(text: "Hi"))))
    try store.clear()
    XCTAssertNil(store.loadError)
    XCTAssertFalse(FileManager.default.fileExists(atPath: asset.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    XCTAssertNoThrow(try store.save(.init(name: "New", detail: "Text", text: .init(text: "Hi"))))
  }

  @MainActor func testOriginalFilenameCannotDeleteIndexOrAttachAnotherCardsAsset() throws {
    let store = SavedReferenceStore(directory: try folder())
    let first = try store.save(
      .init(name: "First", detail: "Text", text: .init(text: "Hi")), original: image())
    for name in ["index.json", "../outside.png", "original.png", first.originalFilename!] {
      let other = SavedReference(
        name: "Other", detail: "Text", text: .init(text: "Hi"), originalFilename: name)
      XCTAssertThrowsError(try store.save(other))
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: store.directory.appendingPathComponent("index.json").path))
  }

  func testMissingThumbnailIsDownsampledWithoutChangingOriginal() throws {
    let directory = try folder()
    var store = SnapStore(baseDirectory: directory)
    let snap = store.add(
      image: image(CGSize(width: 2_400, height: 1_600)), origin: .imported, limit: .unlimited)
    store.waitForPendingWrites()
    let root = directory.appendingPathComponent("Snaps")
    try FileManager.default.removeItem(at: root.appendingPathComponent(snap.thumbnailFilename))
    store = SnapStore(baseDirectory: directory)
    let thumbnail = try XCTUnwrap(store.thumbnail(for: snap))
    XCTAssertLessThanOrEqual(max(thumbnail.pixelSize.width, thumbnail.pixelSize.height), 400)
    XCTAssertEqual(store.image(for: snap)?.pixelSize.width, 2_400)
    XCTAssertLessThan(SnapStore.decodedMemoryCost(thumbnail), 1_000_000)
  }

  func testDamagedLibraryIndexIsPreservedUntilExplicitFullDeletion() throws {
    let directory = try folder()
    let root = directory.appendingPathComponent("Snaps")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = root.appendingPathComponent("index.json")
    let corrupt = Data("corrupt history".utf8)
    try corrupt.write(to: index)
    let owned = root.appendingPathComponent("\(UUID()).png")
    try image().pngData()!.write(to: owned)
    let unknown = root.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: unknown)
    let store = SnapStore(baseDirectory: directory)
    XCTAssertNotNil(store.storageIssue)
    store.add(image: image(), origin: .imported, limit: .unlimited)
    store.clearHistory()
    store.waitForPendingWrites()
    XCTAssertEqual(try Data(contentsOf: index), corrupt)
    XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
    store.clear()
    store.waitForPendingWrites()
    XCTAssertTrue(SnapStore(baseDirectory: directory).snaps.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
  }

  func testLibraryCanRetryReadingWithoutDeletingItsFiles() throws {
    let directory = try folder()
    let store = SnapStore(baseDirectory: directory)
    let snap = store.add(image: image(), origin: .imported, limit: .unlimited)
    store.waitForPendingWrites()
    let index = directory.appendingPathComponent("Snaps/index.json")
    let valid = try Data(contentsOf: index)
    try Data("temporarily unreadable index".utf8).write(to: index, options: .atomic)
    let restored = SnapStore(baseDirectory: directory)
    XCTAssertTrue(restored.canRetryLoading)
    try valid.write(to: index, options: .atomic)
    restored.retryLoading()
    XCTAssertFalse(restored.canRetryLoading)
    XCTAssertNil(restored.storageIssue)
    XCTAssertEqual(restored.snaps.map(\.id), [snap.id])
    XCTAssertNotNil(restored.image(for: snap))
  }

  @MainActor func testAsynchronousLibraryWriteFailureIsVisible() async throws {
    let directory = try folder()
    let store = SnapStore(baseDirectory: directory)
    let index = directory.appendingPathComponent("Snaps/index.json")
    try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
    let reported = expectation(description: "Storage failure reported")
    let observer = store.$storageIssue.compactMap { $0 }.first().sink { _ in reported.fulfill() }
    store.add(image: image(), origin: .imported, limit: .unlimited)
    await fulfillment(of: [reported], timeout: 5)
    withExtendedLifetime(observer) {}
    XCTAssertTrue(store.storageIssue?.contains("couldn't be saved") == true)
  }

  func testTemporaryCleanupIsScopedAndDoesNotFollowSymlinks() throws {
    let base = try folder()
    let owned = base.appendingPathComponent(TemporaryMedia.Kind.imports.rawValue)
    try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
    let stale = owned.appendingPathComponent("\(UUID()).mov")
    try Data("stale".utf8).write(to: stale)
    let unknown = owned.appendingPathComponent("source.mov")
    try Data("keep".utf8).write(to: unknown)
    let outside = base.appendingPathComponent("original.mov")
    try Data("original".utf8).write(to: outside)
    let link = owned.appendingPathComponent("\(UUID()).mov")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    TemporaryMedia.cleanUpAfterPreviousLaunch(base: base)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
    XCTAssertEqual(try String(contentsOf: outside), "original")
    XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
  }

  func testDiagnosticsAreByteBoundedAndCannotInsertExtraLines() {
    let value = CodDiagnosticLog.boundedLine(
      String(repeating: "👩🏽‍💻\n", count: 4_000), date: .distantPast)
    XCTAssertLessThan(value.utf8.count, 4_096)
    XCTAssertEqual(value.filter { $0 == "\n" }.count, 1)
    XCTAssertFalse(value.contains("\r"))
  }

  func testDiagnosticWriterCapsFileSizeAndMarksItExcludedFromBackup() throws {
    let url = try folder().appendingPathComponent("diagnostics.log")
    for _ in 0..<40 { CodDiagnosticLog.append(String(repeating: "é", count: 5_000), at: url) }
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isExcludedFromBackupKey])
    XCTAssertLessThanOrEqual(try XCTUnwrap(values.fileSize), CodDiagnosticLog.maximumFileBytes)
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testReferenceDecoderHonors50MBRatherThanShareExtensions32MBLimit() throws {
    var data = try XCTUnwrap(image().pngData())
    data.append(Data(count: SharedImageInbox.maximumImageBytes + 1 - data.count))
    XCTAssertGreaterThan(data.count, SharedImageInbox.maximumImageBytes)
    XCTAssertLessThan(data.count, VisualFileImport.maximumImageBytes)
    XCTAssertNotNil(ReferenceImage.decode(data))
  }

  func testImageBudgetRejectsInvalidMetadataAndBoundsLargeSources() {
    for dimensions in [(Double.infinity, 1.0), (.nan, 10), (0, 20), (1, -1), (1e300, 1e300)] {
      XCTAssertNil(ReferenceImage.maximumEdge(width: dimensions.0, height: dimensions.1))
    }
    for (width, height) in [(10_000.0, 10_000.0), (600.0, 30_000.0)] {
      let edge = Double(ReferenceImage.maximumEdge(width: width, height: height)!)
      let ratio = edge / max(width, height)
      XCTAssertLessThanOrEqual(width * height * ratio * ratio, 16_000_000)
      XCTAssertLessThanOrEqual(width * ratio, 4_096)
      XCTAssertLessThanOrEqual(height * ratio, 12_000)
    }
    XCTAssertNil(ReferenceImage.decode(at: URL(string: "https://example.com/photo.png")!))
  }

  func testRealLargeAndRotatedImagesAreDecodedInsideTheBudget() throws {
    try autoreleasepool {
      let large = try XCTUnwrap(
        image(CGSize(width: 4_000, height: 6_000)).jpegData(compressionQuality: 0.8))
      let decoded = try XCTUnwrap(ReferenceImage.decode(large))
      XCTAssertLessThanOrEqual(decoded.pixelSize.width * decoded.pixelSize.height, 16_010_000)
      XCTAssertLessThanOrEqual(decoded.pixelSize.width, 4_096)
      XCTAssertLessThanOrEqual(decoded.pixelSize.height, 12_000)
    }
    let rotated = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(rotated, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, try XCTUnwrap(image(CGSize(width: 600, height: 6_000)).cgImage),
      [kCGImagePropertyOrientation: 6] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let decoded = try XCTUnwrap(ReferenceImage.decode(rotated as Data))
    XCTAssertGreaterThan(decoded.pixelSize.width, decoded.pixelSize.height)
    XCTAssertLessThanOrEqual(decoded.pixelSize.width, 4_096)
    XCTAssertEqual(decoded.imageOrientation, .up)
  }

  @MainActor func testUpdatingReferencePreservesIdentifierAndOriginalAcrossRelaunch() throws {
    let directory = try folder()
    let store = SavedReferenceStore(directory: directory)
    var item = try store.save(
      .init(name: "Card", detail: "Text", text: .init(text: "First")), original: image())
    let originalFilename = item.originalFilename
    item.text?.text = "Edited"
    try store.save(item, replacingExisting: true)
    let reloaded = SavedReferenceStore(directory: directory)
    XCTAssertEqual(reloaded.items.map(\.id), [item.id])
    XCTAssertEqual(reloaded.items.first?.text?.text, "Edited")
    XCTAssertEqual(reloaded.items.first?.originalFilename, originalFilename)
    XCTAssertNotNil(reloaded.original(for: item))
  }

  func testScrollingStopsLoadingAsSoonAsCanvasBudgetIsExceeded() {
    var loaded = 0
    let source = image(CGSize(width: 100, height: 1_000))
    XCTAssertThrowsError(
      try ScrollingReference(pageCount: 20, name: "Bounded") { _ in
        loaded += 1
        return source
      })
    XCTAssertEqual(loaded, 3, "Don't eagerly render all 20 pages before rejecting the third")
  }

  func testClearingThenImmediatelySavingDoesNotSweepTheNewCapture() throws {
    let store = SnapStore(baseDirectory: try folder())
    store.add(image: image(), origin: .imported, limit: .unlimited)
    store.clear()
    let latest = store.add(image: image(), origin: .imported, limit: .unlimited)
    store.waitForPendingWrites()
    XCTAssertEqual(store.snaps.map(\.id), [latest.id])
    XCTAssertNotNil(store.image(for: latest))
  }

  @MainActor func testRepeatedEndSeeksKeepNativeClockPausedInsideTheFiniteRange() async throws {
    let session = FloatingToolSession(
      configuration: .init(kind: .teleprompter, text: "A short finite script"))
    let source = LiveFloatSource(session: session)
    let pip = AVPictureInPictureController(
      contentSource: .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: source))
    source.controller = pip
    try source.start()
    defer { source.stop() }
    let range = source.pictureInPictureControllerTimeRangeForPlayback(pip)
    let timebase = try XCTUnwrap(source.layer.controlTimebase)
    for _ in 0..<20 {
      session.resume()
      session.seek(to: 999_999)
      try await Task.sleep(for: .milliseconds(3))
      XCTAssertTrue(CMTimeRangeContainsTime(range, time: CMTimebaseGetTime(timebase)))
      XCTAssertEqual(CMTimebaseGetRate(timebase), 0)
    }
  }
}
