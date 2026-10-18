import XCTest
import AVFoundation
import AVKit
import UIKit
@testable import Cod

final class PiPStateTests: XCTestCase {
    func testEarlyRestorationIgnoresLateStartEvents() {
        var policy = PiPRestorationState()
        policy.beginFloat()
        XCTAssertFalse(policy.isRestoring)
        policy.beginRestoration()
        XCTAssertTrue(policy.isRestoring)
    }

    func testNextFloatDoesNotInheritAnEarlierRestoration() {
        var policy = PiPRestorationState()
        policy.beginRestoration()
        policy.beginFloat()
        XCTAssertFalse(policy.isRestoring)
    }

    @MainActor
    func testRestoreImageAlwaysOpensSelectionWithoutRunningInstantFloat() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cod-restore-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapStore(baseDirectory: directory)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "Cod.RestoreTests.\(UUID().uuidString)")!)
        settings.arrivalMode = .instant
        settings.instantAction = .float
        let pip = PiPPinController()
        let coordinator = CaptureCoordinator(store: store, settings: settings, pins: PinManager(), pip: pip)
        coordinator.floatOnlyLaunch = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12)).image { _ in UIColor.red.setFill() }
        coordinator.restoreFloatingSelection(image)
        XCTAssertFalse(coordinator.floatOnlyLaunch)
        XCTAssertTrue(coordinator.pending?.image === image)
        XCTAssertEqual(pip.status, .idle)
        XCTAssertTrue(store.snaps.isEmpty)
    }

    @MainActor
    func testEncodedFloatingClipContainsTheImageInsteadOfBlankFrames() async throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        let url = try await FloatingClip.make(from: image)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        let frame = try await generator.image(at: .zero).image
        XCTAssertEqual(frame.width, 64)
        XCTAssertEqual(frame.height, 48)
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(frame, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(rgba[0], 220)
        XCTAssertLessThan(rgba[1], 40)
        XCTAssertLessThan(rgba[2], 40)
        XCTAssertGreaterThan(rgba[3], 240)
    }

    @MainActor
    func testOddSizedImageEncodesToEvenVideoDimensions() async throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 65, height: 49), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 65, height: 49))
        }
        let url = try await FloatingClip.make(from: image)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 64, height: 48))
    }

    @MainActor
    func testUnownedDelegateCallbacksCannotStartOrDestroySession() async {
        let sut = PiPPinController()
        let stale = AVPictureInPictureController(contentSource: .init(
            activeVideoCallSourceView: UIView(),
            contentViewController: AVPictureInPictureVideoCallViewController()
        ))
        sut.pictureInPictureControllerDidStartPictureInPicture(stale)
        sut.pictureInPictureController(stale, failedToStartPictureInPictureWithError: NSError(domain: "stale-test", code: 1))
        sut.pictureInPictureControllerDidStopPictureInPicture(stale)
        let restored = await withCheckedContinuation { continuation in
            sut.pictureInPictureController(stale, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler: {
                continuation.resume(returning: $0)
            })
        }
        XCTAssertFalse(restored)
        XCTAssertEqual(sut.status, .idle)
        XCTAssertNil(sut.currentImage)
    }

    @MainActor
    func testReadinessCompletionBeforeWaitIsNotLost() async {
        let wait = PiPReadinessWait()
        wait.finish(.ready)
        let result = await wait.wait()
        XCTAssertEqual(result, .ready)
    }

    @MainActor
    func testReadinessCompletionIsOneShot() async {
        let wait = PiPReadinessWait()
        wait.finish(.cancelled)
        wait.finish(.ready)
        wait.finish(.timedOut)
        let result = await wait.wait()
        XCTAssertEqual(result, .cancelled)
    }

    @MainActor
    func testReadinessTimeoutIsBounded() async {
        let wait = PiPReadinessWait()
        let result = await wait.wait(timeoutNanoseconds: 1_000_000)
        XCTAssertEqual(result, .timedOut)
    }

    @MainActor
    func testCancellingPreparationReleasesReadinessWait() async {
        let wait = PiPReadinessWait()
        let task = Task { await wait.wait(timeoutNanoseconds: 30_000_000_000) }
        await Task.yield()
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    @MainActor
    func testCancelledOldReadinessCannotCompleteNewWait() async {
        let old = PiPReadinessWait()
        let new = PiPReadinessWait()
        old.finish(.cancelled)
        old.finish(.ready)
        new.finish(.ready)
        let oldResult = await old.wait()
        let newResult = await new.wait()
        XCTAssertEqual(oldResult, .cancelled)
        XCTAssertEqual(newResult, .ready)
    }

    @MainActor
    func testVeryThinImagesNeverResizeToZeroPixels() {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        for size in [CGSize(width: 1, height: 4_000), CGSize(width: 4_000, height: 1)] {
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let fitted = image.fitted(within: CGSize(width: 1_200, height: 1_200))
            XCTAssertGreaterThanOrEqual(fitted.pixelSize.width, 1)
            XCTAssertGreaterThanOrEqual(fitted.pixelSize.height, 1)
            XCTAssertLessThanOrEqual(max(fitted.pixelSize.width, fitted.pixelSize.height), 1_200)
        }
    }

    func testActiveWindowTakesReplacementPathEvenAfterStatusMovesToPreparing() {
        let path = PiPPinController.preparationPath(
            wasActive: true,
            hasPlayer: true,
            hasController: true
        )

        XCTAssertEqual(path, .replaceActive)
    }

    func testPrewarmedControllerReusesPreparedPlayback() {
        let path = PiPPinController.preparationPath(
            wasActive: false,
            hasPlayer: true,
            hasController: true
        )

        XCTAssertEqual(path, .reusePrepared)
    }

    func testMissingPreparedComponentsUsesColdPath() {
        XCTAssertEqual(
            PiPPinController.preparationPath(
                wasActive: false,
                hasPlayer: true,
                hasController: false
            ),
            .cold
        )
    }

    func testExternalLaunchBuildsFreshPlaybackDespiteDormantPrewarm() {
        XCTAssertEqual(
            PiPPinController.preparationPath(
                wasActive: false,
                hasPlayer: true,
                hasController: true,
                reusePreparedPlayback: false
            ),
            .cold
        )
    }

    func testExternalLaunchKeepsAnAlreadyActiveWindowForReplacement() {
        XCTAssertEqual(
            PiPPinController.preparationPath(
                wasActive: true,
                hasPlayer: true,
                hasController: true,
                reusePreparedPlayback: false
            ),
            .replaceActive
        )
    }
}
