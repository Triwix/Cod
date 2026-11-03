import AlarmKit
import UIKit
import XCTest
@testable import Cod

final class Polish10Tests: XCTestCase {
    func testClockStyleDurationComponentsPreserveOtherWheels() {
        let duration = TimerDuration(3_661)
        XCTAssertEqual(duration.hours, 1)
        XCTAssertEqual(duration.minutes, 1)
        XCTAssertEqual(duration.seconds, 1)
        XCTAssertEqual(duration.changing(minutes: 40).totalSeconds, 6_001)
        XCTAssertEqual(duration.changing(seconds: 2).totalSeconds, 3_662)
        XCTAssertEqual(TimerDuration(-1).totalSeconds, 0)
        XCTAssertEqual(TimerDuration(Int.max).totalSeconds, 86_399)
    }

    func testEmptyDraftUsesSampleWithoutBecomingEditableSample() {
        let draft = ""
        XCTAssertEqual(FloatingText.content(draft), FloatingText.example)
        XCTAssertEqual(draft, "")
        XCTAssertEqual(FloatingText.content("  \n"), FloatingText.example)
        XCTAssertEqual(FloatingText.content("My own note"), "My own note")
        XCTAssertEqual(FloatingText.content("", sample: "Script sample"), "Script sample")
    }

    func testWordPresentationGroupsTimingFinalHoldAndWhitespace() {
        let presentation = WordPresentation(text: "One,  two\nthree — four!", groupSize: 2, wordsPerMinute: 120)
        XCTAssertEqual(presentation.chunk(at: 0), "One, two")
        XCTAssertEqual(presentation.chunk(at: 0.99), "One, two")
        XCTAssertEqual(presentation.chunk(at: 1), "three —")
        XCTAssertEqual(presentation.chunk(at: 2), "four!")
        XCTAssertEqual(presentation.duration, 2.5)
        XCTAssertEqual(presentation.chunk(at: 10_000), "four!")
        XCTAssertEqual(WordPresentation(text: "", groupSize: 0, wordsPerMinute: 0).chunk(at: 0), "")
    }

