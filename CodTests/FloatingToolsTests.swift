import AVFoundation
import AVKit
import AlarmKit
import PDFKit
import UIKit
import XCTest
@testable import Cod

final class FloatingToolsTests: XCTestCase {
    func testTimelineStartsPausedAndNeverCountsCallbacks() {
        var state = FloatingToolTimeline()
        XCTAssertEqual(state.elapsed(at: 100), 0)
        state.resume(at: 100)
        XCTAssertEqual(state.elapsed(at: 175), 75)
        state.resume(at: 180)
        XCTAssertEqual(state.elapsed(at: 200), 100, "Repeated resume must not reset the start time")
        state.pause(at: 210)
        XCTAssertEqual(state.elapsed(at: 900), 110)
        state.pause(at: 901)
        state.resume(at: 1_000)
        XCTAssertEqual(state.elapsed(at: 1_020), 130)
        state.reset(at: 1_020)
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.elapsed(at: 1_024), 4)
        state.pause(at: 1_024)
        state.reset(at: 2_000)
        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.elapsed(at: 9_000), 0)
    }

    func testCountdownRoundsUpAndStopsAtZero() {
        let config = FloatingToolConfiguration(kind: .countdown, duration: 65)
        XCTAssertEqual(config.snapshot(elapsed: 0, date: .distantPast).value, "01:05")
        XCTAssertEqual(config.snapshot(elapsed: 0.9, date: .distantPast).value, "01:05")
        XCTAssertEqual(config.snapshot(elapsed: 1, date: .distantPast).value, "01:04")
        let finished = config.snapshot(elapsed: 6_000, date: .distantPast)
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.value, "00:00")
        XCTAssertEqual(finished.progress, 1)
    }

    func testStopwatchAndHourFormatting() {
        XCTAssertEqual(FloatingToolConfiguration.time(3_661.9), "01:01:01")
        XCTAssertEqual(FloatingToolConfiguration.time(-5), "00:00")
        XCTAssertEqual(FloatingToolConfiguration.time(.infinity), "00:00")
        let config = FloatingToolConfiguration(kind: .stopwatch)
        XCTAssertEqual(config.snapshot(elapsed: 65.9, date: .distantPast).value, "01:05")
        XCTAssertFalse(config.snapshot(elapsed: 1_000_000, date: .distantPast).isFinished)
    }

    func testPomodoroFocusBreakBoundaryAndFinalSession() {
        let config = FloatingToolConfiguration(kind: .pomodoro, focusDuration: 60, breakDuration: 60, rounds: 2)
        XCTAssertEqual(config.totalPomodoroDuration, 180)
        XCTAssertEqual(config.snapshot(elapsed: 59, date: .distantPast).title, "Focus")
        XCTAssertEqual(config.snapshot(elapsed: 60, date: .distantPast).title, "Break")
        XCTAssertEqual(config.snapshot(elapsed: 119, date: .distantPast).detail, "Session 1 of 2")
        let second = config.snapshot(elapsed: 120, date: .distantPast)
        XCTAssertEqual(second.title, "Focus")
        XCTAssertEqual(second.value, "01:00")
        XCTAssertEqual(second.detail, "Session 2 of 2")
        XCTAssertTrue(config.snapshot(elapsed: 180, date: .distantPast).isFinished)
    }

    func testOnePomodoroDoesNotAppendAFinalBreak() {
        let config = FloatingToolConfiguration(kind: .pomodoro, focusDuration: 60, breakDuration: 300, rounds: 1)
        XCTAssertEqual(config.totalPomodoroDuration, 60)
        XCTAssertTrue(config.snapshot(elapsed: 60, date: .distantPast).isFinished)
    }

    func testWorldClockUsesTheSelectedZone() {
        let date = Date(timeIntervalSince1970: 12 * 3_600)
        let utc = FloatingToolConfiguration(kind: .clock, timeZoneIdentifier: "GMT", uses24HourClock: true)
        let tokyo = FloatingToolConfiguration(kind: .clock, timeZoneIdentifier: "Asia/Tokyo", uses24HourClock: true)
        XCTAssertEqual(utc.snapshot(elapsed: 0, date: date).value, "12:00:00")
        XCTAssertEqual(tokyo.snapshot(elapsed: 0, date: date).value, "21:00:00")
        XCTAssertTrue(tokyo.snapshot(elapsed: 0, date: date).title.hasPrefix("Tokyo · "))
    }

    @MainActor
    func testCurrentTimeDoesNotFreezeItsPreviewWhenClosed() {
        var date = Date(timeIntervalSince1970: 1_000)
        let session = FloatingToolSession(configuration: .init(kind: .clock), now: { date })
        XCTAssertEqual(FloatingToolKind.clock.title, "Current Time")
        session.pause()
        date = date.addingTimeInterval(3_600)
        XCTAssertEqual(session.displayDate, date, "Current Time reads the system date even when its old PiP is closed")
    }

    @MainActor
    func testStopwatchPauseFreezesElapsedTimeUntilResumed() {
        var uptime: TimeInterval = 100
        let session = FloatingToolSession(configuration: .init(kind: .stopwatch), uptime: { uptime })
        session.resume()
        uptime = 165
        session.pause()
        uptime = 3_600
        XCTAssertEqual(session.elapsed, 65)
        XCTAssertFalse(session.isPlaying)
        session.resume()
        uptime += 10
        XCTAssertEqual(session.elapsed, 75)
    }

    func testDefaultPrompterScriptIsValidAndActuallyScrolls() throws {
        let configuration = FloatingToolConfiguration(kind: .teleprompter, text: FloatingToolConfiguration.exampleScript)
        try configuration.validate()
        XCTAssertGreaterThan(FloatingToolRenderer.scriptTravel(configuration), 540)
    }

    func testCustomColorsReachTextAndEveryLiveRenderer() throws {
        let colors = FloatingColors(background: .magenta, foreground: .cyan)
        let text = try FloatingText.render("Real text", colors: colors)
        let textCorner = try Self.pixel(XCTUnwrap(text.cropped(toPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1))))
        XCTAssertGreaterThan(textCorner.red, 245)
        XCTAssertGreaterThan(textCorner.blue, 245)
        for kind in FloatingToolKind.allCases {
            let config = FloatingToolConfiguration(kind: kind, text: "Example", customColors: colors)
            let image = FloatingToolRenderer.render(configuration: config, elapsed: 0, date: .distantPast)
            let corner = try Self.pixel(XCTUnwrap(image.cropped(toPixelRect: CGRect(x: 0, y: 0, width: 1, height: 1))))
            XCTAssertGreaterThan(corner.red, 245, kind.title)
            XCTAssertGreaterThan(corner.blue, 245, kind.title)
            XCTAssertEqual(config.colors.foreground, .cyan)
        }
        let script = FloatingToolRenderer.script(.init(kind: .teleprompter, text: "Example", customColors: colors))
        XCTAssertEqual(script.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, .cyan)
    }

    @MainActor
    func testAlarmTracksTimerPauseResumeAndRestart() async {
        let driver = RecordingTimerAlarmDriver()
        var uptime: TimeInterval = 100
        var now = Date(timeIntervalSince1970: 1_000)
        let session = FloatingToolSession(configuration: .init(kind: .countdown, duration: 60, alarmWhenFinished: true),
                                          alarmScheduler: driver, now: { now }, uptime: { uptime })
        driver.now = { now }
        session.resume()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.dates.last, now.addingTimeInterval(60))
        session.resume()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.dates.count, 1, "Repeated Float/start calls must not restart or duplicate the alarm")
        uptime += 20
        now += 20
        session.pause()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.cancelled.last, session.id)
        XCTAssertNil(session.alarmDate)
        uptime += 300
        now += 300
        session.resume()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.dates.last, now.addingTimeInterval(40))
        session.reset()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.dates.last, now.addingTimeInterval(60))
        XCTAssertNil(session.alarmError)
    }

    @MainActor
    func testFinishingOrClosingAlarmTimerDoesNotCancelItsSound() async throws {
        let driver = RecordingTimerAlarmDriver()
        let session = FloatingToolSession(configuration: .init(kind: .countdown, duration: 60, alarmWhenFinished: true), alarmScheduler: driver)
        let source = LiveFloatSource(session: session)
        try source.start()
        source.activate()
        await session.waitForAlarmUpdate()
        source.stop()
        XCTAssertTrue(session.isPlaying, "The alarm timer keeps running when its PiP closes or the phone locks")
        session.complete()
        await session.waitForAlarmUpdate()
        XCTAssertFalse(session.isPlaying)
        XCTAssertTrue(driver.cancelled.isEmpty, "Finishing must not cancel a ringing alarm")
        session.pause()
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.cancelled, [session.id], "An explicit user cancellation still cancels")
    }

    @MainActor
    func testAVKitSetupAndTeardownPauseDoNotDisarmAnAlarmTimer() async throws {
        let driver = RecordingTimerAlarmDriver()
        let session = FloatingToolSession(configuration: .init(kind: .countdown, alarmWhenFinished: true), alarmScheduler: driver)
        let source = LiveFloatSource(session: session)
        let pip = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: source))
        source.controller = pip
        try source.start()
        source.activate()
        await session.waitForAlarmUpdate()
        source.pictureInPictureController(pip, setPlaying: false)
        await Task.yield()
        XCTAssertTrue(session.isPlaying)
        XCTAssertTrue(driver.cancelled.isEmpty)
        source.stop()
        session.pause()
        await session.waitForAlarmUpdate()
    }

    @MainActor
    func testAlarmScheduleFailureIsVisibleAndPausesTimer() async {
        let driver = RecordingTimerAlarmDriver()
        driver.fails = true
        let session = FloatingToolSession(configuration: .init(kind: .countdown, alarmWhenFinished: true), alarmScheduler: driver)
        session.resume()
        await session.waitForAlarmUpdate()
        XCTAssertNotNil(session.alarmError)
        XCTAssertFalse(session.isPlaying)
        XCTAssertNil(session.alarmDate)
        XCTAssertFalse(session.isUpdatingAlarm)
    }

    @MainActor
    func testVisualOnlyToolsNeverScheduleAnAlarm() async {
        let driver = RecordingTimerAlarmDriver()
        for kind in FloatingToolKind.allCases {
            let session = FloatingToolSession(configuration: .init(kind: kind), alarmScheduler: driver)
            session.resume()
            session.pause()
            session.reset()
            await session.waitForAlarmUpdate()
        }
        XCTAssertTrue(driver.dates.isEmpty)
        XCTAssertTrue(driver.cancelled.isEmpty)
    }

    @MainActor
    func testLateAlarmScheduleCannotUndoANewerPause() async {
        let driver = RecordingTimerAlarmDriver()
        driver.delayFirstSchedule = true
        let session = FloatingToolSession(configuration: .init(kind: .countdown, alarmWhenFinished: true), alarmScheduler: driver)
        session.resume()
        for _ in 0..<100 where driver.pendingSchedule == nil { await Task.yield() }
        XCTAssertNotNil(driver.pendingSchedule)
        session.pause()
        driver.pendingSchedule?.resume()
        driver.pendingSchedule = nil
        await session.waitForAlarmUpdate()
        XCTAssertEqual(driver.operations.last, "cancel")
        XCTAssertFalse(session.isUpdatingAlarm)
        XCTAssertNil(session.alarmDate)
    }

    func testTimerAlarmPermissionPurposeIsDeclared() {
        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String
        XCTAssertTrue(purpose?.contains("timer") == true)
    }

    func testInvalidToolConfigurationsAreRejected() {
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .countdown, duration: 0).validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .countdown, duration: .nan).validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .pomodoro, rounds: 0).validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .clock, timeZoneIdentifier: "Not/AZone").validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .teleprompter, text: " \n").validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .teleprompter, text: String(repeating: "x", count: 20_001)).validate())
        XCTAssertThrowsError(try FloatingToolConfiguration(kind: .teleprompter, text: "Script", scrollSpeed: .infinity).validate())
    }

    func testTextRenderingIsBoundedAndRejectsUnusableInput() throws {
        XCTAssertThrowsError(try FloatingText.render(" \n"))
        XCTAssertThrowsError(try FloatingText.render(String(repeating: "x", count: 2_001)))
        XCTAssertThrowsError(try FloatingText.render(String(repeating: "line\n", count: 200)))
        for palette in FloatingPalette.allCases {
            let image = try FloatingText.render("Reference: flight AB123\nGate 7", palette: palette)
            XCTAssertEqual(image.pixelSize.width, 900)
            XCTAssertLessThanOrEqual(image.pixelSize.height, 1_188)
            XCTAssertNotNil(image.cgImage)
        }
    }

    func testPDFPageSelectionAndRenderingRespectOriginals() throws {
        let reference = try PDFReference(data: Self.pdfData())
        XCTAssertEqual(reference.pageCount, 2)
        let first = try reference.image(pageIndex: 0, maximumEdge: 600)
        let second = try reference.image(pageIndex: 1, maximumEdge: 600)
        XCTAssertEqual(first.pixelSize, CGSize(width: 450, height: 600))
        XCTAssertGreaterThan(try Self.pixel(first).red, 220)
        XCTAssertGreaterThan(try Self.pixel(second).blue, 220)
        // Checking just red/blue allowed a mostly-white page with a tiny
        // colored rectangle to pass. Verify every corner, including channels
        // that must be absent, at both upscaled and downscaled resolutions.
        for edge in [CGFloat(120), 600, 1_600] {
            for (index, expectedRed) in [(0, true), (1, false)] {
                let rendered = try reference.image(pageIndex: index, maximumEdge: edge)
                for point in [CGPoint(x: 1, y: 1), CGPoint(x: rendered.pixelSize.width - 2, y: 1),
                              CGPoint(x: 1, y: rendered.pixelSize.height - 2),
                              CGPoint(x: rendered.pixelSize.width - 2, y: rendered.pixelSize.height - 2)] {
                    let corner = try Self.pixel(XCTUnwrap(rendered.cropped(toPixelRect: CGRect(origin: point, size: CGSize(width: 1, height: 1)))))
                    XCTAssertLessThan(corner.green, 20, "No white padding may be introduced by PDF rendering")
                    XCTAssertLessThan(expectedRed ? corner.blue : corner.red, 20)
                    XCTAssertGreaterThan(expectedRed ? corner.red : corner.blue, 235)
                }
            }
        }
        XCTAssertEqual(reference.document.page(at: 0)?.rotation, 0)
        XCTAssertThrowsError(try reference.image(pageIndex: -1))
        XCTAssertThrowsError(try reference.image(pageIndex: 2))
    }

    func testRotatedPDFProducesLandscapeImage() throws {
        let document = try XCTUnwrap(PDFDocument(data: Self.pdfData()))
        document.page(at: 0)?.rotation = 90
        let reference = try PDFReference(data: XCTUnwrap(document.dataRepresentation()))
        XCTAssertEqual(try reference.image(pageIndex: 0, maximumEdge: 600).pixelSize, CGSize(width: 600, height: 450))
        XCTAssertEqual(reference.document.page(at: 0)?.rotation, 90)
    }

    func testPDFCropBoxAndAllRotationsFillTheRaster() throws {
        for rotation in [0, 90, 180, 270] {
            let document = try XCTUnwrap(PDFDocument(data: Self.pdfData()))
            let page = try XCTUnwrap(document.page(at: 1))
            page.setBounds(CGRect(x: 50, y: 75, width: 200, height: 250), for: .cropBox)
            page.rotation = rotation
            let reference = try PDFReference(data: XCTUnwrap(document.dataRepresentation()))
            let image = try reference.image(pageIndex: 1, maximumEdge: 1_000)
            XCTAssertEqual(image.pixelSize, rotation % 180 == 0 ? CGSize(width: 800, height: 1_000) : CGSize(width: 1_000, height: 800))
            for point in [CGPoint(x: 2, y: 2), CGPoint(x: image.pixelSize.width - 3, y: image.pixelSize.height - 3)] {
                let pixel = try Self.pixel(XCTUnwrap(image.cropped(toPixelRect: CGRect(origin: point, size: CGSize(width: 1, height: 1)))))
                XCTAssertGreaterThan(pixel.blue, 235)
                XCTAssertLessThan(pixel.red, 20, "Rotation \(rotation) must not introduce white borders")
                XCTAssertLessThan(pixel.green, 20)
            }
        }
    }

    func testMalformedAndOversizePDFsAreRejected() {
        XCTAssertThrowsError(try PDFReference(data: Data("not a pdf".utf8)))
        XCTAssertThrowsError(try PDFReference(data: Data(count: PDFReference.maximumBytes + 1)))
    }

    func testScriptStopsAtItsLastLinesInsteadOfScrollingIntoBlank() {
        let short = FloatingToolConfiguration(kind: .teleprompter, text: "Short reference")
        XCTAssertEqual(FloatingToolRenderer.scriptTravel(short), 0)
        let long = FloatingToolConfiguration(kind: .teleprompter, text: (1...40).map { "Line \($0): keep this visible." }.joined(separator: "\n"))
        XCTAssertGreaterThan(FloatingToolRenderer.scriptTravel(long), 540)
        let last = FloatingToolRenderer.render(configuration: long, elapsed: 1_000_000, date: .distantPast)
        XCTAssertEqual(last.pixelSize, CGSize(width: 960, height: 540))
        XCTAssertNotEqual(last.pngData(), FloatingToolRenderer.render(configuration: long, elapsed: 0, date: .distantPast).pngData())
    }

    @MainActor
    func testLiveFramesContainRealPixelsAndPresentationTimes() throws {
        let config = FloatingToolConfiguration(kind: .countdown, palette: .yellow)
        let image = FloatingToolRenderer.render(configuration: config, elapsed: 5, date: .distantPast)
        let sample = try LiveFloatSource.sampleBuffer(image: image, at: CMTime(seconds: 123, preferredTimescale: 600))
        XCTAssertTrue(CMSampleBufferDataIsReady(sample))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, 123, accuracy: 0.001)
        let pixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
        XCTAssertEqual(CVPixelBufferGetWidth(pixels), 960)
        XCTAssertEqual(CVPixelBufferGetHeight(pixels), 540)
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(base[2], 240, "The first real video frame must contain the yellow background, not gray/black")
        XCTAssertGreaterThan(base[1], 220)
        XCTAssertLessThan(base[0], 200, "A blank white frame must not pass as the actual yellow content")
    }

    @MainActor
    func testStoppingLiveSourcePausesAndReleasesItsCallback() throws {
        let session = FloatingToolSession(configuration: .init(kind: .stopwatch))
        let source = LiveFloatSource(session: session)
        try source.start()
        source.activate()
        XCTAssertTrue(session.isPlaying)
        source.stop()
        XCTAssertFalse(session.isPlaying)
        XCTAssertNil(session.onPlaybackChange)
        source.stop()
    }

    @MainActor
    func testTextAndPDFActionsDeliverActualInputWithoutReplacingImageShortcut() async throws {
        let inbox = IntentInbox.shared
        defer { inbox.pendingReference = nil }
        let text = FloatTextWithCodIntent()
        text.text = "The actual shared reference"
        _ = try await text.perform()
        guard case .text(let supplied)? = inbox.pendingReference?.content else { return XCTFail("Missing supplied text") }
        XCTAssertEqual(supplied, text.text)
        let pdf = FloatPDFPageWithCodIntent()
        pdf.document = .init(data: Self.pdfData(), filename: "two-pages.pdf", type: .pdf)
        pdf.page = 2
        _ = try await pdf.perform()
        guard case .pdf(let data, let page)? = inbox.pendingReference?.content else { return XCTFail("Missing supplied PDF") }
        XCTAssertEqual(page, 2)
        XCTAssertGreaterThan(try Self.pixel(PDFReference(data: data).image(pageIndex: page - 1)).blue, 220)
        pdf.page = 3
        do { _ = try await pdf.perform(); XCTFail("Out-of-range pages must fail") } catch {}
    }

    @MainActor
    func testNewestExplicitReferenceDoesNotReplayOlderImageInput() {
        let inbox = IntentInbox()
        inbox.pendingFloatImage = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        inbox.wantsFloatLatest = true
        inbox.pendingQuickFloatRequestID = UUID()
        inbox.deliverReference(.text("Newest reference"))
        XCTAssertNil(inbox.pendingFloatImage)
        XCTAssertFalse(inbox.wantsFloatLatest)
        XCTAssertNil(inbox.pendingQuickFloatRequestID)
        XCTAssertNotNil(inbox.pendingReference)
        inbox.requestFloatLatest()
        XCTAssertNil(inbox.pendingReference)
    }

    @MainActor
    func testLiveDelegateHonorsNativePauseAndAcknowledgesSkip() async throws {
        let session = FloatingToolSession(configuration: .init(kind: .stopwatch))
        let source = LiveFloatSource(session: session)
        let pip = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: source.layer, playbackDelegate: source))
        source.controller = pip
        defer { source.stop() }
        try source.start()
        source.activate()
        XCTAssertFalse(source.pictureInPictureControllerIsPlaybackPaused(pip))
        session.setPlayingFromPiP(false)
        XCTAssertTrue(source.pictureInPictureControllerIsPlaybackPaused(pip))
        XCTAssertFalse(session.isPlaying)
        session.setPlayingFromPiP(true)
        XCTAssertTrue(session.isPlaying)
        var acknowledged = false
        source.pictureInPictureController(pip, skipByInterval: .zero) { acknowledged = true }
        XCTAssertTrue(acknowledged)
        XCTAssertTrue(source.pictureInPictureControllerTimeRangeForPlayback(pip).duration.isPositiveInfinity)
    }

    func testToolTimerRequiredReasonIsDeclaredInAppManifest() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let timer = try XCTUnwrap(entries.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategorySystemBootTime" })
        XCTAssertEqual(timer["NSPrivacyAccessedAPITypeReasons"] as? [String], ["35F9.1"])
    }

    private static func pdfData() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
            for color in [UIColor.red, UIColor.blue] {
                context.beginPage()
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            }
        }
    }

    private static func pixel(_ image: UIImage) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(try XCTUnwrap(image.cgImage), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (bytes[0], bytes[1], bytes[2])
    }
}

@MainActor
private final class RecordingTimerAlarmDriver: FloatingTimerAlarmScheduling {
    var dates: [Date] = []
    var cancelled: [UUID] = []
    var operations: [String] = []
    var fails = false
    var delayFirstSchedule = false
    var pendingSchedule: CheckedContinuation<Void, Never>?

    var now: () -> Date = Date.init

    func schedule(id: UUID, after duration: TimeInterval) async throws -> Date {
        if delayFirstSchedule {
            delayFirstSchedule = false
            await withCheckedContinuation { pendingSchedule = $0 }
        }
        if fails { throw FloatingTimerAlarmError.permissionDenied }
        let date = now().addingTimeInterval(duration)
        dates.append(date)
        operations.append("schedule")
        return date
    }
    func cancel(id: UUID) throws {
        cancelled.append(id)
        operations.append("cancel")
    }
}
