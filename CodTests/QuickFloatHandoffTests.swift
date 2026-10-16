import XCTest
import UIKit
@testable import Cod

final class QuickFloatHandoffTests: XCTestCase {
    private var container: URL!
    private var handoff: QuickFloatHandoff!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("CodQuickTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let directory = container!
        handoff = QuickFloatHandoff(container: { directory })
    }

    override func tearDownWithError() throws {
        if let container { try FileManager.default.removeItem(at: container) }
        container = nil
        handoff = nil
    }

    func testSeparateAppReaderClaimsCorrectImageExactlyOnce() throws {
        let id = try handoff.store(Self.image, now: now)
        let directory = container!
        let reader = QuickFloatHandoff(container: { directory })
        let received = try XCTUnwrap(reader.claim(now: now))
        XCTAssertEqual(received.id, id)
        XCTAssertEqual(received.mode, .float)
        XCTAssertEqual(received.image.pixelSize, CGSize(width: 40, height: 24))
        XCTAssertEqual(received.image.pngData(), Self.image.pngData())
        XCTAssertNil(try reader.claim(now: now))
        XCTAssertNil(try handoff.claim(now: now))
        try reader.finish(id, success: true)
        XCTAssertNil(try handoff.preview())
    }

    func testLaunchRequestCannotConsumeANewerSharedImage() throws {
        let old = try handoff.store(Self.image, now: now)
        let current = try handoff.store(Self.image, now: now)
        XCTAssertNil(try handoff.claim(now: now, expectedID: old))
        XCTAssertEqual(try handoff.claim(now: now, expectedID: current)?.id, current)
        XCTAssertNil(try handoff.claim(now: now, expectedID: current))
    }

    func testLaunchURLContainsOnlyItsRequestAndRejectsMalformedInput() throws {
        let route = QuickFloatLaunchRoute(scheme: "cod-test")
        let id = UUID()
        let url = try XCTUnwrap(route.url(for: id))
        XCTAssertEqual(route.requestID(in: url), id)
        let value = id.uuidString
        for raw in [
            "wrong://float-shared-image?request=\(value)",
            "cod-test://wrong?request=\(value)",
            "cod-test://user@float-shared-image?request=\(value)",
            "cod-test://float-shared-image:123?request=\(value)",
            "cod-test://float-shared-image/path?request=\(value)",
            "cod-test://float-shared-image?request=bad",
            "cod-test://float-shared-image?request=\(value)&request=\(value)",
            "cod-test://float-shared-image?request=\(value)&source=another-app",
            "cod-test://float-shared-image?request=\(value)#fragment",
            "cod-test://float-shared-image",
        ] {
            XCTAssertNil(route.requestID(in: try XCTUnwrap(URL(string: raw))), raw)
        }
    }

    @MainActor
    func testExplicitShareReplacesOldCropButWrongRequestDoesNot() throws {
        let suite = "CodQuickExplicitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.historyLimit = .off
        let coordinator = CaptureCoordinator(store: .shared, settings: settings, pins: .shared, pip: PiPPinController(), quickHandoff: handoff)
        coordinator.restoreFloatingSelection(Self.image)
        let old = try XCTUnwrap(coordinator.pending?.id)
        let id = try handoff.store(Self.image, mode: .crop)
        XCTAssertTrue(coordinator.receiveQuickShare(expectedID: UUID()))
        XCTAssertEqual(coordinator.pending?.id, old)
        XCTAssertTrue(coordinator.receiveQuickShare(expectedID: id))
        XCTAssertNotEqual(coordinator.pending?.id, old)
        XCTAssertEqual(coordinator.pending?.image.pngData(), Self.image.pngData())
    }

    @MainActor
    func testBusyFloatDefersAnExplicitShareWithoutConsumingIt() throws {
        let suite = "CodQuickBusyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = CaptureCoordinator(store: .shared, settings: AppSettings(defaults: defaults), pins: .shared, pip: PiPPinController(), quickHandoff: handoff)
        let id = try handoff.store(Self.image, mode: .crop)
        coordinator.isWorking = true
        XCTAssertFalse(coordinator.receiveQuickShare(expectedID: id))
        XCTAssertNil(coordinator.pending)
        coordinator.isWorking = false
        XCTAssertTrue(coordinator.receiveQuickShare(expectedID: id))
        XCTAssertNotNil(coordinator.pending)
        XCTAssertNil(try handoff.claim())
    }

