import XCTest
import UIKit
@testable import Cod

final class SharedImageInboxTests: XCTestCase {
    private var container: URL!
    private var inbox: SharedImageInbox!

    override func setUpWithError() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("CodInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let directory = container!
        inbox = SharedImageInbox(container: { directory })
    }

    override func tearDownWithError() throws {
        if let container { try FileManager.default.removeItem(at: container) }
        container = nil
        inbox = nil
    }

    func testImageSurvivesSeparateReadersAndExplicitRemoval() throws {
        let id = try inbox.save(Self.image)
        let directory = container!
        let appReader = SharedImageInbox(container: { directory })
        let entry = try XCTUnwrap(appReader.entries().first)
        XCTAssertEqual(entry.id, id)
        XCTAssertNotNil(entry.thumbnail)
        let image = try appReader.image(for: id)
        XCTAssertEqual(image.pixelSize, CGSize(width: 20, height: 12))
        XCTAssertEqual(image.pngData(), Self.image.pngData())
        XCTAssertEqual(try appReader.entries().count, 1, "Opening must not discard the durable image")
        try appReader.remove(id)
        XCTAssertTrue(try inbox.entries().isEmpty)
        try appReader.remove(id) // Idempotent, including two app windows.
    }

    func testNewestFirstAndDistinctImagesDoNotOverwriteEachOther() throws {
        let oldest = try inbox.save(Self.image, receivedAt: Date(timeIntervalSince1970: 1))
        let newest = try inbox.save(Self.image, receivedAt: Date(timeIntervalSince1970: 3))
        let middle = try inbox.save(Self.image, receivedAt: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try inbox.entries().map(\.id), [newest, middle, oldest])
    }