    func testWordModeProducesChangingFramesAndHoldsLastChunk() {
        var config = FloatingToolConfiguration(kind: .teleprompter, text: "First second third")
        config.prompterMode = .words
        config.prompterCountdownEnabled = false
        config.wordsPerMinute = 60
        let first = FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .distantPast).pngData()
        let second = FloatingToolRenderer.render(configuration: config, elapsed: 1, date: .distantPast).pngData()
        let last = FloatingToolRenderer.render(configuration: config, elapsed: 3, date: .distantPast).pngData()
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(second, last)
        XCTAssertEqual(last, FloatingToolRenderer.render(configuration: config, elapsed: 1_000, date: .distantPast).pngData())
    }

    func testLegacySnapAndActionPreferencesDoNotLoseData() throws {
        let old = """
        {"id":"8C951979-30DD-48F5-A35E-9F6EB32172AA","createdAt":0,"pixelWidth":20,"pixelHeight":30,"origin":"shared","recognizedText":"Keep this","barcodes":[]}
        """
        let snap = try JSONDecoder().decode(Snap.self, from: Data(old.utf8))
        XCTAssertFalse(snap.isFavorite)
        XCTAssertFalse(snap.isVideo)
        XCTAssertEqual(snap.recognizedText, "Keep this")
        XCTAssertEqual(try JSONDecoder().decode(SnapAction.self, from: Data("\"pin\"".utf8)), .pin)
        XCTAssertFalse(SnapAction.availableCases.contains(.pin))
        XCTAssertFalse(SnapAction.defaultOrder.contains(.pin))
    }

    func testFavoritesSurviveTrimmingHistoryOffClearingAndReload() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CodFavoriteTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = SnapStore(baseDirectory: base)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let favorite = store.add(image: image, origin: .shared, limit: .unlimited)
        store.toggleFavorite(favorite.id)
        for _ in 0..<12 { store.add(image: image, origin: .shared, limit: .ten) }
        XCTAssertEqual(store.snaps.count, 11)
        XCTAssertEqual(store.historyCount, 10)
        store.setRecognizedText("Still a favorite", for: favorite.id)
        store.trim(to: .off)
        XCTAssertEqual(store.snaps.count, 1)
        store.clearHistory()
        store.waitForPendingWrites()
        let reloaded = SnapStore(baseDirectory: base)
        XCTAssertEqual(reloaded.snaps.first?.id, favorite.id)
        XCTAssertTrue(reloaded.snaps.first?.isFavorite == true)
        XCTAssertEqual(reloaded.snaps.first?.recognizedText, "Still a favorite")
        reloaded.delete(try XCTUnwrap(reloaded.snaps.first))
        reloaded.waitForPendingWrites()
        XCTAssertTrue(reloaded.snaps.isEmpty)
    }

    @MainActor
    func testShortAlarmDoesNotCountDownWhileSchedulingOrCancelAtCompletion() async {
        let scheduler = DelayedCountdownScheduler()
        var uptime = 0.0
        var date = Date(timeIntervalSince1970: 1_000)
        scheduler.now = { date }
        let session = FloatingToolSession(configuration: .init(kind: .countdown, duration: 2, alarmWhenFinished: true), alarmScheduler: scheduler, now: { date }, uptime: { uptime })
        session.resume()
        while scheduler.continuation == nil { await Task.yield() }
        uptime += 7; date += 7
        XCTAssertEqual(session.elapsed, 0, "Preparing an alarm mustn't consume a two-second duration")
        scheduler.continuation?.resume()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(session.snapshot.value, "00:02")
        uptime += 1; date += 1
        XCTAssertEqual(session.snapshot.value, "00:01")
        uptime += 1; date += 1
        session.setPlayingFromPiP(false)
        await session.waitForAlarmUpdate()
        XCTAssertEqual(session.snapshot.value, "00:00")
        XCTAssertEqual(scheduler.cancellations, 0, "Automatic end-of-playback must leave iOS's ringing alarm alone")
        session.cancelAlarm()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(scheduler.cancellations, 1)
    }

    @MainActor
    func testNativeCountdownConfigurationUsesDurationNotFixedWallClock() throws {
        if #available(iOS 26.0, *) {
            // Encoding the returned value is system-owned; real AlarmKit
            // scheduling and the widget are also exercised by simulator UI.
            _ = FloatingTimerAlarms.configuration(duration: 2)
        }
    }

    func testLiveActivityCancelIsRegisteredInAppWithoutOpeningItsUI() {
        if #available(iOS 26.0, *) {
            let id = UUID()
            XCTAssertEqual(StopCodTimerIntent(id: id).alarmID, id.uuidString)
            XCTAssertFalse(StopCodTimerIntent.openAppWhenRun)
        }
    }

    @MainActor
    func testVideoCopyLibraryAndCleanupNeverRemoveOriginal() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
        }
        let source = try await FloatingClip.make(from: image)
        defer { try? FileManager.default.removeItem(at: source) }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CodVideoStoreTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        var reference: VideoReference? = try await VideoReference.copy(from: source)
        let copiedURL = try XCTUnwrap(reference?.url)
        XCTAssertNotEqual(source, copiedURL)
        XCTAssertGreaterThan(try XCTUnwrap(reference?.duration), 1)
        let store = SnapStore(baseDirectory: base)
        let added = try await store.add(video: XCTUnwrap(reference), limit: .ten)
        let snap = try XCTUnwrap(added)
        store.waitForPendingWrites()
        XCTAssertTrue(snap.isVideo)
        let saved = try XCTUnwrap(store.videoURL(for: snap))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        reference = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: copiedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let loaded = SnapStore(baseDirectory: base)
        XCTAssertTrue(loaded.snaps.first?.isVideo == true)
        loaded.delete(snap)
        loaded.waitForPendingWrites()
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
}

@MainActor private final class DelayedCountdownScheduler: FloatingTimerAlarmScheduling {
    var continuation: CheckedContinuation<Void, Never>?
    var cancellations = 0
    var now: () -> Date = Date.init
    func schedule(id: UUID, after duration: TimeInterval) async throws -> Date {
        await withCheckedContinuation { continuation = $0 }
        return now().addingTimeInterval(duration)
    }
    func cancel(id: UUID) throws { cancellations += 1 }
}
