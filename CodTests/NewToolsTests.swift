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

  func testSystemSnapshotListsMetricsAndOnlyShowsSpeedWhenOn() {
    var config = FloatingToolConfiguration(kind: .system)
    let metrics = SystemMetrics(batteryLevel: 0.5, thermalState: .nominal, downloadRate: 2_000, uploadRate: 100, speed: 5)
    var rows = config.snapshot(elapsed: 0, date: Date(), metrics: metrics).rows
    XCTAssertEqual(rows.map(\.label), ["Battery", "Temperature", "Download", "Upload"])
    config.showsSpeed = true
    rows = config.snapshot(elapsed: 0, date: Date(), metrics: metrics).rows
    XCTAssertEqual(rows.last?.label, "Speed")
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
  func testRecentFloatsDeduplicateAndCapAtSix() {
    let suite = "Cod.Recents.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let recents = RecentFloats(defaults: defaults)
    var timer = FloatingToolConfiguration(kind: .countdown)
    for minutes in 1...8 {
      timer.duration = Double(minutes * 60)
      recents.record(timer)
    }
    XCTAssertEqual(recents.items.count, RecentFloats.limit)
    XCTAssertEqual(recents.items.first?.configuration.duration, 480)
    recents.record(recents.items[3].configuration)
    XCTAssertEqual(recents.items.count, RecentFloats.limit, "Floating a recent again moves it, not duplicates it")
    XCTAssertEqual(RecentFloats(defaults: defaults).items.count, RecentFloats.limit, "Recents persist")
  }

  func testEveryTimeAndSystemToolBelongsToOneCategory() {
    for kind in FloatingToolKind.allCases where ![.teleprompter, .document, .slideshow].contains(kind) {
      XCTAssertNotNil(FloatCategory.category(for: kind), "\(kind) has no Home category")
    }
  }
}
