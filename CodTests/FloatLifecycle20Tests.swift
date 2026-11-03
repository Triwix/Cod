import Combine
import UIKit
import XCTest
@testable import Cod

final class FloatLifecycle20Tests: XCTestCase {
    @MainActor
    func testFreshImagePlaybackDoesNotPublishAnIntermediateIdle() throws {
        try withRig { pip, _, _ in
            var statuses: [PiPPinController.Status] = []
            let observation = pip.$status.dropFirst().sink { statuses.append($0) }
            defer { observation.cancel() }

            pip.float(Self.image, reusePreparedPlayback: false)

            XCTAssertEqual(statuses, [.preparing], "Rebuilding playback must not end the new float request")
        }
    }

    @MainActor
    func testDirectImageAndShortcutRemainTrackedUntilStopped() throws {
        try withRig { pip, coordinator, _ in
            for useShortcut in [false, true] {
                if useShortcut { coordinator.receiveFloatIntentImage(Self.image) }
                else { coordinator.receiveExternalImage(Self.image) }

                XCTAssertEqual(pip.status, .preparing)
                XCTAssertTrue(coordinator.isWorking, "The coordinator must still observe the eventual result")
                XCTAssertTrue(coordinator.floatOnlyLaunch)

                pip.stop()
                XCTAssertEqual(pip.status, .idle)
                XCTAssertFalse(coordinator.isWorking, "An actual stop must still finish the request")
            }
        }
    }

    @MainActor
    func testPreparingShareStaysClaimedAndActualStopAllowsRetry() throws {
        try withRig { pip, coordinator, handoff in
            let id = try handoff.store(Self.image)
            XCTAssertTrue(coordinator.receiveQuickShare(expectedID: id))

            XCTAssertEqual(pip.status, .preparing)
            XCTAssertTrue(coordinator.isWorking)
            XCTAssertEqual(try handoff.preview()?.id, id)
            XCTAssertNil(try handoff.claimNotification(id), "An in-flight share must not be released for a second claim")

            pip.stop()
            XCTAssertFalse(coordinator.isWorking)
            XCTAssertEqual(try handoff.claimNotification(id)?.id, id, "A cancelled share must remain explicitly retryable")
        }
    }

    @MainActor
    func testNewExternalImageDoesNotFinishItsOwnRequestWhileReplacingPreparation() throws {
        try withRig { pip, coordinator, _ in
            var statuses: [PiPPinController.Status] = []
            let observation = pip.$status.dropFirst().sink { statuses.append($0) }
            defer { observation.cancel() }

            coordinator.receiveFloatIntentImage(Self.image)
            coordinator.receiveFloatIntentImage(Self.image)

            XCTAssertEqual(statuses, [.preparing, .preparing])
            XCTAssertTrue(coordinator.isWorking)
            XCTAssertTrue(pip.currentImage === Self.image)
        }
    }

    @MainActor
    func testUnsupportedPlaybackFinishesTheRequestAndKeepsTheShareRetryable() throws {
        try withRig(isSupported: false) { pip, coordinator, handoff in
            let id = try handoff.store(Self.image)
            XCTAssertTrue(coordinator.receiveQuickShare(expectedID: id))

            XCTAssertEqual(pip.status, .unsupported)
            XCTAssertFalse(coordinator.isWorking)
            XCTAssertFalse(coordinator.floatOnlyLaunch)
            XCTAssertEqual(try handoff.claimNotification(id)?.id, id)
        }
    }

    @MainActor
    private func withRig(
        isSupported: Bool = true,
        _ body: (PiPPinController, CaptureCoordinator, QuickFloatHandoff) throws -> Void
    ) throws {
        // Assert synchronous request state, then stop before the preparation
        // task runs. No native PiP success or playback is simulated here.
        let pip = PiPPinController(isSupported: isSupported)
        let suite = "Cod.FloatLifecycle20.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            pip.stop()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = AppSettings(defaults: defaults, sharePreferences: FloatLifecyclePreferences())
        settings.historyLimit = .off
        let handoff = QuickFloatHandoff(container: { directory })
        let coordinator = CaptureCoordinator(
            store: SnapStore(baseDirectory: directory.appendingPathComponent("Library")),
            settings: settings, pip: pip, quickHandoff: handoff
        )
        try body(pip, coordinator, handoff)
    }

    @MainActor
    private static let image: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 24), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 24))
        }
    }()
}

private final class FloatLifecyclePreferences: ShareFloatPreferenceStore {
    var oneTapFloat = true
    var useFloatNotification = false
    func setOneTapFloat(_ enabled: Bool) -> Bool { oneTapFloat = enabled; return true }
    func setUseFloatNotification(_ enabled: Bool) -> Bool { useFloatNotification = enabled; return true }
}
