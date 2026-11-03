import UIKit
import XCTest

@testable import Cod

final class Polish11Tests: XCTestCase {
  @MainActor func testClosedVisualTimersRemainDiscoverableAndCanBeCancelled() {
    let timers = FloatingVisualTimers()
    var uptime = 0.0
    let session = FloatingToolSession(
      configuration: .init(kind: .countdown, duration: 10), uptime: { uptime })
    session.resume()
    timers.keep(session)
    timers.keep(session)
    XCTAssertEqual(timers.sessions.count, 1)
    uptime = 5
    XCTAssertEqual(timers.sessions.first?.snapshot.value, "00:05")
    timers.cancel(session)
    XCTAssertTrue(timers.sessions.isEmpty)
    XCTAssertFalse(session.isPlaying)
  }

  func testLegacyFavoritesMigrateToPersistentStableOrder() {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodLegacyOrder-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SnapStore(baseDirectory: base)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
    var a = store.add(image: image, origin: .shared, limit: .unlimited)
    var b = store.add(image: image, origin: .shared, limit: .unlimited)
    a.isFavorite = true
    b.isFavorite = true
    store.update(a)
    store.update(b)
    store.waitForPendingWrites()
    let reloaded = SnapStore(baseDirectory: base)
    XCTAssertEqual(reloaded.favorites.map(\.id), [a.id, b.id])
    XCTAssertTrue(reloaded.favorites.allSatisfy { $0.favoriteOrder != nil })
    reloaded.waitForPendingWrites()
    XCTAssertEqual(SnapStore(baseDirectory: base).favorites.map(\.id), [a.id, b.id])
  }

