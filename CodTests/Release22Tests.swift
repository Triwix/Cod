import AVFoundation
import Combine
import UIKit
import XCTest
@testable import Cod

final class Release22Tests: XCTestCase {
    func testWriterFailureWithoutReadinessReturnsInsteadOfWaitingForAnotherCallback() async {
        let writer = TestClipWriter(.failBeforeReady)
        do { try await FloatingClipEncoder.encode(writer, frames: 12); XCTFail("Expected writer failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("encoding")) }
        XCTAssertEqual(writer.cancellations, 1)
    }

    func testRejectedFrameCancelsEncoding() async {
        let writer = TestClipWriter(.rejectFrame)
        do { try await FloatingClipEncoder.encode(writer, frames: 12); XCTFail("Expected append failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("rejected")) }
        XCTAssertEqual(writer.cancellations, 1)
    }

    func testBackpressureHasABoundedDeadline() async {
        await assertTimeout(.neverReady)
    }

    func testFinalizationHasTheSameBoundedDeadline() async {
        await assertTimeout(.neverFinishes)
    }

    private func assertTimeout(_ scenario: TestClipWriter.Scenario) async {
        let writer = TestClipWriter(scenario)
        do {
            try await FloatingClipEncoder.encode(writer, frames: 12, timeout: .milliseconds(40))
            XCTFail("Expected bounded failure")
        } catch {
            guard case FloatingClip.ClipError.timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(writer.cancellations, 1)
    }

    func testCancellationWhileWaitingForReadiness() async {
        await assertCancellation(.neverReady)
    }

    func testCancellationWhileFinalizing() async {
        await assertCancellation(.neverFinishes)
    }

    private func assertCancellation(_ scenario: TestClipWriter.Scenario) async {
        let writer = TestClipWriter(scenario)
        let task = Task { try await FloatingClipEncoder.encode(writer, frames: 12) }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writer.cancellations, 1)
    }

    func testAlreadyCancelledEncodingDoesNotAppendAFrame() async {
        let writer = TestClipWriter(.succeeds)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await FloatingClipEncoder.encode(writer, frames: 12)
        }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(writer.appended, 0)
    }

    func testSuccessfulEncodingFinishesEveryFrameAndDoesNotCancel() async throws {
        let writer = TestClipWriter(.succeeds)
        try await FloatingClipEncoder.encode(writer, frames: 12)
        XCTAssertEqual(writer.appended, 12)
        XCTAssertEqual(writer.cancellations, 0)
    }

    func testCompletionBetweenPollsIsAccepted() async throws {
        let writer = TestClipWriter(.completesAfterOnePoll)
        try await FloatingClipEncoder.encode(writer, frames: 12)
        XCTAssertEqual(writer.appended, 12)
        XCTAssertEqual(writer.cancellations, 0)
    }

    func testFinalizationFailureIsReported() async {
        let writer = TestClipWriter(.finalizationFails)
        do { try await FloatingClipEncoder.encode(writer, frames: 12); XCTFail("Expected finalization failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("finalization")) }
        XCTAssertEqual(writer.cancellations, 1)
    }

    func testGeneratedClipCanActuallyBeDecoded() async throws {
        let url = try await FloatingClip.make(from: Self.image())
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 1.5)
        XCTAssertLessThanOrEqual(duration, 2.1)
        let frame = try await AVAssetImageGenerator(asset: asset).image(at: .zero).image
        XCTAssertEqual(frame.width, 80)
        XCTAssertEqual(frame.height, 60)
        var pixels = [UInt8](repeating: 0, count: 8)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 1,
                bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        }
        // Decode the actual yellow/blue content, not merely a playable black file.
        XCTAssertGreaterThan(pixels[0], 150)
        XCTAssertGreaterThan(pixels[1], 150)
        XCTAssertLessThan(pixels[2], 100)
        XCTAssertLessThan(pixels[4], 100)
        XCTAssertGreaterThan(pixels[6], 150)
    }

    @MainActor func testStorageSizeAwaitsQueuedWritesAndRemovals() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapStore(baseDirectory: directory)
        store.add(image: Self.image(), origin: .imported, limit: .unlimited)
        let bytes = await store.diskUsage()
        XCTAssertGreaterThan(bytes, 100)
        store.clear()
        let cleared = await store.diskUsage()
        XCTAssertLessThan(cleared, bytes)
    }

    @MainActor func testRotatedImagePreparationCannotReplaceANewerSelection() async throws {
        let directory = folder()
        let suite = "Cod.Release22.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let pip = PiPPinController(isSupported: false)
        let coordinator = CaptureCoordinator(store: SnapStore(baseDirectory: directory),
            settings: AppSettings(defaults: defaults, sharePreferences: Release22Preferences()), pip: pip)
        defer {
            pip.stop(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let rotated = UIImage(cgImage: try XCTUnwrap(Self.image().cgImage), scale: 2, orientation: .right)
        coordinator.present(image: rotated, origin: .imported)
        XCTAssertTrue(coordinator.isWorking)
        let newest = Self.image()
        coordinator.restoreFloatingSelection(newest)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(coordinator.pending?.image === newest)
        XCTAssertFalse(coordinator.isWorking)
    }

    @MainActor func testRotatedImageIsPreparedBeforePresentation() async throws {
        let directory = folder()
        let suite = "Cod.Release22.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults, sharePreferences: Release22Preferences())
        settings.arrivalMode = .selection
        settings.enabledActions = []
        let coordinator = CaptureCoordinator(store: SnapStore(baseDirectory: directory), settings: settings,
            pip: PiPPinController(isSupported: false))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let ready = expectation(description: "Normalized selection")
        let observation = coordinator.$pending.compactMap { $0 }.sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        let rotated = UIImage(cgImage: try XCTUnwrap(Self.image().cgImage), scale: 2, orientation: .right)
        coordinator.present(image: rotated, origin: .imported)
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(coordinator.pending?.image.imageOrientation, .up)
        XCTAssertEqual(coordinator.pending?.image.scale, 1)
        XCTAssertFalse(coordinator.isWorking)
    }

    func testReleaseLoggingDoesNotEvaluateItsMessage() {
        var evaluations = 0
        CodDiagnosticLog.record({ evaluations += 1; return "Release22 logging check" }())
        #if DEBUG
        XCTAssertEqual(evaluations, 1)
        #else
        XCTAssertEqual(evaluations, 0)
        #endif
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CodRelease22-\(UUID())")
    }
    private static func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
            UIColor.yellow.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
    }
}

private final class Release22Preferences: ShareFloatPreferenceStore {
    var oneTapFloat = true
    var useFloatNotification = false
    func setOneTapFloat(_ enabled: Bool) -> Bool { oneTapFloat = enabled; return true }
    func setUseFloatNotification(_ enabled: Bool) -> Bool { useFloatNotification = enabled; return true }
}

private final class TestClipWriter: FloatingClipWriting, @unchecked Sendable {
    enum Scenario { case succeeds, failBeforeReady, rejectFrame, neverReady, neverFinishes, completesAfterOnePoll, finalizationFails }
    let scenario: Scenario
    private let lock = NSLock()
    private var currentStatus: AVAssetWriter.Status = .writing
    private var frames = 0
    private var cancelled = 0
    private var finishRequested = false
    private var readsAfterFinish = 0
    init(_ scenario: Scenario) { self.scenario = scenario }
    var status: AVAssetWriter.Status {
        lock.withLock {
            if scenario == .completesAfterOnePoll, finishRequested {
                readsAfterFinish += 1
                if readsAfterFinish > 1 { currentStatus = .completed }
            }
            return currentStatus
        }
    }
    var error: Error? { nil }
    var cancellations: Int { lock.withLock { cancelled } }
    var appended: Int { lock.withLock { frames } }
    var isReady: Bool {
        lock.withLock {
            if scenario == .failBeforeReady { currentStatus = .failed; return false }
            return scenario != .neverReady
        }
    }
    func append(frame: Int) -> Bool {
        lock.withLock { frames += 1; return scenario != .rejectFrame }
    }
    func finish() {
        lock.withLock {
            finishRequested = true
            if scenario == .finalizationFails { currentStatus = .failed }
            else if scenario != .neverFinishes && scenario != .completesAfterOnePoll { currentStatus = .completed }
        }
    }
    func cancel() { lock.withLock { cancelled += 1; currentStatus = .cancelled } }
}
