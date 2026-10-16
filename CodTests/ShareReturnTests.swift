#if COD_PERSONAL
import XCTest
import UIKit
@testable import Cod

final class ShareReturnTests: XCTestCase {
    #if DEBUG
    func testImageMetadataDiagnosticReportsKeysNotValuesAndIsBounded() {
        let properties: NSDictionary = [
            "{Exif}": ["UserComment": "private caption", "DateTimeOriginal": "private date"],
            "{GPS}": ["Latitude": 42.0],
            "Caption\nprivate text": "must not become a log line",
            "LineBreak\n": "must not become a log line either",
        ]
        let paths = ShareSourceContext.imagePropertyKeyPaths(properties)
        XCTAssertTrue(paths.contains("{Exif}.UserComment"))
        XCTAssertTrue(paths.contains("{GPS}.Latitude"))
        XCTAssertFalse(paths.joined().contains("private"))
        XCTAssertFalse(paths.joined().contains("42.0"))
        XCTAssertTrue(paths.allSatisfy { !$0.contains("\n") })
        let many = Dictionary(uniqueKeysWithValues: (0..<100).map { ("Key\($0)", "secret") }) as NSDictionary
        XCTAssertLessThanOrEqual(ShareSourceContext.imagePropertyKeyPaths(many).count, 32)
    }
    #endif

    func testScreenshotEnvironmentIdentifiesTheCapturedAppNotThePreview() {
        let environment = ScreenshotEnvironmentFixture()
        environment.identifier = "com.spotify.client"
        XCTAssertEqual(ShareSourceContext.bundleIdentifier(fromScreenshotEnvironment: environment), "com.spotify.client")
    }

    func testScreenshotEnvironmentNeverGuessesAnAppWhenMetadataIsMissing() {
        let environment = ScreenshotEnvironmentFixture()
        for identifier in [nil, "unknown", "spotify://", "com.apple.ScreenshotServicesService", "com.josh.cod", "com.josh.cod.share"] {
            environment.identifier = identifier
            XCTAssertNil(ShareSourceContext.bundleIdentifier(fromScreenshotEnvironment: environment))
        }
        XCTAssertNil(ShareSourceContext.bundleIdentifier(fromScreenshotEnvironment: NSObject()))
        XCTAssertNil(ShareSourceContext.screenshotOrigin(from: []))
    }

    @MainActor
    func testDiscardedReturnContextDoesNotSurviveUserRestoration() {
        SourceAppReturn.shared.capture(sourceBundleIdentifier: "com.apple.ScreenshotServicesService")
        XCTAssertTrue(SourceAppReturn.shared.shouldReturnHome)
        SourceAppReturn.shared.discard()
        XCTAssertFalse(SourceAppReturn.shared.shouldReturnHome)
    }

    @MainActor
    func testHandoffClaimsImageExactlyOnceWithoutChangingCopiedText() throws {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        pasteboard.items = ShareFloatHandoff.itemsWithPayload(
            [["public.utf8-plain-text": "keep this text"]],
            imageData: try XCTUnwrap(image.pngData()),
            sourceBundleIdentifier: "com.apple.mobileslideshow"
        )
        let payload = try XCTUnwrap(ShareFloatHandoff.takePayload(from: pasteboard))
        XCTAssertEqual(payload.image.pixelSize, CGSize(width: 12, height: 8))
        XCTAssertEqual(payload.sourceBundleIdentifier, "com.apple.mobileslideshow")
        XCTAssertNil(ShareFloatHandoff.takePayload(from: pasteboard))
        XCTAssertEqual(pasteboard.string, "keep this text")
        XCTAssertNil(pasteboard.data(forPasteboardType: ShareFloatHandoff.sourcePasteboardType))
    }

    @MainActor
    func testMalformedHandoffIsRemovedWithoutDeletingUserClipboard() {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        pasteboard.items = ShareFloatHandoff.itemsWithPayload(
            [["public.utf8-plain-text": "keep this text"]], imageData: Data([0, 1, 2]),
            sourceBundleIdentifier: "com.apple.mobileslideshow"
        )
        XCTAssertNil(ShareFloatHandoff.takePayload(from: pasteboard))
        XCTAssertNil(pasteboard.data(forPasteboardType: ShareFloatHandoff.pasteboardType))
        XCTAssertNil(pasteboard.data(forPasteboardType: ShareFloatHandoff.sourcePasteboardType))
        XCTAssertEqual(pasteboard.string, "keep this text")
    }