    func testConcurrentClaimsHaveOneWinner() throws {
        try handoff.store(Self.image, now: now)
        let directory = container!
        let lock = NSLock()
        var claimed = 0
        var errors: [Error] = []
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            do {
                if try QuickFloatHandoff(container: { directory }).claim(now: self.now) != nil {
                    lock.lock(); claimed += 1; lock.unlock()
                }
            } catch { lock.lock(); errors.append(error); lock.unlock() }
        }
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(claimed, 1)
    }

    func testNewShareSupersedesOldAndStaleAcknowledgementCannotRemoveIt() throws {
        let old = try handoff.store(Self.image, now: now)
        _ = try handoff.claim(now: now)
        let new = try handoff.store(Self.image, mode: .crop, now: now)
        try handoff.finish(old, success: true)
        try handoff.finish(old, success: false)
        let current = try XCTUnwrap(handoff.claim(now: now))
        XCTAssertEqual(current.id, new)
        XCTAssertEqual(current.mode, .crop)
    }

    func testFailedOrInterruptedLaunchRequiresExplicitRetry() throws {
        let id = try handoff.store(Self.image, now: now)
        _ = try handoff.claim(now: now)
        XCTAssertNil(try handoff.claim(now: now))
        try handoff.finish(id, success: false)
        XCTAssertNil(try handoff.claim(now: now))
        XCTAssertEqual(try handoff.retry()?.id, id)
        XCTAssertNil(try handoff.claim(now: now))
        try handoff.finish(id, success: true)
        XCTAssertNil(try handoff.retry())
    }

    func testExpiredOrFutureRequestsNeverAutoplayButRemainRetryable() throws {
        for timestamp in [now.addingTimeInterval(-301), now.addingTimeInterval(6)] {
            let id = try handoff.store(Self.image, now: timestamp)
            XCTAssertNil(try handoff.claim(now: now))
            XCTAssertNil(try handoff.claim(now: now))
            XCTAssertEqual(try handoff.retry()?.id, id)
            try handoff.discard()
        }
    }

    func testExplicitInputDefersAutomaticShareAndKeepsItForRetry() throws {
        let id = try handoff.store(Self.image, now: now)
        try handoff.deferAutomaticStart()
        XCTAssertNil(try handoff.claim(now: now))
        XCTAssertEqual(try handoff.preview()?.id, id)
        XCTAssertEqual(try handoff.retry()?.id, id)
    }

    func testUnreadableImageIsClaimedBeforeDecodeSoItCannotLoop() throws {
        try handoff.store(Self.image, now: now)
        let url = container.appendingPathComponent("Quick Float/request.plist")
        var dictionary = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        dictionary["png"] = Data([1, 2, 3])
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0).write(to: url)
        XCTAssertThrowsError(try handoff.claim(now: now))
        XCTAssertNil(try handoff.claim(now: now))
        try handoff.discard()
        XCTAssertNil(try handoff.preview())
    }

    func testMissingContainerFailsWithoutAnyClipboardFallback() {
        let unavailable = QuickFloatHandoff(container: { nil })
        XCTAssertThrowsError(try unavailable.store(Self.image))
        XCTAssertThrowsError(try unavailable.claim())
    }

    func testQuickDataIsExcludedFromBackupAndDiscardKeepsUnrelatedFiles() throws {
        try handoff.store(Self.image, now: now)
        let directory = container.appendingPathComponent("Quick Float", isDirectory: true)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        try handoff.discard()
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertNil(try handoff.preview())
    }

    @MainActor
    func testCropSettingIgnoresInstantArrivalAndCancelKeepsExplicitRetry() throws {
        let suite = "CodQuickCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.arrivalMode = .instant
        settings.instantAction = .copyImage
        settings.historyLimit = .off
        let coordinator = CaptureCoordinator(store: .shared, settings: settings, pins: .shared, pip: PiPPinController(), quickHandoff: handoff)
        let id = try handoff.store(Self.image, mode: .crop)
        coordinator.receiveQuickShare()
        XCTAssertEqual(coordinator.pending?.image.pixelSize, Self.image.pixelSize)
        XCTAssertFalse(coordinator.floatOnlyLaunch)
        coordinator.dismissSelection()
        XCTAssertNil(coordinator.pending)
        XCTAssertNil(try handoff.claim())
        XCTAssertEqual(try handoff.retry()?.id, id)
    }

    func testFileImageDecoderBoundsLargeImagesAndRejectsInvalidFiles() throws {
        let url = container.appendingPathComponent("large.png")
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let large = UIGraphicsImageRenderer(size: CGSize(width: 3_000, height: 1_000), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 1_000))
        }
        try XCTUnwrap(large.pngData()).write(to: url)
        let decoded = try XCTUnwrap(UIImage.decodedImage(at: url, maximumEdge: 600))
        XCTAssertEqual(decoded.pixelSize, CGSize(width: 600, height: 200))
        try Data([1, 2, 3]).write(to: url)
        XCTAssertNil(UIImage.decodedImage(at: url))
        XCTAssertNil(UIImage.decodedImage(at: url, maximumEdge: 0))
    }

    func testTypedImageFallbackBoundsPixelsNotPoints() throws {
        let cg = try XCTUnwrap(Self.image.cgImage)
        let scaled = UIImage(cgImage: cg, scale: 3, orientation: .up)
        let bounded = try XCTUnwrap(scaled.boundedShareImage(maximumEdge: 20))
        XCTAssertEqual(bounded.scale, 1)
        XCTAssertEqual(bounded.imageOrientation, .up)
        XCTAssertEqual(bounded.pixelSize, CGSize(width: 20, height: 12))
        XCTAssertNil(scaled.boundedShareImage(maximumEdge: 0))
    }

    func testTypedImageFallbackRefusesHugeSourceBitmap() {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let huge = UIGraphicsImageRenderer(size: CGSize(width: 5_000, height: 3_201), format: format).image { _ in }
        XCTAssertNil(huge.boundedShareImage())
    }

    private static var image: UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
        }
    }
}