  @MainActor func testUnifiedFileImportRoutesARealMovieWithoutTouchingItsOriginal() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { _ in }
    let original = try await FloatingClip.make(from: image)
    defer { try? FileManager.default.removeItem(at: original) }
    guard case .video(let movie) = try await VisualFileImport.open(original) else {
      return XCTFail("Expected video")
    }
    XCTAssertNotEqual(movie.url, original)
    XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
  }
  func testOptionalHundredthsAndLongStopwatchFormatting() {
    var config = FloatingToolConfiguration(kind: .stopwatch)
    XCTAssertEqual(config.snapshot(elapsed: 12.349, date: .distantPast).value, "00:12")
    config.showsHundredths = true
    XCTAssertEqual(config.snapshot(elapsed: 12.349, date: .distantPast).value, "00:12.34")
    XCTAssertEqual(config.snapshot(elapsed: 3_661.99, date: .distantPast).value, "01:01:01.99")
    XCTAssertEqual(FloatingToolConfiguration.time(-2, hundredths: true), "00:00.00")
    XCTAssertEqual(FloatingToolConfiguration.time(.infinity, hundredths: true), "00:00.00")
    XCTAssertEqual(FloatingToolConfiguration.time(59.999, hundredths: true), "00:59.99")
  }

  func testRingsAndHundredthsHaveSubsecondFrameKeysWithoutMakingClocksExpensive() {
    let timer = FloatingToolConfiguration(kind: .countdown)
    XCTAssertNotEqual(
      timer.frameKey(elapsed: 0, date: .distantPast),
      timer.frameKey(elapsed: 0.1, date: .distantPast))
    var watch = FloatingToolConfiguration(kind: .stopwatch)
    XCTAssertEqual(
      watch.frameKey(elapsed: 0, date: .distantPast),
      watch.frameKey(elapsed: 0.1, date: .distantPast))
    watch.showsHundredths = true
    XCTAssertNotEqual(
      watch.frameKey(elapsed: 0, date: .distantPast),
      watch.frameKey(elapsed: 0.1, date: .distantPast))
    let clock = FloatingToolConfiguration(kind: .clock)
    XCTAssertEqual(clock.framesPerSecond, 1)
    XCTAssertEqual(
      clock.frameKey(elapsed: 0, date: Date(timeIntervalSince1970: 1)),
      clock.frameKey(elapsed: 100, date: Date(timeIntervalSince1970: 1.5)))
  }

  func testCircularProgressReallyChangesWithinASecond() {
    let config = FloatingToolConfiguration(kind: .countdown, duration: 2)
    let first = FloatingToolRenderer.render(configuration: config, elapsed: 0.1, date: .distantPast)
    let second = FloatingToolRenderer.render(
      configuration: config, elapsed: 0.2, date: .distantPast)
    XCTAssertEqual(first.size, CGSize(width: 960, height: 540))
    XCTAssertNotEqual(first.pngData(), second.pngData())
    XCTAssertEqual(
      config.snapshot(elapsed: 0.1, date: .distantPast).value,
      config.snapshot(elapsed: 0.2, date: .distantPast).value)
  }

  @MainActor func testClosingTimerCancelsAlarmOnlyWhenPreferenceIsOff() async {
    for keep in [true, false] {
      let driver = Polish11AlarmDriver()
      let config = FloatingToolConfiguration(
        kind: .countdown, alarmWhenFinished: true, keepTimerRunningOnClose: keep)
      let session = FloatingToolSession(configuration: config, alarmScheduler: driver)
      session.resume()
      await session.waitForAlarmUpdate()
      session.pictureInPictureDidClose()
      await session.waitForAlarmUpdate()
      XCTAssertEqual(session.isPlaying, keep)
      XCTAssertEqual(driver.cancels, keep ? 0 : 1)
      session.pause()
      await session.waitForAlarmUpdate()
    }
  }

  @MainActor func testRestoringToCodDoesNotCancelATimerEvenWithClosePreferenceOff() async {
    let driver = Polish11AlarmDriver()
    let config = FloatingToolConfiguration(
      kind: .countdown, alarmWhenFinished: true, keepTimerRunningOnClose: false)
    let session = FloatingToolSession(configuration: config, alarmScheduler: driver)
    session.resume()
    await session.waitForAlarmUpdate()
    session.pictureInPictureDidClose(preservingTimer: true)
    await session.waitForAlarmUpdate()
    XCTAssertTrue(session.isPlaying)
    XCTAssertEqual(driver.cancels, 0)
    session.pause()
    await session.waitForAlarmUpdate()
  }

  @MainActor func testVisualTimerCloseAndStopwatchPauseRespectTheirDifferentPolicies() {
    var uptime = 0.0
    let timer = FloatingToolSession(configuration: .init(kind: .countdown), uptime: { uptime })
    timer.resume()
    timer.pictureInPictureDidClose()
    uptime = 10
    XCTAssertEqual(timer.elapsed, 10)
    let paused = FloatingToolSession(
      configuration: .init(kind: .countdown, keepTimerRunningOnClose: false), uptime: { uptime })
    paused.resume()
    paused.pictureInPictureDidClose()
    uptime = 20
    XCTAssertEqual(paused.elapsed, 0)
    let watch = FloatingToolSession(configuration: .init(kind: .stopwatch), uptime: { uptime })
    watch.resume()
    watch.pictureInPictureDidClose()
    XCTAssertFalse(watch.isPlaying)
  }

  @MainActor func testSystemDeadlineCorrectsProvisionalCountdownAndCannotReviveCancelledTimer()
    async
  {
    let driver = Polish11AlarmDriver()
    var now = Date(timeIntervalSince1970: 1_000)
    var uptime = 0.0
    driver.now = { now }
    let session = FloatingToolSession(
      configuration: .init(kind: .countdown, duration: 10, alarmWhenFinished: true),
      alarmScheduler: driver, now: { now }, uptime: { uptime })
    session.resume()
    await session.waitForAlarmUpdate()
    now += 2
    uptime += 2
    session.alarmDeadlineDidChange(Date(timeIntervalSince1970: 1_011))
    XCTAssertEqual(session.elapsed, 1, accuracy: 0.001)
    XCTAssertEqual(session.alarmDate, Date(timeIntervalSince1970: 1_011))
    session.pause()
    await session.waitForAlarmUpdate()
    session.alarmDeadlineDidChange(Date(timeIntervalSince1970: 1_020))
    XCTAssertFalse(session.isPlaying)
    XCTAssertNil(session.alarmDate)
  }

  func testFavoritesAppendInStableOrderAcrossNewHistoryAndReload() {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodOrderTest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SnapStore(baseDirectory: base)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
    let a = store.add(image: image, origin: .imported, limit: .unlimited)
    let b = store.add(image: image, origin: .imported, limit: .unlimited)
    store.toggleFavorite(b.id)
    store.toggleFavorite(a.id)
    store.add(image: image, origin: .imported, limit: .unlimited)
    XCTAssertEqual(store.favorites.map(\.id), [b.id, a.id])
    store.waitForPendingWrites()
    let loaded = SnapStore(baseDirectory: base)
    XCTAssertEqual(loaded.favorites.map(\.id), [b.id, a.id])
    loaded.toggleFavorite(b.id)
    loaded.toggleFavorite(b.id)
    XCTAssertEqual(loaded.favorites.map(\.id), [a.id, b.id])
    loaded.clearHistory()
    XCTAssertEqual(loaded.favorites.map(\.id), [a.id, b.id])
    loaded.clear()
    loaded.waitForPendingWrites()
    XCTAssertTrue(SnapStore(baseDirectory: base).snaps.isEmpty)
  }

  @MainActor func testUnifiedFileImportRecognizesImagePDFAndRejectsUnsupportedContent() async throws
  {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "CodImportTest-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = UIGraphicsImageRenderer(size: CGSize(width: 70, height: 40)).image { _ in }
    let png = root.appendingPathComponent("test.png")
    try image.pngData()?.write(to: png)
    guard case .image(let imported) = try await VisualFileImport.open(png) else {
      return XCTFail("Expected image")
    }
    XCTAssertEqual(imported.pixelSize, CGSize(width: 70 * image.scale, height: 40 * image.scale))
    let pdf = root.appendingPathComponent("test.pdf")
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData {
      $0.beginPage()
    }
    try data.write(to: pdf)
    guard case .pdf(let reference) = try await VisualFileImport.open(pdf) else {
      return XCTFail("Expected PDF")
    }
    XCTAssertEqual(reference.pageCount, 1)
    let text = root.appendingPathComponent("test.txt")
    try Data("not an image".utf8).write(to: text)
    do {
      _ = try await VisualFileImport.open(text)
      XCTFail("Text isn't a supported visual document")
    } catch { XCTAssertTrue(error is VisualFileImport.ImportError) }
    let corrupt = root.appendingPathComponent("bad.png")
    try Data("corrupt".utf8).write(to: corrupt)
    do {
      _ = try await VisualFileImport.open(corrupt)
      XCTFail("Must reject corrupt images")
    } catch { XCTAssertTrue(error is VisualFileImport.ImportError) }
  }

  func testLegacyTimerAlarmRecordsDecodeWithoutNewEstimationField() throws {
    let data = Data("[{\"id\":\"8C951979-30DD-48F5-A35E-9F6EB32172AA\",\"date\":0}]".utf8)
    XCTAssertNil(
      try JSONDecoder().decode([FloatingTimerAlarmRecord].self, from: data).first?.estimated)
  }
}

@MainActor private final class Polish11AlarmDriver: FloatingTimerAlarmScheduling {
  var cancels = 0
  var now: () -> Date = Date.init
  func schedule(id: UUID, after duration: TimeInterval) async throws -> Date {
    now().addingTimeInterval(duration)
  }
  func cancel(id: UUID) throws { cancels += 1 }
}