    @MainActor
    func testTemporaryScreenshotHostAndHomeUseHomeFallback() {
        XCTAssertTrue(SourceAppReturn.requiresHomeFallback(for: "com.apple.ScreenshotServicesService"))
        XCTAssertTrue(SourceAppReturn.requiresHomeFallback(for: "com.apple.springboard"))
    }

    @MainActor
    func testNormalAppsAndUnknownSourcesAreNotClassifiedAsScreenshotPreview() {
        for source in ["com.apple.mobileslideshow", "com.apple.mobilesafari", "com.apple.shortcuts", "com.example.ScreenshotEditor"] {
            XCTAssertFalse(SourceAppReturn.requiresHomeFallback(for: source))
        }
        XCTAssertFalse(SourceAppReturn.requiresHomeFallback(for: nil))
    }

    @MainActor
    func testScreenshotPreviewReturnsWithoutReactivatingItsService() async {
        SourceAppReturn.shared.capture(sourceBundleIdentifier: "com.apple.ScreenshotServicesService")
        XCTAssertTrue(SourceAppReturn.shared.shouldReturnHome)
        let dispatched = await SourceAppReturn.shared.returnToSource()
        XCTAssertFalse(dispatched)
        XCTAssertFalse(SourceAppReturn.shared.shouldReturnHome, "The consumed screenshot origin must not leak into the next float")
    }

    @MainActor
    func testStatusBarProbeNeverInvokesLazyUIKitStyleGetters() {
        let owner = StatusBarGetterTrapFixture()
        XCTAssertNil(SourceAppReturn.existingStatusBar(from: owner))
        XCTAssertEqual(owner.getterCalls, 0)
    }

    @MainActor
    func testReturnContextCaptureIsSafeWithoutAStatusBar() {
        SourceAppReturn.shared.capture(sourceBundleIdentifier: "com.apple.mobileslideshow")
        SourceAppReturn.shared.capture()
    }

    func testModernSceneResolvesExistingHostProcessHandle() {
        let scene = ModernSceneLookupFixture()
        scene.frontBoardScene.process.handle.identifier = "com.apple.mobileslideshow"
        XCTAssertEqual(ShareSourceContext.bundleIdentifier(fromSceneObject: scene), "com.apple.mobileslideshow")
    }

    func testModernSceneDoesNotMistakeSpringBoardForOriginalHomeScreen() {
        let scene = ModernSceneLookupFixture()
        for identifier in ["com.apple.springboard", "com.apple.UIKit.ShareSheet", "com.josh.cod", "com.josh.cod.share", "photos://", "unknown"] {
            scene.frontBoardScene.process.handle.identifier = identifier
            XCTAssertNil(ShareSourceContext.bundleIdentifier(fromSceneObject: scene))
        }
    }

    func testModernSceneMissingGetterIsSafe() {
        XCTAssertNil(ShareSourceContext.bundleIdentifier(fromSceneObject: NSObject()))
    }

    @MainActor
    func testHostLookupTraversesControllerParents() {
        let root = HostLookupController()
        root.hostIdentifier = "com.apple.mobileslideshow"
        let middle = UIViewController()
        let child = UIViewController()
        root.addChild(middle)
        middle.addChild(child)
        XCTAssertEqual(ShareSourceContext.bundleIdentifier(from: child), "com.apple.mobileslideshow")
    }

    @MainActor
    func testHostLookupTraversesTheResponderChainWithoutAParent() {
        let host = HostLookupController()
        host.hostIdentifier = "com.apple.mobileslideshow"
        let child = HostLookupController()
        child.nextResponderForTest = host
        XCTAssertEqual(ShareSourceContext.bundleIdentifier(from: child), "com.apple.mobileslideshow")
    }

    @MainActor
    func testUnknownResponderCycleIsBounded() {
        let first = HostLookupController()
        let second = HostLookupController()
        first.nextResponderForTest = second
        second.nextResponderForTest = first
        defer { first.nextResponderForTest = nil; second.nextResponderForTest = nil }
        XCTAssertNil(ShareSourceContext.bundleIdentifier(from: first))
    }

    func testHostedSceneIdentifiesOnlyItsExplicitHost() {
        XCTAssertEqual(
            ShareSourceContext.bundleIdentifier(fromHostedSceneIdentifier: "UISceneHosting-com.apple.mobileslideshow:UIHostedScene-com.josh.cod.share-123"),
            "com.apple.mobileslideshow"
        )
        XCTAssertEqual(
            ShareSourceContext.bundleIdentifier(fromHostedSceneIdentifier: "UISceneHosting-com.apple.springboard:UIHostedScene-com.josh.cod.share-123"),
            "com.apple.springboard"
        )
    }

