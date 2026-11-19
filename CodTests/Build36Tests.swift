import XCTest
import UniformTypeIdentifiers
@testable import Cod

/// Recents fixes, video speed and sections, web video links and documents.
@MainActor
final class Build36Tests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suite = "Build36-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  // MARK: Recents

  func testTheSameSetupInLightAndDarkModeIsOneRecent() {
    let recents = RecentFloats(defaults: defaults)
    var light = FloatingToolConfiguration(kind: .stopwatch)
    light.interfaceStyle = .light
    var dark = light
    dark.interfaceStyle = .dark
    recents.record(light)
    recents.record(dark)
    XCTAssertEqual(recents.items.count, 1)
  }

  func testOlderDuplicateListsMergeAndKeepTheirStar() throws {
    var light = FloatingToolConfiguration(kind: .stopwatch)
    light.interfaceStyle = .light
    var dark = light
    dark.interfaceStyle = .dark
    let saved = [RecentFloat(configuration: light), RecentFloat(configuration: dark, starred: true)]
    defaults.set(try JSONEncoder().encode(saved), forKey: "cod.home.recentFloats")
    let recents = RecentFloats(defaults: defaults)
    XCTAssertEqual(recents.items.count, 1)
    XCTAssertTrue(recents.items[0].isStarred)
  }

  func testRowsShowWhatMakesASetupDifferent() {
    var stopwatch = FloatingToolConfiguration(kind: .stopwatch)
    XCTAssertEqual(RecentFloat(configuration: stopwatch).detail, "")
    stopwatch.showsHundredths = true
    stopwatch.windowShape = .square
    XCTAssertEqual(RecentFloat(configuration: stopwatch).detail, "Hundredths · 1:1")
  }

  func testImageSetsPagesAndDocumentsAreRecorded() {
    let recents = RecentFloats(defaults: defaults)
    var set = FloatingToolConfiguration(kind: .slideshow)
    set.slideNames = ["a.jpg", "b.jpg"]
    recents.record(set)
    var pages = set
    pages.slideNames = ["c.jpg", "d.jpg", "e.jpg"]
    pages.startsPaused = true
    pages.setName = "Guide · 1–3"
    recents.record(pages)
    var document = FloatingToolConfiguration(kind: .document)
    document.text = "Manual · 2–4"
    document.documentPages = ["f.jpg"]
    recents.record(document)
    var unsaved = FloatingToolConfiguration(kind: .document)
    unsaved.text = "Not stored"
    recents.record(unsaved)
    XCTAssertEqual(recents.items.map(\.title), ["Manual · 2–4", "Guide · 1–3", "Image Set"])
    XCTAssertEqual(recents.items[1].detail, "3 pages")
    XCTAssertEqual(recents.items[2].detail, "2 images · every 5 s")
    XCTAssertEqual(recents.items[0].detail, "Auto-scroll · 1 pages")
  }

  func testStoredDocumentPagesFloatAgainFromRecents() throws {
    let page = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 600)).image { context in
      UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 600))
    }
    let names = try Slideshow.storePages([page, page])
    defer { names.forEach { try? FileManager.default.removeItem(at: Slideshow.directory.appendingPathComponent($0)) } }
    var configuration = FloatingToolConfiguration(kind: .document)
    configuration.text = "Notes"
    configuration.documentPages = names
    let document = try XCTUnwrap(CaptureCoordinator.document(for: configuration))
    XCTAssertEqual(document.pages.count, 2)
    XCTAssertEqual(document.name, "Notes")
    configuration.documentPages = names + ["missing.jpg"]
    XCTAssertNil(CaptureCoordinator.document(for: configuration), "Missing pages don't float half a document")
  }

  // MARK: Video

  func testVideoSectionsFitTheVideo() {
    XCTAssertNil(FloatingVideoOptions.clampedSection(nil, duration: 60))
    XCTAssertNil(FloatingVideoOptions.clampedSection(0...60, duration: 60), "The whole video isn't a section")
    XCTAssertEqual(FloatingVideoOptions.clampedSection(10...20, duration: 60), 10...20)
    XCTAssertEqual(FloatingVideoOptions.clampedSection(50...90, duration: 60), 50...60)
    XCTAssertEqual(FloatingVideoOptions.clampedSection(30...30, duration: 60), 30...31, "At least one second")
    XCTAssertEqual(FloatingVideoOptions.clampedSection(70...80, duration: 60), 59...60)
    XCTAssertNil(FloatingVideoOptions.clampedSection(0...1, duration: 0.5))
    XCTAssertEqual(FloatingVideoOptions.speeds.map(FloatingVideoOptions.speedTitle),
                   ["0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
  }

  func testPlaybackAppliesSpeedAndSection() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120)).image { context in
      UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
    }
    let source = try await FloatingClip.make(from: image)
    defer { try? FileManager.default.removeItem(at: source) }
    let reference = try await VideoReference.copy(from: source)
    let playback = FloatingVideoPlayback(
      reference: reference, options: .init(speed: 1.5, section: 10...20))
    XCTAssertEqual(playback.startTime.seconds, 10, accuracy: 0.01)
    XCTAssertEqual(playback.player.currentItem?.forwardPlaybackEndTime.seconds ?? 0, 20, accuracy: 0.01)
    playback.setSpeed(2)
    XCTAssertEqual(playback.player.defaultRate, 2)
    XCTAssertEqual(playback.options.speed, 2)
    playback.stop()
  }

  // MARK: Web video

  func testLinksAreReadFromTypedAndSharedText() {
    XCTAssertEqual(WebVideoLink.url(from: "https://www.youtube.com/watch?v=abc")?.absoluteString,
                   "https://www.youtube.com/watch?v=abc")
    XCTAssertEqual(WebVideoLink.url(from: "youtube.com/watch?v=abc")?.host, "youtube.com")
    XCTAssertEqual(WebVideoLink.url(from: "http://vimeo.com/1")?.scheme, "https", "Upgraded to https")
    XCTAssertEqual(WebVideoLink.url(from: "Watch this https://youtu.be/xyz now")?.absoluteString, "https://youtu.be/xyz")
    XCTAssertNil(WebVideoLink.url(from: "not a link"))
    XCTAssertNil(WebVideoLink.url(from: "ftp://example.com/file"))
    XCTAssertEqual(WebVideoLink.loneLink(in: "  https://youtu.be/xyz \n")?.absoluteString, "https://youtu.be/xyz")
    XCTAssertNil(WebVideoLink.loneLink(in: "Watch this https://youtu.be/xyz"), "Text with a link stays text")
  }

  func testASharedLinkIsClaimedOnceWhileFresh() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Build36-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let handoff = SharedLinkHandoff(container: { directory })
    let now = Date()
    try handoff.store(URL(string: "https://youtu.be/xyz")!, now: now)
    XCTAssertEqual(handoff.claim(now: now)?.absoluteString, "https://youtu.be/xyz")
    XCTAssertNil(handoff.claim(now: now), "Claimed once")
    try handoff.store(URL(string: "https://youtu.be/old")!, now: now)
    XCTAssertNil(handoff.claim(now: now.addingTimeInterval(SharedLinkHandoff.maximumAge + 1)))
  }

  func testFreeTierAsksForProBeforeOpeningWebVideo() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Build36-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = CaptureCoordinator(
      store: .shared, settings: AppSettings(defaults: defaults), pip: PiPPinController(),
      pro: ProStore(defaults: defaults))
    let handoff = SharedLinkHandoff(container: { directory })
    try handoff.store(URL(string: "https://youtu.be/xyz")!)
    XCTAssertTrue(coordinator.receiveSharedLink(handoff))
    XCTAssertEqual(coordinator.proPrompt?.feature, .video)
    XCTAssertNil(coordinator.route)
  }

  // MARK: Documents

  func testFileImportOffersOfficeAndTextDocuments() throws {
    for fileExtension in ["docx", "pptx", "xlsx", "key", "pages", "txt", "rtf", "md"] {
      let type = try XCTUnwrap(UTType(filenameExtension: fileExtension), fileExtension)
      XCTAssertTrue(VisualFileImport.contentTypes.contains { type.conforms(to: $0) }, fileExtension)
    }
    XCTAssertTrue(DocumentImport.isOffice(UTType("com.microsoft.word.doc")!))
    XCTAssertFalse(DocumentImport.isOffice(.pdf))
    XCTAssertTrue(DocumentImport.isText(.plainText))
    XCTAssertFalse(DocumentImport.isText(.pdf))
  }

  func testTextMarkdownAndRTFBecomeEditableText() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Build36-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let plain = folder.appendingPathComponent("notes.txt")
    try "  Line one\r\nLine two \n".write(to: plain, atomically: true, encoding: .utf8)
    XCTAssertEqual(try DocumentImport.text(at: plain, type: .plainText), "Line one\nLine two")

    let markdown = UTType("net.daringfireball.markdown")!
    let md = folder.appendingPathComponent("notes.md")
    try "# Title\n\n- **Bold** item\n1. Step [link](https://a.b)\n> Quote".write(to: md, atomically: true, encoding: .utf8)
    XCTAssertEqual(try DocumentImport.text(at: md, type: markdown), "Title\n\n• Bold item\n• Step link\nQuote")

    let rtf = folder.appendingPathComponent("notes.rtf")
    let attributed = NSAttributedString(string: "Styled text", attributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
    let data = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                   documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    try data.write(to: rtf)
    XCTAssertEqual(try DocumentImport.text(at: rtf, type: .rtf), "Styled text")

    let empty = folder.appendingPathComponent("empty.txt")
    try " \n".write(to: empty, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try DocumentImport.text(at: empty, type: .plainText))
  }

  func testWordDocumentsBecomePDFPages() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Sample", withExtension: "docx", subdirectory: "Fixtures"))
    let pdf = try await DocumentImport.pdf(from: url)
    XCTAssertGreaterThanOrEqual(pdf.pageCount, 2, "120 paragraphs need more than one page")
    XCTAssertEqual(pdf.name, "Sample")
    let page = try pdf.image(pageIndex: 0)
    XCTAssertGreaterThan(page.size.height, page.size.width, "Letter pages")
    XCTAssertGreaterThan(Self.inkFraction(of: page), 0.005, "The page has the document's text, not a blank sheet")
  }

  /// Share of pixels noticeably darker than white.
  private static func inkFraction(of image: UIImage) -> Double {
    guard let cgImage = image.cgImage else { return 0 }
    let width = 200, height = Int(200 * Double(cgImage.height) / Double(cgImage.width))
    var pixels = [UInt8](repeating: 255, count: width * height)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return 0 }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Double(pixels.filter { $0 < 200 }.count) / Double(pixels.count)
  }
}