    func testFullInboxRejectsNewImageWithoutDeletingExistingOnes() throws {
        var originals: [UUID] = []
        for _ in 0..<SharedImageInbox.capacity { originals.append(try inbox.save(Self.image)) }
        XCTAssertThrowsError(try inbox.save(Self.image)) { error in
            guard case SharedImageInbox.InboxError.full = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertEqual(Set(try inbox.entries().map(\.id)), Set(originals))
        try inbox.remove(originals[0])
        XCTAssertNoThrow(try inbox.save(Self.image))
    }

    func testConcurrentSavesRespectCapacityWithoutOverwriting() throws {
        let png = try XCTUnwrap(Self.image.pngData())
        let directory = container!
        let lock = NSLock()
        var saved: [UUID] = []
        var rejected = 0
        var unexpected: [Error] = []
        DispatchQueue.concurrentPerform(iterations: SharedImageInbox.capacity + 4) { _ in
            let writer = SharedImageInbox(container: { directory })
            do {
                let id = try writer.savePNG(png)
                lock.lock(); saved.append(id); lock.unlock()
            } catch SharedImageInbox.InboxError.full {
                lock.lock(); rejected += 1; lock.unlock()
            } catch {
                lock.lock(); unexpected.append(error); lock.unlock()
            }
        }
        XCTAssertTrue(unexpected.isEmpty, "\(unexpected)")
        XCTAssertEqual(saved.count, SharedImageInbox.capacity)
        XCTAssertEqual(rejected, 4)
        XCTAssertEqual(Set(try inbox.entries().map(\.id)), Set(saved))
    }

    func testMalformedImageIsRejectedWithoutCreatingARecord() throws {
        XCTAssertThrowsError(try inbox.savePNG(Data([0, 1, 2])))
        XCTAssertTrue(try inbox.entries().isEmpty)
    }

    func testOversizedImageIsRejectedBeforeDecoding() throws {
        XCTAssertThrowsError(try inbox.savePNG(Data(count: SharedImageInbox.maximumImageBytes + 1))) { error in
            guard case SharedImageInbox.InboxError.tooLarge = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertTrue(try inbox.entries().isEmpty)
    }

    func testMissingAppGroupFailsClearlyWithoutClipboardFallback() {
        let unavailable = SharedImageInbox(container: { nil })
        XCTAssertThrowsError(try unavailable.save(Self.image)) { error in
            guard case SharedImageInbox.InboxError.unavailable = error else { return XCTFail("Wrong error: \(error)") }
        }
        XCTAssertThrowsError(try unavailable.entries())
    }

    func testCorruptRecordRemainsVisibleAndCanBeRemoved() throws {
        let id = try inbox.save(Self.image)
        let url = container.appendingPathComponent("Shared Images").appendingPathComponent(id.uuidString).appendingPathExtension("codimage")
        try Data([1, 2, 3]).write(to: url, options: .atomic)
        let entry = try XCTUnwrap(inbox.entries().first)
        XCTAssertEqual(entry.id, id)
        XCTAssertNil(entry.thumbnail)
        XCTAssertThrowsError(try inbox.image(for: id))
        try inbox.remove(id)
        XCTAssertTrue(try inbox.entries().isEmpty)
    }

    func testInboxIsExcludedFromBackupAndUnrelatedFilesSurvive() throws {
        let id = try inbox.save(Self.image)
        let directory = container.appendingPathComponent("Shared Images")
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        try inbox.remove(id)
        XCTAssertTrue(try inbox.entries().isEmpty)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
    }

    @MainActor
    func testCropFromInboxIgnoresInstantArrivalAndKeepsImageAfterCancel() throws {
        let defaults = UserDefaults(suiteName: "CodInboxCoordinatorTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.arrivalMode = .instant
        settings.instantAction = .copyImage
        settings.historyLimit = .off
        let coordinator = CaptureCoordinator(store: .shared, settings: settings, pins: .shared, pip: PiPPinController(), sharedInbox: inbox)
        try inbox.save(Self.image)
        coordinator.refreshSharedImages()
        let entry = try XCTUnwrap(coordinator.sharedImages.first)
        coordinator.openSharedImage(entry, float: false)
        XCTAssertNotNil(coordinator.pending)
        XCTAssertFalse(coordinator.floatOnlyLaunch)
        coordinator.dismissSelection()
        XCTAssertNil(coordinator.pending)
        XCTAssertEqual(try inbox.entries().count, 1)
        coordinator.removeSharedImage(entry)
        XCTAssertTrue(coordinator.sharedImages.isEmpty)
    }

    func testStoreAppAndExtensionHaveMatchingSharedContainerMetadataAndPrivacyResources() throws {
        let app = Bundle.main
        let plugins = try XCTUnwrap(app.builtInPlugInsURL)
        let share = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("CodShare.appex")))
        XCTAssertEqual(app.bundleIdentifier, "com.josh.cod.store")
        XCTAssertEqual(share.bundleIdentifier, "com.josh.cod.store.share")
        let group = try XCTUnwrap(app.object(forInfoDictionaryKey: "CodAppGroup") as? String)
        XCTAssertEqual(group, "group.com.josh.cod.store")
        XCTAssertEqual(share.object(forInfoDictionaryKey: "CodAppGroup") as? String, group)
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CodFloatURLScheme") as? String, "cod-store")
        XCTAssertEqual(share.object(forInfoDictionaryKey: "CodFloatURLScheme") as? String, "cod-store")
        let expectedPolicy = "manual-open"
        XCTAssertEqual(app.object(forInfoDictionaryKey: "CodShareLaunchPolicy") as? String, expectedPolicy)
        XCTAssertEqual(share.object(forInfoDictionaryKey: "CodShareLaunchPolicy") as? String, expectedPolicy)
        XCTAssertNotNil(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group))
        for bundle in [app, share] {
            let manifest = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
            let dictionary = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: manifest), format: nil) as? [String: Any])
            let categories = try XCTUnwrap(dictionary["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
            XCTAssertEqual(categories.first?["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryUserDefaults")
            XCTAssertEqual(categories.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        }
    }

    func testSettingsCannotRestoreRemovedUploadAction() {
        let suite = "CodStoreSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try! JSONEncoder().encode(SnapAction.upload), forKey: "instantAction")
        defaults.set(try! JSONEncoder().encode([SnapAction.upload, .float]), forKey: "actionOrder")
        defaults.set(try! JSONEncoder().encode(Set([SnapAction.upload, .float])), forKey: "enabledActions")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.instantAction, .float)
        XCTAssertFalse(settings.visibleActions.contains(.upload))
        XCTAssertFalse(settings.actionOrder.contains(.upload))
        XCTAssertFalse(SnapAction.availableCases.contains(.upload))
    }

    private static var image: UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 20, height: 12), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        }
    }
}
