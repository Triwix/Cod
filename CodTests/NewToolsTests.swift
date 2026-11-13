import XCTest
@testable import Cod

/// Countdown to a date, World Clock, System Monitor, teleprompter Lines mode,
/// image sets, and the tolerant decoder for saved tool settings.
final class NewToolsTests: XCTestCase {
  // MARK: Teleprompter lines

  func testLinesSplitOnBreaksSentencesAndLongRuns() {
    let text = "First line.\n\nSecond one! Third here\n" + Array(repeating: "word", count: 15).joined(separator: " ")
    let lines = LinePresentation.split(text)
    XCTAssertEqual(lines[0], "First line.")
    XCTAssertEqual(lines[1], "Second one!")
    XCTAssertEqual(lines[2], "Third here")
    XCTAssertEqual(lines[3].split(separator: " ").count, 12)
    XCTAssertEqual(lines[4].split(separator: " ").count, 3)
  }

  func testLinesAdvanceInProportionToWords() {
    // 60 wpm: one second per word.
    let lines = LinePresentation(text: "one two\nthree\nfour five six", wordsPerMinute: 60)
    XCTAssertEqual(lines.duration, 6, accuracy: 0.001)
    XCTAssertEqual(lines.frame(at: 0).current, "one two")
    XCTAssertEqual(lines.frame(at: 1.9).current, "one two")
    XCTAssertEqual(lines.frame(at: 2.1).current, "three")
    let last = lines.frame(at: 99)
    XCTAssertEqual(last.current, "four five six")
    XCTAssertEqual(last.index, 2)
    XCTAssertEqual(last.count, 3)
    XCTAssertEqual(lines.frame(at: 0).upcoming, ["three", "four five six"])
  }

  // MARK: Countdown to a date

