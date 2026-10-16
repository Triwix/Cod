import AppIntents
import CoreVideo
import UserNotifications
import XCTest
@testable import Cod

final class FloatEntryPointTests: XCTestCase {
    @MainActor
    func testControlDeliversLatestScreenshotRequestWithoutReadingClipboard() async throws {
        IntentInbox.shared.wantsFloatLatest = false
        defer { IntentInbox.shared.wantsFloatLatest = false }
        _ = try await FloatControlIntent(target: .latestScreenshot).perform()
        XCTAssertTrue(IntentInbox.shared.wantsFloatLatest)
        XCTAssertEqual(FloatControlIntent.authenticationPolicy, .requiresAuthentication)
    }

    @MainActor
    func testImageIntentDeliversTheSuppliedImageNotLatestPhoto() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 37, height: 19)).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 37, height: 19))
        }
        var intent = FloatWithCodIntent()
        intent.image = IntentFile(data: try XCTUnwrap(image.pngData()), filename: "shared.png", type: .png)
        defer { IntentInbox.shared.pendingFloatImage = nil }
        _ = try await intent.perform()
        XCTAssertEqual(IntentInbox.shared.pendingFloatImage?.pixelSize, image.pixelSize)
        XCTAssertEqual(pixels(IntentInbox.shared.pendingFloatImage), pixels(image))
    }

    private func pixels(_ image: UIImage?) -> Data? {
        guard let buffer = image?.pixelBuffer() else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        var result = Data()
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            result.append(bytes.assumingMemoryBound(to: UInt8.self).advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)), count: CVPixelBufferGetWidth(buffer) * 4)
        }
        return result
    }

    func testNotificationOnlyContainsOneRequestIdentifierAndNoImage() {
        let id = UUID()
        let request = ShareFloatNotificationPayload.request(for: id)
        XCTAssertEqual(request.content.userInfo.count, 1)
        XCTAssertTrue(request.content.attachments.isEmpty)
        XCTAssertNil(request.content.sound)
        XCTAssertEqual(ShareFloatNotificationPayload.requestID(
            identifier: request.identifier, category: request.content.categoryIdentifier,
            userInfo: request.content.userInfo
        ), id)
        XCTAssertNil(ShareFloatNotificationPayload.requestID(
            identifier: "other", category: request.content.categoryIdentifier,
            userInfo: request.content.userInfo
        ))
        XCTAssertNil(ShareFloatNotificationPayload.requestID(
            identifier: request.identifier, category: "other",
            userInfo: request.content.userInfo
        ))
        XCTAssertNil(ShareFloatNotificationPayload.requestID(
            identifier: request.identifier, category: request.content.categoryIdentifier,
            userInfo: [ShareFloatNotificationPayload.requestKey: "not-a-uuid"]
        ))
    }
}