    func testHostedSceneRejectsUnknownAndMalformedFormats() {
        for value in ["com.apple.mobileslideshow", "UIHostedScene-com.josh.cod.share-123", "UISceneHosting-:UIHostedScene-cod", "UISceneHosting-photos://:UIHostedScene-cod", "UISceneHosting-com.apple.photos:UIHostedScene-", "prefix UISceneHosting-com.apple.photos:UIHostedScene-cod"] {
            XCTAssertNil(ShareSourceContext.bundleIdentifier(fromHostedSceneIdentifier: value))
        }
    }

    func testSourceIdentifierRejectsURLsAndMalformedValues() {
        XCTAssertTrue(ShareSourceContext.isValid("com.apple.mobileslideshow"))
        XCTAssertTrue(ShareSourceContext.isValid("com.apple.springboard"))
        for value in ["", "photos://", "com.apple.photos?url=bad", "com.apple.photos\n", "unknown", String(repeating: "a", count: 256) + ".app"] {
            XCTAssertFalse(ShareSourceContext.isValid(value))
        }
    }

    func testHandoffAddsSourceWithoutRemovingCopiedText() {
        let image = Data([1, 2, 3])
        let items = ShareFloatHandoff.itemsWithPayload(
            [["public.utf8-plain-text": "existing clipboard"]],
            imageData: image,
            sourceBundleIdentifier: "com.apple.mobileslideshow"
        )
        XCTAssertEqual(items[0]["public.utf8-plain-text"] as? String, "existing clipboard")
        XCTAssertEqual(items[0][ShareFloatHandoff.pasteboardType] as? Data, image)
        XCTAssertEqual(items[0][ShareFloatHandoff.sourcePasteboardType] as? Data, Data("com.apple.mobileslideshow".utf8))
    }

    func testUnknownSourceCannotReuseAnEarlierPhotosDestination() {
        let items = ShareFloatHandoff.itemsWithPayload(
            [[ShareFloatHandoff.sourcePasteboardType: Data("com.apple.mobileslideshow".utf8)],
             ["public.utf8-plain-text": "keep", ShareFloatHandoff.sourcePasteboardType: Data("com.apple.mobileslideshow".utf8)]],
            imageData: Data([4]),
            sourceBundleIdentifier: nil
        )
        XCTAssertTrue(items.allSatisfy { $0[ShareFloatHandoff.sourcePasteboardType] == nil })
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["public.utf8-plain-text"] as? String, "keep")
    }

    func testConsumingPayloadPreservesOtherClipboardRepresentations() {
        let original: [[String: Any]] = [["public.utf8-plain-text": "keep"], ["public.url": "https://example.com"]]
        let stored = ShareFloatHandoff.itemsWithPayload(original, imageData: Data([7]), sourceBundleIdentifier: "com.apple.springboard")
        let restored = ShareFloatHandoff.itemsWithoutPayload(stored)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0]["public.utf8-plain-text"] as? String, "keep")
        XCTAssertEqual(restored[1]["public.url"] as? String, "https://example.com")
    }
}

private final class ScreenshotEnvironmentFixture: NSObject {
    var identifier: String?
    @objc(currentApplicationBundleID) func capturedAppForTest() -> NSString? { identifier as NSString? }
}

private final class StatusBarGetterTrapFixture: NSObject {
    var getterCalls = 0
    @objc(statusBar) func statusBarForTest() -> NSObject? { getterCalls += 1; return nil }
    @objc(_statusBar) func privateStatusBarForTest() -> NSObject? { getterCalls += 1; return nil }
}

private final class ModernSceneLookupFixture: NSObject {
    let frontBoardScene = ModernFrontBoardLookupFixture()
    @objc(_FBSScene) func sceneForTest() -> NSObject { frontBoardScene }
}

private final class ModernFrontBoardLookupFixture: NSObject {
    let process = ModernProcessLookupFixture()
    @objc(hostProcess) func processForTest() -> NSObject { process }
}

private final class ModernProcessLookupFixture: NSObject {
    @objc let handle = ModernHandleLookupFixture()
}

private final class ModernHandleLookupFixture: NSObject {
    var identifier: String?
    @objc(bundleIdentifier) func identifierForTest() -> NSString? { identifier as NSString? }
}

private final class HostLookupController: UIViewController {
    var hostIdentifier: String?
    var nextResponderForTest: UIResponder?
    override var next: UIResponder? { nextResponderForTest }

    @objc(_hostBundleID)
    func hostBundleForTest() -> NSString? { hostIdentifier as NSString? }
}
#endif