  func testEventCountdownFormatsDaysHoursAndFinishes() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    XCTAssertEqual(EventCountdownFormatting.remaining(until: now.addingTimeInterval(65), from: now), "01:05")
    XCTAssertEqual(EventCountdownFormatting.remaining(until: now.addingTimeInterval(3_725), from: now), "01:02:05")
    XCTAssertEqual(
      EventCountdownFormatting.remaining(until: now.addingTimeInterval(2 * 86_400 + 61), from: now), "2d 00:01:01")
    XCTAssertNil(EventCountdownFormatting.remaining(until: now, from: now))
    XCTAssertNil(EventCountdownFormatting.remaining(until: now.addingTimeInterval(-5), from: now))
  }

  func testEventSnapshotShowsTitleAndFinishedState() throws {
    var config = FloatingToolConfiguration(kind: .event)
    config.eventTitle = "Launch"
    let now = Date()
    config.eventDate = now.addingTimeInterval(90)
    try config.validate()
    let running = config.snapshot(elapsed: 0, date: now)
    XCTAssertEqual(running.title, "Launch")
    XCTAssertEqual(running.value, "01:30")
    XCTAssertFalse(running.isFinished)
    let done = config.snapshot(elapsed: 0, date: now.addingTimeInterval(100))
    XCTAssertTrue(done.isFinished)
  }

  // MARK: World clock

  func testWorldClockRowsShowCityTimeAndDayDifference() throws {
    // 23:30 UTC on Jan 1 is already Jan 2 in Tokyo and still Jan 1 in New York.
    let date = Date(timeIntervalSince1970: 1_704_151_800)
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let rows = WorldClockFormatting.rows(
      zones: ["Asia/Tokyo", "America/New_York", "Not/AZone"], date: date, uses24Hour: true, home: utc)
    XCTAssertEqual(rows.map(\.label), ["Tokyo", "New York"], "Unknown zones are skipped")
    XCTAssertEqual(rows[0].value, "08:30")
    XCTAssertEqual(rows[0].note, "Tomorrow")
    XCTAssertEqual(rows[1].value, "18:30")
    XCTAssertEqual(rows[1].note, "")
  }

  func testWorldClockValidationRequiresOneToFourKnownZones() {
    var config = FloatingToolConfiguration(kind: .worldClock)
    config.worldClockZones = []
    XCTAssertThrowsError(try config.validate())
    config.worldClockZones = ["Europe/London", "Bad/Zone"]
    XCTAssertThrowsError(try config.validate())
    config.worldClockZones = ["Europe/London", "Asia/Tokyo", "UTC", "America/Chicago", "Europe/Paris"]
    XCTAssertThrowsError(try config.validate())
    config.worldClockZones = ["Europe/London", "Asia/Tokyo"]
    XCTAssertNoThrow(try config.validate())
  }

  // MARK: System monitor

  func testNetworkRatesHandleWrapAndShortIntervals() throws {
    let a = NetworkCounters(received: 1_000, sent: 500, at: 10)
    let b = NetworkCounters(received: 3_000, sent: 400, at: 12)
    let rates = try XCTUnwrap(NetworkCounters.rates(from: a, to: b))
    XCTAssertEqual(rates.down, 1_000, accuracy: 0.001)
    XCTAssertEqual(rates.up, 0, "A counter reset reads as no traffic, not a spike")
    XCTAssertNil(NetworkCounters.rates(from: a, to: NetworkCounters(received: 2_000, sent: 600, at: 10.1)))
  }

  func testMetricTextIsReadable() {
    XCTAssertEqual(SystemMetrics.rateText(512), "512 B/s")
    XCTAssertEqual(SystemMetrics.rateText(1_536), "1.5 KB/s")
    XCTAssertEqual(SystemMetrics.rateText(250_000_000), "250 MB/s")
    XCTAssertEqual(SystemMetrics.rateText(nil), "—")
    var metrics = SystemMetrics(batteryLevel: 0.87, batteryState: .charging, thermalState: .fair)
    XCTAssertEqual(metrics.batteryText, "87% ⚡︎")
    XCTAssertEqual(metrics.thermalText, "Warm")
    metrics.speed = 10
    XCTAssertEqual(metrics.speedText(metric: true), "36 km/h")
    XCTAssertEqual(metrics.speedText(metric: false), "22 mph")
  }

  func testSystemSnapshotShowsOnlyTheChosenReadingsInAFixedOrder() throws {
    var config = FloatingToolConfiguration(kind: .system)
    var metrics = SystemMetrics(batteryLevel: 0.5, thermalState: .nominal, downloadRate: 2_000, uploadRate: 100, speed: 5)
    metrics.cpuUsage = 0.234
    metrics.freeStorage = 48_200_000_000
    metrics.memoryUsed = 3 * 1_073_741_824
    metrics.memoryTotal = 8 * 1_073_741_824
    metrics.connection = "Wi-Fi"
    var rows = config.snapshot(elapsed: 0, date: Date(), metrics: metrics).rows
    XCTAssertEqual(rows.map(\.label), ["Battery", "Temp", "Download", "Upload"])
    XCTAssertFalse(rows.contains { $0.label == "Speed" }, "Speed is its own tool now")
    config.systemMetrics = [.cpu, .battery, .storage, .memory, .connection]
    XCTAssertEqual(config.systemMetrics, [.battery, .connection, .storage, .memory, .cpu])
    rows = config.snapshot(elapsed: 0, date: Date(), metrics: metrics).rows
    XCTAssertEqual(rows.map(\.value), ["50%", "Wi-Fi", "48.2 GB free", "3.0 / 8.0 GB", "23%"])
    config.systemMetrics = []
    XCTAssertThrowsError(try config.validate(), "A monitor needs at least one reading")
  }

  func testCPUUsageComesFromTickDifferences() {
    let old = CPUTicks(busy: 100, total: 1_000)
    XCTAssertEqual(CPUTicks.usage(from: old, to: CPUTicks(busy: 350, total: 2_000)) ?? -1, 0.25, accuracy: 0.0001)
    XCTAssertNil(CPUTicks.usage(from: old, to: old), "No time passed")
    XCTAssertNil(CPUTicks.usage(from: old, to: CPUTicks(busy: 50, total: 900)), "Counters reset")
    XCTAssertNotNil(CPUTicks.read())
    XCTAssertNotNil(DeviceReadings.memoryUsed())
    XCTAssertNotNil(DeviceReadings.freeStorage())
  }

  func testSpeedometerShowsNumberAndUnits() {
    var config = FloatingToolConfiguration(kind: .speedometer)
    config.usesMetricSpeed = true
    var metrics = SystemMetrics()
    var snapshot = config.snapshot(elapsed: 0, date: Date(), metrics: metrics)
    XCTAssertEqual(snapshot.value, "—")
    XCTAssertEqual(snapshot.detail, "Waiting for location")
    metrics.speed = 10
    snapshot = config.snapshot(elapsed: 0, date: Date(), metrics: metrics)
    XCTAssertEqual(snapshot.value, "36")
    XCTAssertEqual(snapshot.detail, "km/h")
    config.usesMetricSpeed = false
    XCTAssertEqual(config.snapshot(elapsed: 0, date: Date(), metrics: metrics).value, "22")
    XCTAssertTrue(FloatingToolKind.speedometer.samplesSystem)
    XCTAssertEqual(FloatCategory.category(for: .speedometer), .system)
  }

  // MARK: Paged documents

  @MainActor
  func testPagedSetsStartPausedAndSkipTurnsOnePage() {
    var config = FloatingToolConfiguration(kind: .slideshow)
    XCTAssertFalse(config.startsPaused, "Image sets keep playing by default")
    config.slideNames = ["a.jpg", "b.jpg", "c.jpg"]
    config.slideInterval = 10
    config.startsPaused = true
    config.setName = "Menu · 1–3"
    let session = FloatingToolSession(configuration: config)
    XCTAssertEqual(session.title, "Menu · 1–3")
    XCTAssertFalse(session.isPlaying)
    session.skip(by: 15)
    XCTAssertEqual(Slideshow.index(elapsed: session.elapsed, interval: 10, count: 3), 1)
    XCTAssertFalse(session.isPlaying, "Turning a page keeps it paused")
    session.skip(by: 15)
    session.skip(by: 15)
    XCTAssertEqual(Slideshow.index(elapsed: session.elapsed, interval: 10, count: 3), 2, "Stops on the last page")
    session.skip(by: -15)
    XCTAssertEqual(Slideshow.index(elapsed: session.elapsed, interval: 10, count: 3), 1)
  }

  @MainActor
  func testLiveSourceLeavesPagedSetsPausedWhenPiPStarts() throws {
    var config = FloatingToolConfiguration(kind: .slideshow)
    config.slideNames = ["a.jpg", "b.jpg"]
    config.startsPaused = true
    let paged = FloatingToolSession(configuration: config)
    LiveFloatSource(session: paged).activate()
    XCTAssertFalse(paged.isPlaying)
    config.startsPaused = false
    let playing = FloatingToolSession(configuration: config)
    LiveFloatSource(session: playing).activate()
    XCTAssertTrue(playing.isPlaying)
  }

  func testPDFPagesPickTheClosestWindowShape() {
    XCTAssertEqual(FloatWindowShape.closest(to: CGSize(width: 612, height: 792)), .tall, "US Letter")
    XCTAssertEqual(FloatWindowShape.closest(to: CGSize(width: 1920, height: 1080)), .wide, "Slides")
    XCTAssertEqual(FloatWindowShape.closest(to: CGSize(width: 1000, height: 1000)), .square)
    XCTAssertEqual(FloatWindowShape.closest(to: CGSize(width: 1080, height: 1920)), .portrait)
    XCTAssertEqual(FloatWindowShape.closest(to: .zero), .wide)
  }

  // MARK: Window shape

  func testEveryToolRendersAtItsWindowShape() throws {
    let kinds: [FloatingToolKind] = [.countdown, .stopwatch, .clock, .pomodoro, .event, .worldClock, .system, .speedometer, .teleprompter]
    for shape in FloatWindowShape.allCases {
      for kind in kinds {
        var config = FloatingToolConfiguration(kind: kind)
        config.windowShape = shape
        if kind == .teleprompter { config.text = FloatingToolConfiguration.exampleScript }
        let image = FloatingToolRenderer.render(configuration: config, elapsed: 2, date: Date())
        XCTAssertEqual(image.size, shape.size, "\(kind) at \(shape)")
      }
    }
    var wide = FloatingToolConfiguration(kind: .teleprompter)
    wide.text = FloatingToolConfiguration.exampleScript
    var tall = wide
    tall.windowShape = .portrait
    XCTAssertLessThan(
      FloatingToolRenderer.ScriptLayout(tall).travel, FloatingToolRenderer.ScriptLayout(wide).travel * 2,
      "A tall window shows more of the script at once")
    XCTAssertNotEqual(tall.frameKey(elapsed: 1, date: Date()), 0)
    XCTAssertNotEqual(tall, wide, "Shape is part of a saved setup")
  }

  // MARK: Image sets

  func testSlideIndexFollowsTheIntervalAndHoldsTheLastImage() {
    XCTAssertEqual(Slideshow.index(elapsed: 0, interval: 5, count: 3), 0)
    XCTAssertEqual(Slideshow.index(elapsed: 5.01, interval: 5, count: 3), 1)
    XCTAssertEqual(Slideshow.index(elapsed: 500, interval: 5, count: 3), 2)
    XCTAssertEqual(Slideshow.index(elapsed: .nan, interval: 5, count: 3), 0)
  }

  func testImageSetsNeedTwoToThirtyStoredImages() {
    var config = FloatingToolConfiguration(kind: .slideshow)
    config.slideNames = ["a.jpg"]
    XCTAssertThrowsError(try config.validate())
    config.slideNames = ["a.jpg", "b.jpg"]
    XCTAssertNoThrow(try config.validate())
    config.slideInterval = 0.5
    XCTAssertThrowsError(try config.validate())
  }

  // MARK: Saved settings

  func testOlderSavedSettingsStillDecodeWithNewDefaults() throws {
    // A preset saved before these tools existed has none of the new keys.
    var timer = FloatingToolConfiguration(kind: .countdown)
    timer.duration = 120
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(timer)) as? [String: Any])
    for key in json.keys where key.hasPrefix("stored") { json.removeValue(forKey: key) }
    XCTAssertFalse(json.keys.contains { $0.hasPrefix("stored") })
    let old = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(FloatingToolConfiguration.self, from: old)
    XCTAssertEqual(decoded.kind, .countdown)
    XCTAssertEqual(decoded.duration, 120)
    XCTAssertEqual(decoded.worldClockZones, FloatingToolConfiguration(kind: .worldClock).worldClockZones)
    XCTAssertFalse(decoded.showsSpeed)
    XCTAssertEqual(decoded.windowShape, .wide)
    XCTAssertEqual(decoded.systemMetrics, SystemMetric.defaults)
    XCTAssertEqual(decoded.prompterMode, .scroll)
    // And a full round trip keeps everything.
    var config = FloatingToolConfiguration(kind: .event)
    config.eventTitle = "Trip"
    config.worldClockZones = ["Asia/Tokyo"]
    let copy = try JSONDecoder().decode(FloatingToolConfiguration.self, from: JSONEncoder().encode(config))
    XCTAssertEqual(copy, config)
  }

  // MARK: Home

  @MainActor
  func testRecentFloatsDeduplicateAndCapUnstarredSetups() {
    let suite = "Cod.Recents.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let recents = RecentFloats(defaults: defaults)
    var timer = FloatingToolConfiguration(kind: .countdown)
    for minutes in 1...(RecentFloats.limit + 2) {
      timer.duration = Double(minutes * 60)
      recents.record(timer)
    }
    XCTAssertEqual(recents.items.count, RecentFloats.limit)
    XCTAssertEqual(recents.items.first?.configuration.duration, Double((RecentFloats.limit + 2) * 60))
    recents.record(recents.items[3].configuration)
    XCTAssertEqual(recents.items.count, RecentFloats.limit, "Floating a recent again moves it, not duplicates it")
    XCTAssertEqual(RecentFloats(defaults: defaults).items.count, RecentFloats.limit, "Recents persist")
  }

  @MainActor
  func testStarredSetupsStayPinnedSurviveTrimmingAndKeepTheirStar() throws {
    let suite = "Cod.Recents.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let recents = RecentFloats(defaults: defaults)
    var timer = FloatingToolConfiguration(kind: .countdown)
    timer.duration = 60
    recents.record(timer)
    let favorite = try XCTUnwrap(recents.items.first)
    recents.toggleStar(favorite.id)
    for minutes in 2...(RecentFloats.limit + 5) {
      timer.duration = Double(minutes * 60)
      recents.record(timer)
    }
    XCTAssertTrue(recents.items.contains { $0.id == favorite.id && $0.isStarred }, "Starred setups aren't trimmed")
    XCTAssertEqual(recents.items.filter { !$0.isStarred }.count, RecentFloats.limit)
    XCTAssertEqual(recents.forHome.first?.id, favorite.id, "Home lists starred setups first")
    recents.record(favorite.configuration)
    XCTAssertTrue(recents.items.first?.isStarred ?? false, "Floating it again keeps the star")
    recents.clearUnstarred()
    XCTAssertEqual(recents.items.count, 1)
    XCTAssertTrue(RecentFloats(defaults: defaults).items.first?.isStarred ?? false, "Stars persist")
  }

  func testBuild29RecentsDecodeWithoutStars() throws {
    var item = RecentFloat(configuration: FloatingToolConfiguration(kind: .stopwatch))
    item.starred = nil
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([item])) as? [[String: Any]])
    json[0].removeValue(forKey: "starred")
    let decoded = try JSONDecoder().decode([RecentFloat].self, from: JSONSerialization.data(withJSONObject: json))
    XCTAssertFalse(decoded[0].isStarred)
  }

  func testFloatingAnImageAgainMovesItToTheTopWithoutACopy() {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("CodTouchTest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: base) }
    let store = SnapStore(baseDirectory: base)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
    let first = store.add(image: image, origin: .imported, limit: .ten)
    for _ in 0..<9 { store.add(image: image, origin: .imported, limit: .ten) }
    store.touch(first.id)
    XCTAssertEqual(store.snaps.count, 10)
    XCTAssertEqual(store.snaps.first?.id, first.id)
    XCTAssertNotNil(store.snaps.first?.lastUsedAt)
    store.add(image: image, origin: .imported, limit: .ten)
    XCTAssertTrue(store.snaps.contains { $0.id == first.id }, "A reused item counts as recent for the history limit")
    store.waitForPendingWrites()
    XCTAssertNotNil(SnapStore(baseDirectory: base).snaps.first { $0.id == first.id }?.lastUsedAt)
  }

  func testRecentEntriesMatchSearchAndSortByLastUse() {
    var snap = Snap(pixelWidth: 10, pixelHeight: 10, origin: .screenshot)
    snap.createdAt = Date(timeIntervalSince1970: 100)
    snap.recognizedText = "Gate B12"
    XCTAssertTrue(RecentEntry.snap(snap).matches("b12"))
    XCTAssertEqual(RecentEntry.snap(snap).date, Date(timeIntervalSince1970: 100))
    snap.lastUsedAt = Date(timeIntervalSince1970: 500)
    XCTAssertEqual(RecentEntry.snap(snap).date, Date(timeIntervalSince1970: 500))
    var prompter = FloatingToolConfiguration(kind: .teleprompter)
    prompter.text = "Quarterly update"
    XCTAssertTrue(RecentEntry.tool(RecentFloat(configuration: prompter)).matches("quarterly"))
    XCTAssertFalse(RecentEntry.tool(RecentFloat(configuration: prompter)).matches("gate"))
  }

  func testEveryTimeAndSystemToolBelongsToOneCategory() {
    for kind in FloatingToolKind.allCases where ![.teleprompter, .document, .slideshow].contains(kind) {
      XCTAssertNotNil(FloatCategory.category(for: kind), "\(kind) has no Home category")
    }
  }
}
