import AVFoundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@testable import Cod

final class Features16Tests: XCTestCase {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "features16-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  private func image(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 48)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      color.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }
  private func gif(colors: [UIColor] = [.red, .blue], delays: [Double] = [0.3, 0.7]) throws -> Data
  {
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, colors.count, nil))
    for (index, color) in colors.enumerated() {
      CGImageDestinationAddImage(
        destination, try XCTUnwrap(image(color).cgImage),
        [
          kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delays[index % delays.count],
            kCGImagePropertyGIFUnclampedDelayTime: delays[index % delays.count],
          ]
        ] as CFDictionary)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
  private func rgb(_ image: UIImage) throws -> [Int] {
    let cg = try XCTUnwrap(image.cgImage)
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(
      CGContext(
        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return bytes.prefix(3).map(Int.init)
  }

  func testTextReflowDoesNotRewriteNumbersAndPreservesParagraphs() {
    XCTAssertEqual(
      RecognizedReferenceText.reflow("Gate 7\nat 14:30\n\n2.5 kg  flour"),
      "Gate 7 at 14:30\n\n2.5 kg flour")
    XCTAssertEqual(RecognizedReferenceText.reflow("  \n"), "")
  }

  func testImageRecognitionFindsRealReferenceTextAndNumbers() async throws {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 240), format: format).image { context in
      UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 240))
      ("Gate 7 at 14:30\n2.5 kg flour" as NSString).draw(in: CGRect(x: 50, y: 40, width: 800, height: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 54), .foregroundColor: UIColor.black])
    }
    do {
      let result = try await Recognizer.recognizeText(in: image, accuracy: .accurate, languages: ["en-US"], usesLanguageCorrection: false)
      let text = RecognizedReferenceText.reflow(result.text)
      XCTAssertTrue(text.contains("Gate 7"), text)
      XCTAssertTrue(text.contains("14:30"), text)
      XCTAssertTrue(text.contains("2.5"), text)
      XCTAssertTrue(text.contains("flour"), text)
    } catch Recognizer.RecognizerError.unavailable {
      throw XCTSkip("Vision's model is unavailable in this simulator; real image recognition needs device acceptance.")
    }
  }

  @MainActor func testSavedTextIsEditableDurableAndIndependentOfHistory() throws {
    let directory = try temporaryDirectory()
    let store = SavedReferenceStore(directory: directory)
    let original = image(.green)
    var card = try store.save(
      .init(
        name: "  Gate 7  ", detail: "Text card",
        text: .init(text: "Gate 7 at 14:30", fontSize: 52, palette: .yellow)), original: original)
    XCTAssertEqual(card.name, "Gate 7")
    let reloaded = SavedReferenceStore(directory: directory)
    XCTAssertEqual(reloaded.items.first?.text?.text, "Gate 7 at 14:30")
    XCTAssertEqual(reloaded.items.first?.text?.fontSize, 52)
    XCTAssertNotNil(reloaded.original(for: card))
    card.text?.text = "Changed to Gate 9"
    _ = try reloaded.save(card)
    XCTAssertEqual(reloaded.items.count, 1)
    XCTAssertEqual(
      SavedReferenceStore(directory: directory).items.first?.text?.text, "Changed to Gate 9")
    try reloaded.delete(card.id)
    XCTAssertTrue(reloaded.items.isEmpty)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(try XCTUnwrap(card.originalFilename)).path))
  }

  @MainActor func testSavedPresetRoundTripsAllAppearanceTimingAndClockSettings() throws {
    let store = SavedReferenceStore(directory: try temporaryDirectory())
    var config = FloatingToolConfiguration(kind: .teleprompter, text: "Actual script")
    config.palette = .yellow
    config.customColors = .init(background: .purple, foreground: .cyan)
    config.interfaceStyle = .dark
    config.readingGuide = true
    config.sideMargin = 120
    config.lineSpacing = 22
    config.targetReadingDuration = 240
    config.prompterMode = .words
    config.wordsAtATime = 3
    config.prompterCountdownSeconds = 8
    config.showsClockDate = false
    let item = try store.save(.init(name: "Script", detail: "Teleprompter", tool: config))
    let decoded = try XCTUnwrap(SavedReferenceStore(directory: store.directory).items.first?.tool)
    XCTAssertEqual(decoded.text, config.text)
    XCTAssertEqual(decoded.interfaceStyle, .dark)
    XCTAssertEqual(decoded.customColors, config.customColors)
    XCTAssertEqual(decoded.targetReadingDuration, 240)
    XCTAssertEqual(decoded.sideMargin, 120)
    XCTAssertEqual(decoded.lineSpacing, 22)
    XCTAssertEqual(decoded.wordsAtATime, 3)
    XCTAssertTrue(decoded.readingGuide)
    XCTAssertFalse(decoded.showsClockDate)
    let summaries = try JSONDecoder().decode(
      [SavedReferenceSummary].self,
      from: Data(contentsOf: store.directory.appendingPathComponent("index.json")))
    XCTAssertEqual(summaries.map(\.id), [item.id])
    XCTAssertEqual(summaries.first?.name, "Script")
  }

  @MainActor func testInvalidSavedReferencesNeverOverwriteGoodData() throws {
    let store = SavedReferenceStore(directory: try temporaryDirectory())
    _ = try store.save(.init(name: "Keep", detail: "Text", text: .init(text: "Original")))
    for candidate in [
      SavedReference(name: " ", detail: "Text", text: .init(text: "Hi")),
      .init(name: "Empty", detail: "Text", text: .init(text: "")),
      .init(name: "Ambiguous", detail: "Text", text: .init(text: "Hi"), tool: .init(kind: .clock)),
      .init(name: "Missing", detail: "Text"),
    ] {
      XCTAssertThrowsError(try store.save(candidate))
    }
    XCTAssertEqual(SavedReferenceStore(directory: store.directory).items.first?.name, "Keep")
  }

  @MainActor func testCorruptSavedIndexIsNotSilentlyReplaced() throws {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("index.json")
    let corrupt = Data("not a valid index".utf8)
    try corrupt.write(to: url)
    let store = SavedReferenceStore(directory: directory)
    XCTAssertNotNil(store.loadError)
    XCTAssertThrowsError(
      try store.save(.init(name: "New", detail: "Text", text: .init(text: "Hi"))))
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
  }

  func testColorCodecRejectsCorruption() throws {
    let invalid = Data(#"{"background":[1,0,0],"foreground":[0,0,0,1]}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(FloatingColors.self, from: invalid))
  }

  func testTimedPrompterDurationExcludesCountdownAndChangesBothModes() throws {
    var config = FloatingToolConfiguration(
      kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
    config.targetReadingDuration = 120
    config.prompterCountdownSeconds = 5
    for mode in TeleprompterMode.allCases {
      config.prompterMode = mode
      try config.validate()
      let layout = FloatingToolRenderer.ScriptLayout(config)
      XCTAssertEqual(layout.duration(config), 120)
      if mode == .words { XCTAssertEqual(layout.words.duration, 120, accuracy: 0.01) }
    }
  }

  @MainActor func testTimedShortScriptStillHoldsForTargetAndSeeksWithoutChangingSettings() throws {
    var now = 0.0
    var config = FloatingToolConfiguration(kind: .teleprompter, text: "Short script")
    config.targetReadingDuration = 90
    config.prompterCountdownEnabled = false
    let session = FloatingToolSession(configuration: config, uptime: { now })
    XCTAssertEqual(session.playbackDuration, 90)
    session.resume()
    now = 20
    session.skip(by: -10)
    XCTAssertEqual(session.elapsed, 10)
    session.seek(to: 90)
    XCTAssertFalse(session.isPlaying)
    XCTAssertEqual(session.configuration.targetReadingDuration, 90)
  }

  func testInvalidReadingDurationsAndLayoutAreRejectedButPreviewsStaySafe() {
    for value in [0.0, 14, 3_601, Double.infinity, Double.nan] {
      var config = FloatingToolConfiguration(kind: .teleprompter, text: "Preview")
      config.targetReadingDuration = value
      XCTAssertThrowsError(try config.validate())
      XCTAssertNotNil(
        FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .now).cgImage)
    }
    for value in [0.0, 200, Double.nan] {
      var config = FloatingToolConfiguration(kind: .teleprompter, text: "Preview")
      config.sideMargin = value
      XCTAssertThrowsError(try config.validate())
    }
  }

  func testReadingGuideAndLayoutChangePixelsAndTravel() {
    var config = FloatingToolConfiguration(
      kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
    config.prompterCountdownEnabled = false
    let old = FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .now).pngData()
    let travel = FloatingToolRenderer.ScriptLayout(config).travel
    config.readingGuide = true
    XCTAssertNotEqual(
      old, FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .now).pngData())
    config.lineSpacing = 40
    config.sideMargin = 160
    XCTAssertGreaterThan(FloatingToolRenderer.ScriptLayout(config).travel, travel)
  }

  func testReadingGuideBlendsWithTheBackgroundInsteadOfBecomingOpaque() throws {
    for (palette, range) in [(FloatingPalette.light, 210...245), (.dark, 10...60)] {
      var config = FloatingToolConfiguration(kind: .teleprompter, text: "Short line")
      config.prompterCountdownEnabled = false
      config.palette = palette
      config.readingGuide = true
      let frame = FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .now)
      let region = try XCTUnwrap(frame.cgImage?.cropping(to: CGRect(x: 800, y: 110, width: 8, height: 8)))
      let components = try rgb(UIImage(cgImage: region))
      XCTAssertTrue(components.allSatisfy { range.contains($0) }, "Guide must be a subtle blended band: \(components)")
    }
  }

  func testScrollingImageHasFiniteTravelAndHoldsTheLastRegion() throws {
    let tall = UIGraphicsImageRenderer(
      size: CGSize(width: 100, height: 600),
      format: {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return f
      }()
    ).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 300))
      UIColor.blue.setFill()
      context.fill(CGRect(x: 0, y: 300, width: 100, height: 300))
    }
    let reference = try ScrollingReference(images: [tall])
    XCTAssertGreaterThan(reference.duration(speed: 32), 1)
    XCTAssertNotEqual(
      reference.frame(elapsed: 0, speed: 32).pngData(),
      reference.frame(elapsed: reference.duration(speed: 32), speed: 32).pngData())
    XCTAssertEqual(
      reference.frame(elapsed: reference.duration(speed: 32), speed: 32).pngData(),
      reference.frame(elapsed: 100_000, speed: 32).pngData())
    XCTAssertGreaterThan(try rgb(reference.frame(elapsed: 100_000, speed: 32))[2], 200)
  }

  @MainActor func testScrollingSessionUsesActualDocumentTimelineAndNativeSeek() throws {
    var now = 0.0
    let reference = try ScrollingReference(images: [image(.red), image(.blue)])
    var config = FloatingToolConfiguration(kind: .document)
    config.duration = reference.duration(speed: 32)
    let session = FloatingToolSession(configuration: config, document: reference, uptime: { now })
    XCTAssertEqual(session.playbackDuration, reference.duration(speed: 32))
    XCTAssertTrue(config.supportsSeeking)
    session.resume()
    now = 3
    session.pause()
    session.seek(to: 10)
    XCTAssertEqual(session.elapsed, min(10, reference.duration(speed: 32)))
    XCTAssertFalse(session.isPlaying)
    XCTAssertEqual(session.renderedFrame().size, ScrollingReference.viewport)
  }

  func testScrollingPDFPageRangeAndResourceLimits() throws {
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData {
      context in
      for color in [UIColor.red, .blue, .green] {
        context.beginPage()
        color.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
      }
    }
    let pdf = try PDFReference(data: data)
    let reference = try ScrollingReference.pdf(pdf, first: 2, last: 3)
    XCTAssertEqual(reference.pages.count, 2)
    XCTAssertGreaterThan(try rgb(reference.pages[0])[2], 200)
    XCTAssertThrowsError(try ScrollingReference.pdf(pdf, first: 0, last: 1))
    XCTAssertThrowsError(try ScrollingReference.pdf(pdf, first: 3, last: 2))
    XCTAssertThrowsError(try ScrollingReference(images: []))
    XCTAssertThrowsError(try ScrollingReference(images: Array(repeating: image(.red), count: 21)))
    XCTAssertThrowsError(
      try ScrollingReference(images: [image(.red, size: CGSize(width: 2, height: 100))]))
  }

  func testTallImageDecoderPreservesUsefulWidthWithinPixelBudget() throws {
    let data = try XCTUnwrap(image(.red, size: CGSize(width: 600, height: 6_000)).pngData())
    let decoded = try XCTUnwrap(ReferenceImage.decode(data))
    XCTAssertEqual(decoded.pixelSize.height, 6_000)
    XCTAssertEqual(decoded.pixelSize.width, 600)
    XCTAssertNil(ReferenceImage.decode(Data("bad".utf8)))
  }

  func testGIFDetectionTimingAndStaticImages() throws {
    XCTAssertTrue(AnimatedImageImport.isAnimatedGIF(try gif()))
    XCTAssertFalse(AnimatedImageImport.isAnimatedGIF(try XCTUnwrap(image(.red).pngData())))
    XCTAssertFalse(AnimatedImageImport.isAnimatedGIF(Data("bad".utf8)))
    XCTAssertEqual(AnimatedImageImport.frameDelay([:]), 0.1)
    XCTAssertEqual(
      AnimatedImageImport.frameDelay([
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.001]
      ]), 0.02)
  }

  func testGIFIsARealVideoWithBothFramesAndOriginalDuration() async throws {
    let video = try await AnimatedImageImport.video(gif())
    XCTAssertEqual(video.duration, 1, accuracy: 0.05)
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video.url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (red, _) = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600))
    let (blue, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
    XCTAssertGreaterThan(try rgb(UIImage(cgImage: red))[0], 200)
    XCTAssertGreaterThan(try rgb(UIImage(cgImage: blue))[2], 200)
  }

  @MainActor func testFileImportRetainsGIFMotionInsteadOfUsingAThumbnail() async throws {
    let file = try temporaryDirectory().appendingPathComponent("motion.gif")
    try gif().write(to: file)
    guard case .video(let video) = try await VisualFileImport.open(file) else {
      return XCTFail("Animated GIF became a still image")
    }
    XCTAssertEqual(video.duration, 1, accuracy: 0.05)
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
  }

  @MainActor func testImageShortcutHandsOffGIFWithoutChangingExistingImageBindings() async throws {
    let intent = FloatWithCodIntent()
    intent.image = .init(data: try gif(), filename: "motion.gif", type: .gif)
    _ = try await intent.perform()
    defer { IntentInbox.shared.pendingReference = nil }
    guard case .animated(let data)? = IntentInbox.shared.pendingReference?.content else {
      return XCTFail("Animation was flattened")
    }
    XCTAssertTrue(AnimatedImageImport.isAnimatedGIF(data))
  }

  func testVideoCropCreatesBoundedOutputAndKeepsSourceUntouched() async throws {
    let video = try await AnimatedImageImport.video(gif())
    let original = try Data(contentsOf: video.url)
    let cropped = try await VideoRegionCrop.crop(
      video, region: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    XCTAssertEqual(cropped.poster.pixelSize.width, video.poster.pixelSize.width / 2, accuracy: 1)
    XCTAssertEqual(cropped.poster.pixelSize.height, video.poster.pixelSize.height / 2, accuracy: 1)
    XCTAssertEqual(cropped.duration, video.duration, accuracy: 0.05)
    XCTAssertEqual(try Data(contentsOf: video.url), original)
    XCTAssertGreaterThan(try rgb(cropped.poster)[0], 200)
    do {
      _ = try await VideoRegionCrop.crop(video, region: CGRect(x: -1, y: 0, width: 1, height: 1))
      XCTFail("Accepted an invalid crop")
    } catch {}
  }

  func testVideoCropUsesTopLeftCoordinatesAndHonorsRotation() async throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let quadrants = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 96), format: format)
      .image { context in
        for (color, rect) in [
          (UIColor.red, CGRect(x: 0, y: 0, width: 64, height: 48)),
          (.blue, CGRect(x: 64, y: 0, width: 64, height: 48)),
          (.green, CGRect(x: 0, y: 48, width: 64, height: 48)),
          (.yellow, CGRect(x: 64, y: 48, width: 64, height: 48)),
        ] {
          color.setFill()
          context.fill(rect)
        }
      }
    let video = try await VideoReference.openOwned(FloatingClip.make(from: quadrants))
    let region = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    let cropped = try await VideoRegionCrop.crop(video, region: region)
    XCTAssertGreaterThan(
      try rgb(cropped.poster)[2], 200, "Top-right must be blue, not the bottom-right yellow region")
    let asset = AVURLAsset(url: video.url)
    let composition = AVMutableComposition()
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let originalTrack = try XCTUnwrap(tracks.first)
    let track = try XCTUnwrap(
      composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    try track.insertTimeRange(
      CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: originalTrack,
      at: .zero)
    track.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0)
    let output = try temporaryDirectory().appendingPathComponent("rotated.mov")
    let export = try XCTUnwrap(
      AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
    if #available(iOS 18.0, *) {
      try await export.export(to: output, as: .mov)
    } else {
      throw XCTSkip("Rotation fixture export uses iOS 18+")
    }
    let rotated = try await VideoReference.copy(from: output)
    XCTAssertGreaterThan(rotated.poster.size.height, rotated.poster.size.width)
    let result = try await VideoRegionCrop.crop(rotated, region: region)
    let expected = try XCTUnwrap(
      rotated.poster.cropped(
        toPixelRect: CGRect(
          x: rotated.poster.pixelSize.width * region.minX, y: 0,
          width: rotated.poster.pixelSize.width * region.width,
          height: rotated.poster.pixelSize.height * region.height)))
    let expectedRGB = try rgb(expected)
    let actualRGB = try rgb(result.poster)
    for channel in 0..<3 { XCTAssertEqual(actualRGB[channel], expectedRGB[channel], accuracy: 15) }
    XCTAssertEqual(result.duration, rotated.duration, accuracy: 0.05)
  }

  func testGIFResourceCapsFailCleanly() async throws {
    for data in [
      try gif(colors: Array(repeating: UIColor.red, count: 601)),
      try gif(colors: Array(repeating: UIColor.red, count: 13), delays: [10]),
    ] {
      do {
        _ = try await AnimatedImageImport.video(data)
        XCTFail("Oversized animation was accepted")
      } catch { XCTAssertTrue(error is AnimatedImageError) }
    }
  }

  func testGIFDeltaFramesAreCompositedNotStretchedOverTheCanvas() async throws {
    // A real optimized GIF: red 4x4 canvas followed by a blue 1x1 patch at
    // (1,1), disposal=keep. Both its offsets and previous pixels must survive.
    var bytes: [UInt8] = Array("GIF89a".utf8) + [4, 0, 4, 0, 0x80, 0, 0, 255, 0, 0, 0, 0, 255]
    func appendFrame(width: UInt8, height: UInt8, left: UInt8, top: UInt8, pixel: UInt8) {
      bytes += [0x21, 0xF9, 4, 4, 50, 0, 0, 0, 0x2C, left, 0, top, 0, width, 0, height, 0, 0, 2]
      let codes: [UInt8] =
        (0..<(Int(width) * Int(height))).flatMap { _ -> [UInt8] in [4, pixel] } + [UInt8(5)]
      var packed: [UInt8] = []
      var accumulator = 0
      var bits = 0
      for code in codes {
        accumulator |= Int(code) << bits
        bits += 3
        while bits >= 8 {
          packed.append(UInt8(accumulator & 255))
          accumulator >>= 8
          bits -= 8
        }
      }
      if bits > 0 { packed.append(UInt8(accumulator & 255)) }
      bytes += [UInt8(packed.count)] + packed + [0]
    }
    appendFrame(width: 4, height: 4, left: 0, top: 0, pixel: 0)
    appendFrame(width: 1, height: 1, left: 1, top: 1, pixel: 1)
    bytes += [0x3B]
    let video = try await AnimatedImageImport.video(Data(bytes))
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video.url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (frame, _) = try await generator.image(at: CMTime(seconds: 0.7, preferredTimescale: 600))
    let average = try rgb(UIImage(cgImage: frame))
    XCTAssertGreaterThan(
      average[0], average[2], "A single blue patch must not replace the whole red background")
  }

  @MainActor func testSavedReferenceIntentPreservesExactIDAndClearsOtherInput() async throws {
    let inbox = IntentInbox.shared
    inbox.deliverForFloat(image(.red))
    let id = UUID()
    let intent = FloatSavedReferenceIntent(
      target: .init(.init(id: id, name: "Chosen card", detail: "Text")))
    _ = try await intent.perform()
    defer { inbox.pendingReference = nil }
    guard case .saved(let delivered)? = inbox.pendingReference?.content else {
      return XCTFail("Missing explicit saved reference")
    }
    XCTAssertEqual(delivered, id)
    XCTAssertNil(inbox.pendingFloatImage)
    XCTAssertFalse(inbox.wantsFloatLatest)
  }

  func testVeryShortWordScriptCanUseALongTargetDuration() {
    var config = FloatingToolConfiguration(kind: .teleprompter, text: "One word")
    config.targetReadingDuration = 3_600
    config.prompterMode = .words
    let layout = FloatingToolRenderer.ScriptLayout(config)
    XCTAssertEqual(layout.words.duration, 3_600, accuracy: 0.01)
    XCTAssertEqual(layout.words.chunk(at: 1_801), "word")
  }
}
